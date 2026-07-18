#!/usr/bin/env bash
# Ubuntu/Debian VPS firewall and SSH protection setup.

set -Eeuo pipefail

readonly PRESET_TCP_PORTS="80 443"
readonly PRESET_UDP_PORTS="10000:10010"
readonly UFW_STATE_DIR="/var/lib/safevps"
readonly UFW_STATE_FILE="${UFW_STATE_DIR}/ufw.rules"
readonly FAIL2BAN_CONFIG="/etc/fail2ban/jail.d/99-safevps.local"

declare -a SSH_PORTS_TO_PROTECT=()
SSH_CLIENT_IP=""
CURRENT_SSH_PORT=""
DOCKER_WARNING=0
SAFEVPS_LANG="${SAFEVPS_LANG:-zh}"
SHOW_HELP=0

msg() {
  local key="$1"
  shift

  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    case "$key" in
      warning_prefix) printf 'Warning' ;;
      error_prefix) printf 'Error' ;;
      bool_invalid) printf '%s must be 0 or 1.' "$1" ;;
      invalid_port) printf 'Invalid port "%s". Use space-separated ports or ranges, for example: 80 443 8000:8010.' "$1" ;;
      port_out_of_range) printf 'Port "%s" is outside 1-65535, or the range start is greater than its end.' "$1" ;;
      fail2ban_time_invalid) printf '%s has an invalid format. Use a positive value such as 600, 10m, 1h, or 1d.' "$1" ;;
      fail2ban_time_invalid_permanent) printf '%s has an invalid format. Use a positive value such as 600, 10m, 1h, or 1d, or -1 for a permanent ban.' "$1" ;;
      ssh_port_invalid) printf 'SSH_PORT must be a single port between 1 and 65535.' ;;
      ssh_port_fallback) printf 'Could not detect an SSH listening port. Falling back to 22; verify it before continuing.' ;;
      udp_range_deprecated) printf 'UDP_RANGE has been renamed to UDP_PORTS. The legacy value will be used for this run.' ;;
      port_mode_invalid) printf 'PORT_MODE must be minimal, preset, or custom.' ;;
      tcp_ports_invalid) printf 'TCP_PORTS is invalid.' ;;
      udp_ports_invalid) printf 'UDP_PORTS is invalid.' ;;
      fail2ban_profile_invalid) printf 'FAIL2BAN_PROFILE must be relaxed, standard, strict, or custom.' ;;
      ssh_client_missing) printf 'The current SSH client IP was not detected. This can happen when sudo removes SSH environment variables.' ;;
      reset_ufw_warning) printf 'RESET_UFW=1 removes every existing UFW rule, including rules not managed by SafeVPS.' ;;
      canceled) printf 'Canceled.' ;;
      configuring_ufw) printf 'Configuring UFW...' ;;
      current_ufw_status) printf 'Current UFW status:' ;;
      ssh_client_untrusted) printf 'The SSH client IP could not be validated and will not be added to the allowlist.' ;;
      fail2ban_config_failed) printf 'Fail2Ban configuration validation failed. The previous configuration was restored.' ;;
      fail2ban_start_failed) printf 'Fail2Ban failed to start. The previous configuration was restored.' ;;
      fail2ban_not_ready) printf 'Fail2Ban did not become ready in time. The previous configuration was restored.' ;;
      fail2ban_status) printf 'Fail2Ban status:' ;;
      verifying_fail2ban) printf 'Verifying that Fail2Ban writes a real firewall rule...' ;;
      effective_actions) printf 'Effective ban action(s): %s' "$1" ;;
      test_ban_failed) printf 'Fail2Ban could not ban test IP %s.' "$1" ;;
      test_rule_missing) printf 'Fail2Ban recorded the test ban, but %s was not found in nftables, iptables, ipset, or UFW.' "$1" ;;
      test_unban_failed) printf 'Test IP %s was banned but could not be removed automatically. Run: fail2ban-client set sshd unbanip %s' "$1" "$1" ;;
      test_rule_not_cleared) printf 'The test firewall rule for %s was not removed.' "$1" ;;
      test_ban_verified) printf 'Real ban verification passed: the test IP was written to the firewall and removed successfully.' ;;
      root_required) printf 'Run this script as root, for example: sudo bash %s' "$1" ;;
      apt_required) printf 'This script supports Debian/Ubuntu systems that use apt.' ;;
      systemctl_required) printf 'systemctl was not found. This version requires systemd.' ;;
      systemd_inactive) printf 'systemd is not running.' ;;
      docker_detected) printf 'Docker is active. Published container ports may bypass UFW; review container ports and Docker firewall chains separately.' ;;
      unsupported_argument) printf 'Unsupported argument "%s". Use --help for usage.' "$1" ;;
      language_value_required) printf '%s requires zh or en.' "$1" ;;
      language_invalid) printf 'Unsupported language "%s". Use zh or en.' "$1" ;;
      maxretry_invalid) printf 'FAIL2BAN_MAXRETRY must be an integer between 1 and 100.' ;;
      installing_dependencies) printf 'Updating package indexes and installing dependencies...' ;;
      jail_local_found) printf 'Existing /etc/fail2ban/jail.local found. SafeVPS will not overwrite it; check it for legacy global settings.' ;;
      configuring_fail2ban) printf 'Configuring Fail2Ban...' ;;
      docker_final_warning) printf 'UFW status does not include Docker bypass rules. Review docker ps and Docker FORWARD chains.' ;;
      completed) printf 'Completed. Keep this session open and verify SSH from a second terminal before disconnecting.' ;;
      *) printf 'Unknown message key: %s' "$key" ;;
    esac
  else
    case "$key" in
      warning_prefix) printf '警告' ;;
      error_prefix) printf '错误' ;;
      bool_invalid) printf '%s 只能是 0 或 1。' "$1" ;;
      invalid_port) printf '无效端口“%s”，请使用空格分隔的端口或范围，例如：80 443 8000:8010。' "$1" ;;
      port_out_of_range) printf '端口“%s”超出 1-65535，或范围起始值大于结束值。' "$1" ;;
      fail2ban_time_invalid) printf '%s 格式无效，可使用 600、10m、1h、1d 等正数格式。' "$1" ;;
      fail2ban_time_invalid_permanent) printf '%s 格式无效，可使用 600、10m、1h、1d 等正数格式，或使用 -1 永久封禁。' "$1" ;;
      ssh_port_invalid) printf 'SSH_PORT 必须是 1-65535 之间的单个端口。' ;;
      ssh_port_fallback) printf '无法检测 SSH 监听端口，将使用 22；请在继续前确认。' ;;
      udp_range_deprecated) printf 'UDP_RANGE 已更名为 UDP_PORTS，本次仍按兼容参数处理。' ;;
      port_mode_invalid) printf 'PORT_MODE 只能是 minimal、preset 或 custom。' ;;
      tcp_ports_invalid) printf 'TCP_PORTS 配置无效。' ;;
      udp_ports_invalid) printf 'UDP_PORTS 配置无效。' ;;
      fail2ban_profile_invalid) printf 'FAIL2BAN_PROFILE 只能是 relaxed、standard、strict 或 custom。' ;;
      ssh_client_missing) printf '没有检测到当前 SSH 客户端 IP；这在 sudo 清理环境变量时可能发生。' ;;
      reset_ufw_warning) printf 'RESET_UFW=1 会删除所有现有 UFW 规则，包括不属于 SafeVPS 的规则。' ;;
      canceled) printf '已取消。' ;;
      configuring_ufw) printf '配置 UFW...' ;;
      current_ufw_status) printf '当前 UFW 状态：' ;;
      ssh_client_untrusted) printf '无法安全识别 SSH 客户端 IP，不会添加远程白名单。' ;;
      fail2ban_config_failed) printf 'Fail2Ban 配置检查失败，已经恢复原配置。' ;;
      fail2ban_start_failed) printf 'Fail2Ban 启动失败，已经恢复原配置。' ;;
      fail2ban_not_ready) printf 'Fail2Ban 服务未在预期时间内就绪，已经恢复原配置。' ;;
      fail2ban_status) printf 'Fail2Ban 状态：' ;;
      verifying_fail2ban) printf '验证 Fail2Ban 是否真实写入防火墙规则...' ;;
      effective_actions) printf '生效的封禁动作：%s' "$1" ;;
      test_ban_failed) printf 'Fail2Ban 无法封禁测试 IP %s。' "$1" ;;
      test_rule_missing) printf 'Fail2Ban 记录了测试封禁，但 nftables/iptables/ipset/UFW 中没有找到 %s。' "$1" ;;
      test_unban_failed) printf '测试 IP %s 已封禁，但自动解除失败，请手动执行 fail2ban-client set sshd unbanip %s。' "$1" "$1" ;;
      test_rule_not_cleared) printf '测试封禁规则 %s 未从防火墙中清除。' "$1" ;;
      test_ban_verified) printf '真实封禁验证通过：测试 IP 已写入防火墙并成功解除。' ;;
      root_required) printf '请用 root 执行，例如：sudo bash %s' "$1" ;;
      apt_required) printf '这个脚本仅适用于使用 apt 的 Debian/Ubuntu 系统。' ;;
      systemctl_required) printf '没有找到 systemctl；当前版本要求 systemd。' ;;
      systemd_inactive) printf 'systemd 当前没有运行。' ;;
      docker_detected) printf '检测到 Docker。Docker 发布的容器端口可能绕过 UFW，请同时审查容器端口和 Docker 防火墙链。' ;;
      unsupported_argument) printf '不支持的参数“%s”，请使用 --help 查看用法。' "$1" ;;
      language_value_required) printf '%s 需要指定 zh 或 en。' "$1" ;;
      language_invalid) printf '不支持语言“%s”，请使用 zh 或 en。' "$1" ;;
      maxretry_invalid) printf 'FAIL2BAN_MAXRETRY 必须是 1-100 之间的整数。' ;;
      installing_dependencies) printf '更新软件源并安装依赖...' ;;
      jail_local_found) printf '发现现有 /etc/fail2ban/jail.local；SafeVPS 不会覆盖它，请确认其中没有旧版遗留的全局设置。' ;;
      configuring_fail2ban) printf '配置 Fail2Ban...' ;;
      docker_final_warning) printf 'UFW 状态不包含 Docker 绕过规则；请检查 docker ps 和 Docker 的 FORWARD 链。' ;;
      completed) printf '完成。建议保持当前会话，并另开一个终端验证 SSH 后再退出。' ;;
      *) printf '未知消息键：%s' "$key" ;;
    esac
  fi
}

log() {
  printf '==> '
  msg "$@"
  printf '\n'
}

warn() {
  msg warning_prefix >&2
  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    printf ': ' >&2
  else
    printf '：' >&2
  fi
  msg "$@" >&2
  printf '\n' >&2
}

die() {
  msg error_prefix >&2
  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    printf ': ' >&2
  else
    printf '：' >&2
  fi
  msg "$@" >&2
  printf '\n' >&2
  exit 1
}

show_help() {
  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    cat <<'HELP'
SafeVPS - baseline security setup for Ubuntu/Debian VPS hosts

Usage:
  sudo bash setup_server_security.sh [--lang zh|en]

Language:
  --lang zh             Chinese output (default)
  --lang en             English output
  SAFEVPS_LANG=zh|en    Environment variable alternative

Port modes:
  PORT_MODE=minimal     Only allow detected SSH ports (default, recommended)
  PORT_MODE=preset      Allow SSH plus preset TCP 80/443 and UDP 10000:10010
  PORT_MODE=custom      Allow SSH plus TCP_PORTS and UDP_PORTS

Common environment variables:
  SSH_PORT=2222
  TCP_PORTS="80 443 8080:8090"
  UDP_PORTS="51820 10000:10010"
  BLOCK_MAIL_OUT=1
  RESET_UFW=0
  ASSUME_YES=0
  TRUST_CURRENT_SSH_IP=0
  FAIL2BAN_PROFILE=strict
  VERIFY_FAIL2BAN=1

Fail2Ban profiles:
  relaxed   8 failures in 10 minutes, ban for 1 hour
  standard  5 failures in 30 minutes, ban for 24 hours
  strict    3 failures in 1 hour, permanent ban (default)
  custom    Use FAIL2BAN_FINDTIME, FAIL2BAN_MAXRETRY, and FAIL2BAN_BANTIME

Examples:
  sudo bash setup_server_security.sh --lang en
  sudo PORT_MODE=preset bash setup_server_security.sh --lang en
  sudo PORT_MODE=custom TCP_PORTS="80 443 8080" UDP_PORTS="51820" bash setup_server_security.sh --lang en
  sudo ASSUME_YES=1 PORT_MODE=minimal FAIL2BAN_PROFILE=strict bash setup_server_security.sh --lang en
HELP
  else
    cat <<'HELP'
SafeVPS - Ubuntu/Debian VPS 基础安全配置

用法：
  sudo bash setup_server_security.sh [--lang zh|en]

语言：
  --lang zh             中文输出（默认）
  --lang en             英文输出
  SAFEVPS_LANG=zh|en    环境变量替代方式

端口模式：
  PORT_MODE=minimal   只放行检测到的 SSH 端口（默认、推荐）
  PORT_MODE=preset    放行 SSH，并使用预设 TCP 80/443、UDP 10000:10010
  PORT_MODE=custom    放行 SSH，并使用 TCP_PORTS、UDP_PORTS 自定义端口

常用环境变量：
  SSH_PORT=2222
  TCP_PORTS="80 443 8080:8090"
  UDP_PORTS="51820 10000:10010"
  BLOCK_MAIL_OUT=1
  RESET_UFW=0
  ASSUME_YES=0
  TRUST_CURRENT_SSH_IP=0
  FAIL2BAN_PROFILE=strict
  VERIFY_FAIL2BAN=1

Fail2Ban 策略：
  relaxed   10 分钟内失败 8 次，封禁 1 小时
  standard  30 分钟内失败 5 次，封禁 24 小时
  strict    1 小时内失败 3 次，永久封禁（默认）
  custom    使用 FAIL2BAN_FINDTIME、FAIL2BAN_MAXRETRY、FAIL2BAN_BANTIME

示例：
  sudo bash setup_server_security.sh --lang en
  sudo PORT_MODE=preset bash setup_server_security.sh
  sudo PORT_MODE=custom TCP_PORTS="80 443 8080" UDP_PORTS="51820" bash setup_server_security.sh
  sudo ASSUME_YES=1 PORT_MODE=minimal FAIL2BAN_PROFILE=strict bash setup_server_security.sh
HELP
  fi
}

set_language() {
  local requested="${1,,}"
  case "$requested" in
    zh | zh-cn | zh_cn | cn) SAFEVPS_LANG="zh" ;;
    en | en-us | en_us) SAFEVPS_LANG="en" ;;
    *) return 1 ;;
  esac
}

parse_args() {
  local option

  while (($# > 0)); do
    option="$1"
    case "$option" in
      --lang | --language | -l)
        shift
        (($# > 0)) || die language_value_required "$option"
        set_language "$1" || die language_invalid "$1"
        ;;
      --lang=* | --language=*)
        set_language "${option#*=}" || die language_invalid "${option#*=}"
        ;;
      --help | -h)
        SHOW_HELP=1
        ;;
      *)
        die unsupported_argument "$option"
        ;;
    esac
    shift
  done
}

validate_bool() {
  local name="$1"
  local value="$2"
  [[ "$value" == "0" || "$value" == "1" ]] || die bool_invalid "$name"
}

is_valid_single_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1
  ((10#${value} >= 1 && 10#${value} <= 65535))
}

normalize_port_list() {
  local input="$1"
  local token start end result=""
  local -a tokens=()
  local -A seen=()

  read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]{1,5})(:([0-9]{1,5}))?$ ]]; then
      start=$((10#${BASH_REMATCH[1]}))
      end="${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}"
      end=$((10#${end}))
    else
      msg invalid_port "$token" >&2
      printf '\n' >&2
      return 1
    fi

    if ((start < 1 || start > 65535 || end < 1 || end > 65535 || start > end)); then
      msg port_out_of_range "$token" >&2
      printf '\n' >&2
      return 1
    fi

    if [[ -z "${seen[$token]+x}" ]]; then
      seen[$token]=1
      result+="${result:+ }${token}"
    fi
  done

  printf '%s' "$result"
}

validate_fail2ban_time() {
  local name="$1"
  local value="$2"
  local allow_permanent="$3"
  if [[ "$value" == "-1" && "$allow_permanent" == "1" ]]; then
    return 0
  fi
  if [[ "$value" =~ ^([0-9]+)([smhdw])?$ ]] && ((10#${BASH_REMATCH[1]} > 0)); then
    return 0
  fi
  if [[ "$allow_permanent" == "1" ]]; then
    die fail2ban_time_invalid_permanent "$name"
  else
    die fail2ban_time_invalid "$name"
  fi
}

add_ssh_port() {
  local port="$1"
  local existing

  is_valid_single_port "$port" || return 0
  for existing in "${SSH_PORTS_TO_PROTECT[@]}"; do
    [[ "$existing" == "$port" ]] && return 0
  done
  SSH_PORTS_TO_PROTECT+=("$port")
}

detect_ssh_context() {
  local client_ip server_port

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    read -r client_ip _ _ server_port _ <<< "$SSH_CONNECTION"
    SSH_CLIENT_IP="${client_ip:-}"
    if is_valid_single_port "${server_port:-}"; then
      CURRENT_SSH_PORT="$server_port"
    fi
  elif [[ -n "${SSH_CLIENT:-}" ]]; then
    read -r client_ip _ <<< "$SSH_CLIENT"
    SSH_CLIENT_IP="${client_ip:-}"
  fi
}

detect_sshd_ports() {
  local key value

  command -v sshd >/dev/null 2>&1 || return 0
  while read -r key value _; do
    if [[ "$key" == "port" ]] && is_valid_single_port "${value:-}"; then
      add_ssh_port "$value"
    fi
  done < <(sshd -T 2>/dev/null || true)
}

configure_ssh_ports() {
  local requested_port="${SSH_PORT-}"

  detect_ssh_context

  if [[ -n "$requested_port" ]]; then
    is_valid_single_port "$requested_port" || die ssh_port_invalid
    SSH_PORT="$requested_port"
  elif [[ -n "$CURRENT_SSH_PORT" ]]; then
    SSH_PORT="$CURRENT_SSH_PORT"
  else
    detect_sshd_ports
    if ((${#SSH_PORTS_TO_PROTECT[@]} > 0)); then
      SSH_PORT="${SSH_PORTS_TO_PROTECT[0]}"
    else
      SSH_PORT="22"
      warn ssh_port_fallback
    fi
  fi

  add_ssh_port "$SSH_PORT"
  add_ssh_port "$CURRENT_SSH_PORT"
  detect_sshd_ports
}

configure_port_mode() {
  local tcp_was_set=0 udp_was_set=0 choice

  [[ -n "${TCP_PORTS+x}" ]] && tcp_was_set=1
  [[ -n "${UDP_PORTS+x}" ]] && udp_was_set=1

  if ((udp_was_set == 0)) && [[ -n "${UDP_RANGE+x}" ]]; then
    UDP_PORTS="$UDP_RANGE"
    udp_was_set=1
    warn udp_range_deprecated
  fi

  PORT_MODE="${PORT_MODE-}"
  if [[ -z "$PORT_MODE" ]] && ((tcp_was_set == 1 || udp_was_set == 1)); then
    PORT_MODE="custom"
  fi

  if [[ -z "$PORT_MODE" ]]; then
    if [[ "$ASSUME_YES" == "1" ]]; then
      PORT_MODE="minimal"
    else
      if [[ "$SAFEVPS_LANG" == "en" ]]; then
        cat <<'MENU'

Select extra inbound ports:
  1) Minimal (recommended): allow SSH only
  2) Preset: TCP 80/443 and UDP 10000:10010
  3) Custom TCP/UDP ports
MENU
        read -r -p "Select [1]: " choice
      else
        cat <<'MENU'

请选择额外入站端口配置：
  1) 最小模式（推荐）：只放行 SSH
  2) 默认预设：TCP 80/443，UDP 10000:10010
  3) 自定义 TCP/UDP 端口
MENU
        read -r -p "请选择 [1]：" choice
      fi
      PORT_MODE="${choice:-1}"
    fi
  fi

  case "$PORT_MODE" in
    1 | minimal)
      PORT_MODE="minimal"
      TCP_PORTS=""
      UDP_PORTS=""
      ;;
    2 | preset | default)
      PORT_MODE="preset"
      TCP_PORTS="$PRESET_TCP_PORTS"
      UDP_PORTS="$PRESET_UDP_PORTS"
      ;;
    3 | custom)
      PORT_MODE="custom"
      if ((tcp_was_set == 0)) && [[ "$ASSUME_YES" != "1" ]]; then
        if [[ "$SAFEVPS_LANG" == "en" ]]; then
          read -r -p "Allowed TCP ports/ranges (space-separated, empty for none): " TCP_PORTS
        else
          read -r -p "允许的 TCP 端口/范围（空格分隔，留空表示不额外开放）：" TCP_PORTS
        fi
      else
        TCP_PORTS="${TCP_PORTS-}"
      fi
      if ((udp_was_set == 0)) && [[ "$ASSUME_YES" != "1" ]]; then
        if [[ "$SAFEVPS_LANG" == "en" ]]; then
          read -r -p "Allowed UDP ports/ranges (space-separated, empty for none): " UDP_PORTS
        else
          read -r -p "允许的 UDP 端口/范围（空格分隔，留空表示不额外开放）：" UDP_PORTS
        fi
      else
        UDP_PORTS="${UDP_PORTS-}"
      fi
      ;;
    *)
      die port_mode_invalid
      ;;
  esac

  TCP_PORTS="$(normalize_port_list "$TCP_PORTS")" || die tcp_ports_invalid
  UDP_PORTS="$(normalize_port_list "$UDP_PORTS")" || die udp_ports_invalid
}

configure_fail2ban_profile() {
  local values_were_set=0 choice input

  if [[ -n "${FAIL2BAN_BANTIME+x}" || -n "${FAIL2BAN_FINDTIME+x}" || \
    -n "${FAIL2BAN_MAXRETRY+x}" ]]; then
    values_were_set=1
  fi

  FAIL2BAN_PROFILE="${FAIL2BAN_PROFILE-}"
  if [[ -z "$FAIL2BAN_PROFILE" ]] && ((values_were_set == 1)); then
    FAIL2BAN_PROFILE="custom"
  fi

  if [[ -z "$FAIL2BAN_PROFILE" ]]; then
    if [[ "$ASSUME_YES" == "1" ]]; then
      FAIL2BAN_PROFILE="strict"
    else
      if [[ "$SAFEVPS_LANG" == "en" ]]; then
        cat <<'MENU'

Select the SSH failure ban profile:
  1) Relaxed: 8 failures in 10 minutes, ban for 1 hour
  2) Standard: 5 failures in 30 minutes, ban for 24 hours
  3) Strict: 3 failures in 1 hour, permanent ban (default)
  4) Custom
MENU
        read -r -p "Select [3]: " choice
      else
        cat <<'MENU'

请选择 SSH 失败封禁策略：
  1) 宽松：10 分钟内失败 8 次，封禁 1 小时
  2) 标准：30 分钟内失败 5 次，封禁 24 小时
  3) 严格：1 小时内失败 3 次，永久封禁（默认）
  4) 自定义
MENU
        read -r -p "请选择 [3]：" choice
      fi
      FAIL2BAN_PROFILE="${choice:-3}"
    fi
  fi

  case "$FAIL2BAN_PROFILE" in
    1 | relaxed)
      FAIL2BAN_PROFILE="relaxed"
      FAIL2BAN_FINDTIME="10m"
      FAIL2BAN_MAXRETRY="8"
      FAIL2BAN_BANTIME="1h"
      ;;
    2 | standard)
      FAIL2BAN_PROFILE="standard"
      FAIL2BAN_FINDTIME="30m"
      FAIL2BAN_MAXRETRY="5"
      FAIL2BAN_BANTIME="24h"
      ;;
    3 | strict)
      FAIL2BAN_PROFILE="strict"
      FAIL2BAN_FINDTIME="1h"
      FAIL2BAN_MAXRETRY="3"
      FAIL2BAN_BANTIME="-1"
      ;;
    4 | custom)
      FAIL2BAN_PROFILE="custom"
      FAIL2BAN_FINDTIME="${FAIL2BAN_FINDTIME:-1h}"
      FAIL2BAN_MAXRETRY="${FAIL2BAN_MAXRETRY:-3}"
      FAIL2BAN_BANTIME="${FAIL2BAN_BANTIME:--1}"

      if [[ "$ASSUME_YES" != "1" ]]; then
        if [[ "$SAFEVPS_LANG" == "en" ]]; then
          read -r -p "Failure counting window [${FAIL2BAN_FINDTIME}]: " input
        else
          read -r -p "统计失败的时间窗口 [${FAIL2BAN_FINDTIME}]：" input
        fi
        FAIL2BAN_FINDTIME="${input:-$FAIL2BAN_FINDTIME}"
        if [[ "$SAFEVPS_LANG" == "en" ]]; then
          read -r -p "Failures before a ban [${FAIL2BAN_MAXRETRY}]: " input
        else
          read -r -p "触发封禁的失败次数 [${FAIL2BAN_MAXRETRY}]：" input
        fi
        FAIL2BAN_MAXRETRY="${input:-$FAIL2BAN_MAXRETRY}"
        if [[ "$SAFEVPS_LANG" == "en" ]]; then
          read -r -p "Ban duration, -1 means permanent [${FAIL2BAN_BANTIME}]: " input
        else
          read -r -p "封禁时间，-1 表示永久 [${FAIL2BAN_BANTIME}]：" input
        fi
        FAIL2BAN_BANTIME="${input:-$FAIL2BAN_BANTIME}"
      fi
      ;;
    *)
      die fail2ban_profile_invalid
      ;;
  esac
}

join_ssh_ports() {
  local result="" port
  for port in "${SSH_PORTS_TO_PROTECT[@]}"; do
    result+="${result:+,}${port}"
  done
  printf '%s' "$result"
}

show_summary() {
  local protected_ports
  protected_ports="$(join_ssh_ports)"

  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    cat <<INFO

The following configuration will be applied:
  - Port mode: ${PORT_MODE}
  - Primary SSH port: ${SSH_PORT}
  - SSH ports protected against lockout: ${protected_ports}
  - Extra TCP ports: ${TCP_PORTS:-none}
  - Extra UDP ports/ranges: ${UDP_PORTS:-none}
  - UFW defaults: deny incoming, allow outgoing
  - Block outbound mail TCP 25/465/587: ${BLOCK_MAIL_OUT}
  - Reset every existing UFW rule: ${RESET_UFW}
  - Fail2Ban profile: ${FAIL2BAN_PROFILE}
  - Fail2Ban threshold: ${FAIL2BAN_MAXRETRY} failures in ${FAIL2BAN_FINDTIME}, ban for ${FAIL2BAN_BANTIME}
  - Verify a real firewall ban: ${VERIFY_FAIL2BAN}
  - Trust the current SSH client IP: ${TRUST_CURRENT_SSH_IP}
INFO
  else
    cat <<INFO

即将执行以下配置：
  - 端口模式：${PORT_MODE}
  - SSH 主端口：${SSH_PORT}
  - 防止失联而保护的 SSH 端口：${protected_ports}
  - 额外 TCP 端口：${TCP_PORTS:-无}
  - 额外 UDP 端口/范围：${UDP_PORTS:-无}
  - UFW 默认策略：拒绝入站，允许出站
  - 阻止出站邮件 TCP 25/465/587：${BLOCK_MAIL_OUT}
  - 重置全部现有 UFW 规则：${RESET_UFW}
  - Fail2Ban 策略：${FAIL2BAN_PROFILE}
  - Fail2Ban 阈值：${FAIL2BAN_FINDTIME} 内失败 ${FAIL2BAN_MAXRETRY} 次，封禁 ${FAIL2BAN_BANTIME}
  - 验证真实防火墙封禁：${VERIFY_FAIL2BAN}
  - 信任当前 SSH 客户端 IP：${TRUST_CURRENT_SSH_IP}
INFO
  fi

  if [[ -n "$SSH_CLIENT_IP" ]]; then
    if [[ "$SAFEVPS_LANG" == "en" ]]; then
      printf '  - Detected SSH client IP: %s\n' "$SSH_CLIENT_IP"
    else
      printf '  - 检测到的 SSH 客户端 IP：%s\n' "$SSH_CLIENT_IP"
    fi
  else
    warn ssh_client_missing
  fi
}

confirm_changes() {
  local confirmation

  [[ "$ASSUME_YES" == "1" ]] && return 0
  if [[ "$RESET_UFW" == "1" ]]; then
    warn reset_ufw_warning
  fi
  if [[ "$SAFEVPS_LANG" == "en" ]]; then
    read -r -p "Type YES to continue: " confirmation
  else
    read -r -p "确认继续请输入 YES：" confirmation
  fi
  if [[ "$confirmation" != "YES" ]]; then
    msg canceled
    printf '\n'
    exit 0
  fi
}

delete_recorded_ufw_rules() {
  local action direction spec comment
  local -a args

  [[ -f "$UFW_STATE_FILE" ]] || return 0
  while IFS='|' read -r action direction spec comment; do
    [[ "$action" =~ ^(allow|limit|reject)$ ]] || continue
    [[ "$direction" =~ ^(in|out)$ ]] || continue
    [[ "$spec" =~ ^[0-9]{1,5}(:[0-9]{1,5})?/(tcp|udp)$ ]] || continue
    [[ "$comment" =~ ^safevps:[a-z]+$ ]] || continue

    args=("$action")
    [[ "$direction" == "out" ]] && args+=("out")
    args+=("$spec" "comment" "$comment")
    ufw --force delete "${args[@]}" >/dev/null 2>&1 || true
  done < "$UFW_STATE_FILE"
}

record_ufw_rule() {
  local action="$1" direction="$2" spec="$3" comment="$4"
  printf '%s|%s|%s|%s\n' "$action" "$direction" "$spec" "$comment" >> "$UFW_STATE_FILE"
  chmod 600 "$UFW_STATE_FILE"
}

configure_ufw() {
  local port
  local -a tcp_ports=() udp_ports=()

  log configuring_ufw
  install -d -m 700 "$UFW_STATE_DIR"

  if [[ "$RESET_UFW" == "1" ]]; then
    ufw --force reset
  else
    delete_recorded_ufw_rules
  fi
  : > "$UFW_STATE_FILE"
  chmod 600 "$UFW_STATE_FILE"

  ufw default deny incoming
  ufw default allow outgoing

  # Replace any existing LIMIT for these ports, then put LIMIT before broad ALLOW rules.
  for port in "${SSH_PORTS_TO_PROTECT[@]}"; do
    ufw --force delete limit "${port}/tcp" >/dev/null 2>&1 || true
    ufw prepend limit "${port}/tcp" comment "SSH"
    record_ufw_rule "limit" "in" "${port}/tcp" "SSH"
  done

  read -r -a tcp_ports <<< "$TCP_PORTS"
  for port in "${tcp_ports[@]}"; do
    ufw allow "${port}/tcp" comment "safevps:tcp"
    record_ufw_rule "allow" "in" "${port}/tcp" "safevps:tcp"
  done

  read -r -a udp_ports <<< "$UDP_PORTS"
  for port in "${udp_ports[@]}"; do
    ufw allow "${port}/udp" comment "safevps:udp"
    record_ufw_rule "allow" "in" "${port}/udp" "safevps:udp"
  done

  if [[ "$BLOCK_MAIL_OUT" == "1" ]]; then
    for port in 25 465 587; do
      ufw reject out "${port}/tcp" comment "Mail"
      record_ufw_rule "reject" "out" "${port}/tcp" "Mail"
    done
  fi

  ufw --force enable
  log current_ufw_status
  ufw status verbose
}

restore_fail2ban_config() {
  local backup="$1"
  local had_config="$2"

  if [[ "$had_config" == "1" ]]; then
    install -m 644 "$backup" "$FAIL2BAN_CONFIG"
  else
    rm -f "$FAIL2BAN_CONFIG"
  fi
  systemctl restart fail2ban >/dev/null 2>&1 || true
}

configure_fail2ban() {
  local ignore_ips="127.0.0.1/8 ::1"
  local ssh_ports config_tmp backup_tmp had_config=0 ready=0

  if [[ "$TRUST_CURRENT_SSH_IP" == "1" ]]; then
    if [[ -n "$SSH_CLIENT_IP" && "$SSH_CLIENT_IP" =~ ^[0-9A-Fa-f:.]+$ ]]; then
      ignore_ips+=" ${SSH_CLIENT_IP}"
    else
      warn ssh_client_untrusted
    fi
  fi

  ssh_ports="$(join_ssh_ports)"
  config_tmp="$(mktemp)"
  backup_tmp="$(mktemp)"
  if [[ -f "$FAIL2BAN_CONFIG" ]]; then
    cp -a "$FAIL2BAN_CONFIG" "$backup_tmp"
    had_config=1
  fi

  cat > "$config_tmp" <<EOF
# Managed by SafeVPS. Local customizations should use a later jail.d/*.local file.
[sshd]
enabled = true
port = ${ssh_ports}
backend = systemd
usedns = no
ignoreip = ${ignore_ips}
bantime = ${FAIL2BAN_BANTIME}
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
EOF

  install -m 644 "$config_tmp" "$FAIL2BAN_CONFIG"
  if ! fail2ban-client -t; then
    restore_fail2ban_config "$backup_tmp" "$had_config"
    rm -f "$config_tmp" "$backup_tmp"
    die fail2ban_config_failed
  fi

  systemctl enable fail2ban >/dev/null
  if ! systemctl restart fail2ban; then
    restore_fail2ban_config "$backup_tmp" "$had_config"
    rm -f "$config_tmp" "$backup_tmp"
    die fail2ban_start_failed
  fi

  for _ in {1..10}; do
    if fail2ban-client ping >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "1" ]]; then
    restore_fail2ban_config "$backup_tmp" "$had_config"
    rm -f "$config_tmp" "$backup_tmp"
    die fail2ban_not_ready
  fi

  log fail2ban_status
  fail2ban-client status
  fail2ban-client status sshd
  rm -f "$config_tmp" "$backup_tmp"
}

firewall_contains_ip() {
  local ip="$1"
  local rules=""

  if command -v nft >/dev/null 2>&1; then
    rules="$(nft list ruleset 2>/dev/null || true)"
    [[ "$rules" == *"$ip"* ]] && return 0
  fi
  if command -v iptables-save >/dev/null 2>&1; then
    rules="$(iptables-save 2>/dev/null || true)"
    [[ "$rules" == *"$ip"* ]] && return 0
  fi
  if command -v ipset >/dev/null 2>&1; then
    rules="$(ipset list 2>/dev/null || true)"
    [[ "$rules" == *"$ip"* ]] && return 0
  fi
  if command -v ufw >/dev/null 2>&1; then
    rules="$(ufw status 2>/dev/null || true)"
    [[ "$rules" == *"$ip"* ]] && return 0
  fi
  return 1
}

verify_fail2ban_firewall() {
  local test_ip="192.0.2.$((($$ % 254) + 1))"
  local found=0 cleared=0
  local actions

  log verifying_fail2ban
  actions="$(fail2ban-client get sshd actions 2>/dev/null || true)"
  if [[ -n "$actions" ]]; then
    printf '    '
    msg effective_actions "$actions"
    printf '\n'
  fi

  # TEST-NET-1 is reserved for documentation and cannot be a legitimate Internet client.
  fail2ban-client set sshd unbanip "$test_ip" >/dev/null 2>&1 || true
  if ! fail2ban-client set sshd banip "$test_ip" >/dev/null; then
    die test_ban_failed "$test_ip"
  fi

  for _ in {1..5}; do
    if firewall_contains_ip "$test_ip"; then
      found=1
      break
    fi
    sleep 1
  done

  if [[ "$found" != "1" ]]; then
    fail2ban-client set sshd unbanip "$test_ip" >/dev/null 2>&1 || true
    die test_rule_missing "$test_ip"
  fi

  if ! fail2ban-client set sshd unbanip "$test_ip" >/dev/null; then
    die test_unban_failed "$test_ip"
  fi

  for _ in {1..5}; do
    if ! firewall_contains_ip "$test_ip"; then
      cleared=1
      break
    fi
    sleep 1
  done
  [[ "$cleared" == "1" ]] || die test_rule_not_cleared "$test_ip"

  log test_ban_verified
}

check_environment() {
  [[ "${EUID}" -eq 0 ]] || die root_required "$0"
  command -v apt-get >/dev/null 2>&1 || die apt_required
  command -v systemctl >/dev/null 2>&1 || die systemctl_required
  [[ -d /run/systemd/system ]] || die systemd_inactive

  if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
    DOCKER_WARNING=1
    warn docker_detected
  fi
}

main() {
  local initial_language="$SAFEVPS_LANG"

  if ! set_language "$initial_language"; then
    SAFEVPS_LANG="zh"
    die language_invalid "$initial_language"
  fi
  parse_args "$@"

  if [[ "$SHOW_HELP" == "1" ]]; then
    show_help
    exit 0
  fi

  ASSUME_YES="${ASSUME_YES:-0}"
  BLOCK_MAIL_OUT="${BLOCK_MAIL_OUT:-1}"
  RESET_UFW="${RESET_UFW:-0}"
  TRUST_CURRENT_SSH_IP="${TRUST_CURRENT_SSH_IP:-0}"
  VERIFY_FAIL2BAN="${VERIFY_FAIL2BAN:-1}"

  validate_bool "ASSUME_YES" "$ASSUME_YES"
  validate_bool "BLOCK_MAIL_OUT" "$BLOCK_MAIL_OUT"
  validate_bool "RESET_UFW" "$RESET_UFW"
  validate_bool "TRUST_CURRENT_SSH_IP" "$TRUST_CURRENT_SSH_IP"
  validate_bool "VERIFY_FAIL2BAN" "$VERIFY_FAIL2BAN"

  check_environment
  configure_ssh_ports
  configure_port_mode
  configure_fail2ban_profile

  validate_fail2ban_time "FAIL2BAN_BANTIME" "$FAIL2BAN_BANTIME" "1"
  validate_fail2ban_time "FAIL2BAN_FINDTIME" "$FAIL2BAN_FINDTIME" "0"
  if [[ ! "$FAIL2BAN_MAXRETRY" =~ ^[0-9]+$ ]] || \
    ((10#${FAIL2BAN_MAXRETRY} < 1 || 10#${FAIL2BAN_MAXRETRY} > 100)); then
    die maxretry_invalid
  fi

  show_summary
  confirm_changes

  log installing_dependencies
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ufw fail2ban

  if [[ -f /etc/fail2ban/jail.local ]]; then
    warn jail_local_found
  fi

  configure_ufw
  log configuring_fail2ban
  configure_fail2ban
  if [[ "$VERIFY_FAIL2BAN" == "1" ]]; then
    verify_fail2ban_firewall
  fi

  if [[ "$DOCKER_WARNING" == "1" ]]; then
    warn docker_final_warning
  fi
  log completed
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
