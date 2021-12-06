#!/bin/bash

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ /
#   Description: Server Status 监控安装脚本
#========================================================

SSS_BASE_PATH="/opt/ServerStatus"
SSS_AGENT_PATH="${SSS_BASE_PATH}/agent"
SSS_AGENT_SERVICE="/etc/systemd/system/agent.service"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Colsine/Scripts/ServerStatus/main"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

pre_check() {
    command -v systemctl >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi

    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum install $* -y) ||
        (command -v apt >/dev/null 2>&1 && apt update && apt install $* -y) ||
        (command -v pacman >/dev/null 2>&1 && pacman -Syu $*) ||
        (command -v apt-get >/dev/null 2>&1 && apt update && apt-get install $* -y)
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v tar >/dev/null 2>&1) ||
        (install_soft curl wget python3)
}

modify_agent_config() {
    echo -e "> 修改Agent配置"

    wget -O $AGENT_SERVICE ${GITHUB_RAW_URL}/agent.service >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    if [ $# -lt 3 ]; then
        echo "server status agent需要3个参数，请重新输入" 
        return 0
    else
        ServerStatus_host=$1
        ServerStatus_user=$2
        USER_DEFAULT_PASSWORD=$3
    fi

    sed -i "s/ServerStatus_host/${ServerStatus_host}/" ${AGENT_SERVICE}
    sed -i "s/ServerStatus_user/${ServerStatus_user}/" ${AGENT_SERVICE}
    sed -i "s/USER_DEFAULT_PASSWORD/${USER_DEFAULT_PASSWORD}/" ${AGENT_SERVICE}

    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"

    systemctl daemon-reload
    systemctl enable agent
    systemctl restart agent
}

install_agent() {
    install_base

    echo -e "> 安装监控Agent"

    # 监控文件夹
    mkdir -p $AGENT_PATH
    chmod 777 -R $AGENT_PATH

    echo -e "正在下载监控端"
    wget --no-check-certificate -qO client-linux.py $GITHUB_RAW_URL/client-linux.py
    mv client-linux.py $AGENT_PATH

    modify_agent_config "$@"
}

uninstall_agent() {
    (systemctl stop agent) >/dev/null 2>&1
    (systemctl disable agent) >/dev/null 2>&1
    (rm -rf $AGENT_PATH) >/dev/null 2>&1
    (rm -rf $AGENT_SERVICE) >/dev/null 2>&1
    systemctl daemon-reload
}

show_menu() {
    echo -e "
    ${green}Server Status监控管理脚本${plain}
  
    ${green}1.${plain}  安装监控Agent
    ${green}2.${plain}  卸载Agent
    ${green}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-2]: " num

    case "${num}" in
    0)
        exit 0
        ;;
 
    1)
        install_agent
        ;;
    2)
        uninstall_agent
        echo -e "${green}卸载Agent完成${plain}"
        ;;
    *)
        echo -e "${red}请输入正确的数字 [0-2]${plain}"
        ;;
    esac
}

pre_check

if [[ $# == 3 ]]; then
    uninstall_agent
    install_agent "$@"
else
    show_menu
fi


