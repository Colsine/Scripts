#!/usr/bin/env bash
#===============================================================================
# DNS 延迟优化脚本
# 功能：检测当前 DNS、对比 1.1.1.1 与 8.8.8.8 的延迟，自动切换到最优 DNS
# 兼容：Ubuntu / Debian / CentOS / RHEL / Fedora / Arch 等主流 Linux 发行版
# 日期：2026-07-15
#===============================================================================

set -euo pipefail  # 严格模式：遇错退出、未定义变量报错、管道中间失败也报错

#-------------------------------------------------------------------------------
# 颜色定义（用于终端输出美化）
#-------------------------------------------------------------------------------
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'

#-------------------------------------------------------------------------------
# 全局常量
#-------------------------------------------------------------------------------
readonly DNS_CLOUDFLARE='1.1.1.1'       # Cloudflare 公共 DNS
readonly DNS_GOOGLE='8.8.8.8'           # Google 公共 DNS
readonly PING_COUNT=10                   # 每个 IP ping 的次数
readonly RESOLV_CONF='/etc/resolv.conf'  # DNS 配置文件路径
readonly BACKUP_SUFFIX='.bak'            # 备份文件后缀

#-------------------------------------------------------------------------------
# 工具函数
#-------------------------------------------------------------------------------

# 打印带颜色的信息
print_info() {
    echo -e "${COLOR_CYAN}[信息]${COLOR_RESET} $*"
}

print_success() {
    echo -e "${COLOR_GREEN}[成功]${COLOR_RESET} $*"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[警告]${COLOR_RESET} $*"
}

print_error() {
    echo -e "${COLOR_RED}[错误]${COLOR_RESET} $*"
}

print_header() {
    echo ""
    echo -e "${COLOR_BOLD}========== $* ==========${COLOR_RESET}"
    echo ""
}

# 打印分隔线
print_separator() {
    echo "-----------------------------------------------------------------------"
}

#-------------------------------------------------------------------------------
# 第一步：获取当前系统 DNS 服务器地址
#-------------------------------------------------------------------------------
get_current_dns() {
    print_header "第一步：获取当前系统 DNS"

    local current_dns=""

    # 方法1：读取 /etc/resolv.conf（最通用的方式）
    # 兼容传统 resolv.conf、NetworkManager 写入的 resolv.conf、以及 systemd-resolved 的 stub 模式
    if [[ -f "$RESOLV_CONF" ]] && [[ -r "$RESOLV_CONF" ]]; then
        # 提取所有 nameserver 行，取第一个 IP 作为首选 DNS
        # awk 匹配 "nameserver" 开头的行，$2 即 IP 地址；head -n1 取第一个
        current_dns=$(awk '/^nameserver/ {print $2; exit}' "$RESOLV_CONF" 2>/dev/null || true)
    fi

    # 方法2：如果 resolv.conf 返回的是 127.x.x.x（systemd-resolved stub 模式），
    #       尝试通过 resolvectl/systemd-resolve 获取上游真实 DNS
    if [[ -z "$current_dns" ]] || [[ "$current_dns" == 127.* ]] || [[ "$current_dns" == "::1" ]]; then
        # systemd-resolved 新接口 (Ubuntu 18.04+, Debian 10+, CentOS 8+)
        if command -v resolvectl &>/dev/null; then
            # 获取默认网卡的 DNS 服务器（通常是 eth0 或 ens 开头的第一个接口）
            local dns_line
            dns_line=$(resolvectl dns 2>/dev/null | grep -v '^Link' | grep -v '^$' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
            if [[ -n "$dns_line" ]]; then
                current_dns="$dns_line"
            fi
        fi

        # systemd-resolved 旧接口 (Ubuntu 16.04 等)
        if [[ -z "$current_dns" ]] && command -v systemd-resolve &>/dev/null; then
            local dns_line
            dns_line=$(systemd-resolve --status 2>/dev/null | grep 'DNS Servers' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
            if [[ -n "$dns_line" ]]; then
                current_dns="$dns_line"
            fi
        fi
    fi

    # 方法3：通过 NetworkManager 的 nmcli 获取
    if [[ -z "$current_dns" ]] && command -v nmcli &>/dev/null; then
        # 获取活跃连接的首个 DNS
        current_dns=$(nmcli dev show 2>/dev/null | grep 'IP4.DNS' | awk '{print $2}' | head -n1 || true)
    fi

    # 结果处理
    if [[ -z "$current_dns" ]]; then
        print_warning "无法检测到当前 DNS 服务器地址"
        print_info "请确保 DNS 配置正常，脚本将继续运行但无法进行对比"
        CURRENT_DNS=""
    else
        print_info "当前首选 DNS 服务器：${COLOR_BOLD}${current_dns}${COLOR_RESET}"
        CURRENT_DNS="$current_dns"
    fi
}

#-------------------------------------------------------------------------------
# 第二步：Ping 测试延迟（提取平均延迟）
#-------------------------------------------------------------------------------

# 对指定 IP 进行 ping 测试，返回平均延迟（毫秒数）
# 参数：$1 - 目标 IP 地址
# 输出：平均延迟数字（如 "12.345"）；失败时返回空字符串
ping_test() {
    local target_ip="$1"
    local ping_output
    local avg_latency

    # ping 参数说明：
    #   -c N     发送 N 个包
    #   -W N     单次等待超时秒数
    #   -i 0.2   发包间隔 0.2 秒（加快测试速度）
    # 注意：某些系统 -W 含义不同，因此用 timeout 命令兜底
    if ping_output=$(ping -c "$PING_COUNT" -W 2 -i 0.2 "$target_ip" 2>&1); then
        # ping 成功，从统计行提取平均延迟
        # 典型输出行: "rtt min/avg/max/mdev = 1.234/5.678/10.111/2.345 ms"
        # 使用 awk 以 '/' 和 '.' 为分隔符提取 avg
        avg_latency=$(echo "$ping_output" | awk -F'/' '/^rtt|^round-trip/ {print $5}')
        if [[ -z "$avg_latency" ]]; then
            # 另一种格式兼容（某些系统的 rtt 行格式不同）
            avg_latency=$(echo "$ping_output" | awk -F' = ' '/avg/ {print $2}' | awk '{print $1}' | sed 's/ms//; s/ //g')
        fi
    fi

    # 返回平均延迟（如果获取失败则为空）
    echo "${avg_latency:-}"
}

# 对两个公共 DNS 进行延迟测试
test_dns_latency() {
    print_header "第二步：测试公共 DNS 延迟"

    local latency_cf   # Cloudflare 1.1.1.1 延迟
    local latency_gg   # Google 8.8.8.8 延迟

    print_info "正在 ping ${DNS_CLOUDFLARE} (Cloudflare)..."
    latency_cf=$(ping_test "$DNS_CLOUDFLARE")

    if [[ -n "$latency_cf" ]]; then
        print_success "${DNS_CLOUDFLARE} 平均延迟：${COLOR_BOLD}${latency_cf} ms${COLOR_RESET}"
    else
        print_warning "${DNS_CLOUDFLARE} 无法连通，可能是网络问题或防火墙拦截"
    fi

    print_info "正在 ping ${DNS_GOOGLE} (Google)..."
    latency_gg=$(ping_test "$DNS_GOOGLE")

    if [[ -n "$latency_gg" ]]; then
        print_success "${DNS_GOOGLE} 平均延迟：${COLOR_BOLD}${latency_gg} ms${COLOR_RESET}"
    else
        print_warning "${DNS_GOOGLE} 无法连通，可能是网络问题或防火墙拦截"
    fi

    # 存储结果供后续使用
    LATENCY_CF="$latency_cf"
    LATENCY_GG="$latency_gg"
}

#-------------------------------------------------------------------------------
# 第三步：对比分析
#-------------------------------------------------------------------------------

# 对比两个公共 DNS 的延迟，找出更优的；再与当前 DNS 对比
compare_dns() {
    print_header "第三步：延迟对比分析"

    # 情况1：两个公共 DNS 都无法 ping 通
    if [[ -z "$LATENCY_CF" ]] && [[ -z "$LATENCY_GG" ]]; then
        print_error "两个公共 DNS (${DNS_CLOUDFLARE} / ${DNS_GOOGLE}) 均无法连通！"
        print_info "请检查网络连接或防火墙设置后重试。"
        exit 1
    fi

    # 确定两个公共 DNS 中延迟更低的那个
    local best_public_dns=""
    local best_public_latency=""

    if [[ -z "$LATENCY_CF" ]]; then
        # Cloudflare 不通，只能用 Google
        best_public_dns="$DNS_GOOGLE"
        best_public_latency="$LATENCY_GG"
        print_warning "${DNS_CLOUDFLARE} 无法连通，仅以 ${DNS_GOOGLE} 作为候选"
    elif [[ -z "$LATENCY_GG" ]]; then
        # Google 不通，只能用 Cloudflare
        best_public_dns="$DNS_CLOUDFLARE"
        best_public_latency="$LATENCY_CF"
        print_warning "${DNS_GOOGLE} 无法连通，仅以 ${DNS_CLOUDFLARE} 作为候选"
    else
        # 两者都通，用 awk 比较数值大小
        if (( $(echo "$LATENCY_CF < $LATENCY_GG" | bc -l 2>/dev/null || echo "$LATENCY_CF $LATENCY_GG" | awk '{if($1<$2) print 1; else print 0}') )); then
            best_public_dns="$DNS_CLOUDFLARE"
            best_public_latency="$LATENCY_CF"
        else
            best_public_dns="$DNS_GOOGLE"
            best_public_latency="$LATENCY_GG"
        fi
    fi

    print_info "公共 DNS 延迟对比："
    [[ -n "$LATENCY_CF" ]] && echo "  - ${DNS_CLOUDFLARE} (Cloudflare): ${LATENCY_CF} ms"
    [[ -n "$LATENCY_GG" ]] && echo "  - ${DNS_GOOGLE} (Google):     ${LATENCY_GG} ms"
    echo ""
    print_info "延迟最低的公共 DNS：${COLOR_BOLD}${best_public_dns}${COLOR_RESET} (${best_public_latency} ms)"

    # 如果没有当前 DNS 信息，跳过对比
    if [[ -z "$CURRENT_DNS" ]]; then
        print_warning "无法获取当前 DNS，直接推荐使用 ${best_public_dns}"
        BEST_PUBLIC_DNS="$best_public_dns"
        BEST_PUBLIC_LATENCY="$best_public_latency"
        return
    fi

    print_separator
    print_info "当前 DNS：${COLOR_BOLD}${CURRENT_DNS}${COLOR_RESET}"
    print_info "最优公共 DNS：${COLOR_BOLD}${best_public_dns}${COLOR_RESET} (${best_public_latency} ms)"

    # 判断当前 DNS 是否就是最优公共 DNS
    if [[ "$CURRENT_DNS" == "$best_public_dns" ]]; then
        print_separator
        print_success "✅ 当前已是延迟最优的 DNS，无需修改！"
        exit 0
    else
        # 当前 DNS 不是最优公共 DNS，但如果当前 DNS 也是某个公共 DNS，情况就简单
        # 否则需要提示切换
        print_separator
        print_warning "当前 DNS (${CURRENT_DNS}) 不是延迟最低的公共 DNS"
        print_info "建议将 DNS 切换为：${COLOR_BOLD}${best_public_dns}${COLOR_RESET}"
    fi

    BEST_PUBLIC_DNS="$best_public_dns"
    BEST_PUBLIC_LATENCY="$best_public_latency"
}

#-------------------------------------------------------------------------------
# 第四步：用户交互与权限决策
#-------------------------------------------------------------------------------

ask_user_and_apply() {
    print_header "第四步：决策与修改"

    # 读取用户输入
    local user_choice
    read -r -p "$(echo -e "${COLOR_YELLOW}检测到更优 DNS (${BEST_PUBLIC_DNS})，是否更换？[y/N] ${COLOR_RESET}")" user_choice

    # 将输入转为小写并去除首尾空格，方便匹配
    user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$user_choice" in
        y|yes)
            apply_dns_change
            ;;
        n|no|"")
            print_info "操作已取消，未修改任何配置。"
            exit 0
            ;;
        *)
            print_warning "无效输入 '${user_choice}'，视为取消操作。"
            print_info "操作已取消，未修改任何配置。"
            exit 0
            ;;
    esac
}

#-------------------------------------------------------------------------------
# 第五步：执行 DNS 修改
#-------------------------------------------------------------------------------

apply_dns_change() {
    print_separator

    # 检查是否有 root 权限（EUID 为 0 表示 root）
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        print_error "修改 DNS 需要 root 权限，当前未以 root 身份运行。"
        print_info "请使用以下命令重新运行："
        echo ""
        echo -e "  ${COLOR_BOLD}sudo bash $0${COLOR_RESET}"
        echo ""
        print_info "或使用："
        echo ""
        echo -e "  ${COLOR_BOLD}sudo -i${COLOR_RESET}  先切换到 root，再运行脚本"
        echo ""
        exit 1
    fi

    # 确认配置文件存在
    if [[ ! -f "$RESOLV_CONF" ]]; then
        print_error "DNS 配置文件 ${RESOLV_CONF} 不存在！"
        exit 1
    fi

    # ---- 自动备份 ----
    local backup_file="${RESOLV_CONF}${BACKUP_SUFFIX}.$(date +%Y%m%d_%H%M%S)"
    print_info "正在备份当前 DNS 配置..."
    if cp -a "$RESOLV_CONF" "$backup_file"; then
        print_success "已备份至：${backup_file}"
    else
        print_error "备份失败，取消修改操作！"
        exit 1
    fi

    # ---- 检测配置文件管理方式 ----
    # 判断 resolv.conf 的类型，决定修改方式
    local modified=false

    # 方式1：检查是否为 systemd-resolved 管理的符号链接
    if [[ -L "$RESOLV_CONF" ]]; then
        local link_target
        link_target=$(readlink -f "$RESOLV_CONF" 2>/dev/null || true)
        if [[ "$link_target" == *"systemd"* ]] || [[ "$link_target" == *"stub-resolv"* ]]; then
            print_info "检测到 systemd-resolved 管理 DNS，使用 resolvectl 方式修改..."
            # 通过 resolvectl 设置全局 DNS（适用于所有接口）
            if command -v resolvectl &>/dev/null; then
                # 获取所有非 lo 的网络接口
                local interfaces
                interfaces=$(ip -o link show up 2>/dev/null | grep -v 'lo' | awk -F': ' '{print $2}' | grep -v 'docker\|veth\|br-\|virbr' || true)
                for iface in $interfaces; do
                    if resolvectl dns "$iface" "$BEST_PUBLIC_DNS" 2>/dev/null; then
                        print_info "  已设置接口 ${iface} 的 DNS 为 ${BEST_PUBLIC_DNS}"
                        modified=true
                    fi
                done
                # 如果未能按接口设置，尝试全局设置
                if [[ "$modified" == false ]]; then
                    # 设置默认接口
                    resolvectl dns eth0 "$BEST_PUBLIC_DNS" 2>/dev/null || \
                    resolvectl dns ens33 "$BEST_PUBLIC_DNS" 2>/dev/null || \
                    resolvectl dns ens3 "$BEST_PUBLIC_DNS" 2>/dev/null || true
                    modified=true
                fi
            fi
        fi
    fi

    # 方式2：检查是否为 NetworkManager 管理
    if [[ "$modified" == false ]] && command -v nmcli &>/dev/null; then
        # 检查 NetworkManager 是否在运行
        if systemctl is-active NetworkManager &>/dev/null 2>&1 || pidof NetworkManager &>/dev/null 2>&1; then
            print_info "检测到 NetworkManager 管理 DNS，使用 nmcli 方式修改..."
            # 获取当前活跃连接
            local active_connections
            active_connections=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
            if [[ -n "$active_connections" ]]; then
                while IFS= read -r conn; do
                    [[ -z "$conn" ]] && continue
                    # 为每个连接设置 DNS（ipv4.dns 和 ipv4.ignore-auto-dns）
                    if nmcli connection modify "$conn" ipv4.dns "$BEST_PUBLIC_DNS" 2>/dev/null && \
                       nmcli connection modify "$conn" ipv4.ignore-auto-dns yes 2>/dev/null; then
                        print_info "  已修改连接 '${conn}' 的 DNS 配置"
                        modified=true
                    fi
                done <<< "$active_connections"
                # 重新激活连接使配置生效
                if [[ "$modified" == true ]]; then
                    print_info "正在重新激活网络连接以应用更改..."
                    while IFS= read -r conn; do
                        [[ -z "$conn" ]] && continue
                        nmcli connection down "$conn" &>/dev/null && \
                        nmcli connection up "$conn" &>/dev/null && \
                        print_info "  连接 '${conn}' 已刷新"
                    done <<< "$active_connections"
                fi
            fi
        fi
    fi

    # 方式3：传统直接修改 /etc/resolv.conf（适用于静态配置或 chattr -i 后的文件）
    if [[ "$modified" == false ]]; then
        print_info "使用传统方式直接修改 ${RESOLV_CONF}..."

        # 检查是否有不可变标志（chattr +i），如果有则先移除
        if command -v lsattr &>/dev/null; then
            if lsattr "$RESOLV_CONF" 2>/dev/null | grep -q '^....i'; then
                print_warning "检测到 ${RESOLV_CONF} 有不可变标志 (immutable)，正在移除..."
                chattr -i "$RESOLV_CONF" || {
                    print_error "无法移除不可变标志，修改失败！"
                    exit 1
                }
            fi
        fi

        # 写入新配置：保留 comments 和 options，替换 nameserver
        # 策略：在文件开头添加新的 nameserver，注释掉旧的 nameserver
        local tmp_file
        tmp_file=$(mktemp) || {
            print_error "无法创建临时文件！"
            exit 1
        }

        # 写入新的首选 nameserver + 保留原来的内容（注释掉旧 nameserver）
        {
            echo "# DNS 配置已修改（备份文件：${backup_file}）"
            echo "nameserver ${BEST_PUBLIC_DNS}"
            echo ""
            # 保留原文件的所有非 nameserver 行，注释掉旧的 nameserver 行
            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*nameserver ]]; then
                    echo "# [已禁用] ${line}"
                elif [[ "$line" =~ ^[[:space:]]*#.*[Dd][Nn][Ss].*optimizer ]]; then
                    continue  # 跳过上次脚本添加的注释行，避免重复
                else
                    echo "$line"
                fi
            done < "$RESOLV_CONF"
        } > "$tmp_file"

        # 用新配置替换旧配置
        if cp "$tmp_file" "$RESOLV_CONF"; then
            modified=true
        else
            print_error "写入 ${RESOLV_CONF} 失败！"
            rm -f "$tmp_file"
            exit 1
        fi
        rm -f "$tmp_file"
    fi

    # ---- 验证修改结果 ----
    if [[ "$modified" == true ]]; then
        print_separator
        print_success "🎉 DNS 已成功切换至：${COLOR_BOLD}${BEST_PUBLIC_DNS}${COLOR_RESET}"

        # 显示验证信息
        print_info "验证当前 DNS 配置："
        if command -v resolvectl &>/dev/null; then
            resolvectl dns 2>/dev/null | grep -v '^Link' | grep -v '^$' | head -5 || true
        elif [[ -r "$RESOLV_CONF" ]]; then
            grep '^nameserver' "$RESOLV_CONF" 2>/dev/null | head -3
        fi

        print_info "如需恢复，备份文件位于：${backup_file}"
    else
        print_warning "DNS 修改未完全生效，请手动检查配置。"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 主函数：串联所有步骤
#-------------------------------------------------------------------------------

main() {
    # 打印脚本标题
    echo ""
    echo -e "${COLOR_BOLD}╔══════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD}║        DNS 延迟优化脚本                           ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD}║        对比 Cloudflare vs Google 并自动切换       ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD}╚══════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""

    # 检查基本依赖
    local missing_deps=()
    for cmd in ping awk grep sed; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少必要的系统命令：${missing_deps[*]}"
        print_info "请安装后再运行本脚本。"
        exit 1
    fi

    # 步骤1：获取当前 DNS
    get_current_dns

    # 步骤2：测试公共 DNS 延迟
    test_dns_latency

    # 步骤3：对比分析
    compare_dns

    # 步骤4：询问用户并执行（仅在需要时才询问）
    ask_user_and_apply
}

#-------------------------------------------------------------------------------
# 脚本入口
#-------------------------------------------------------------------------------
main "$@"
