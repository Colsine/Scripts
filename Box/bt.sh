#! /bin/bash

#彩色
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}



#宝塔面板 官方版
#一键安装
#CentOS
function btof1(){
yum install -y wget && wget -O install.sh http://download.bt.cn/install/install_6.0.sh && sh install.sh
}
#Ubuntu&Debian
function btof2(){
wget -O install.sh http://download.bt.cn/install/install-ubuntu_6.0.sh && sudo bash install.sh
}
#Python3通用版
function btof3(){
curl -sSO http://download.bt.cn/install/install_panel.sh && bash install_panel.sh
}
#升级与更新
function btof4(){
curl http://download.bt.cn/install/update6.sh|bash
}

#宝塔面板 Hostcli 净化版 v7.6.0
#Centos
function btcli1(){
yum install -y wget && wget -O install.sh http://v7.hostcli.com/install/install_6.0.sh --no-check-certificate && sh install.sh
}
#Ubuntu&Debian
function btcli2(){
wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh --no-check-certificate && sudo bash install.sh
}
#一键转移/升级
function btcli3(){
curl http://v7.hostcli.com/install/update6.sh|bash
}

#宝塔面板 Fenhao 开心版 v7.7.0
#CentOS
function btfh1(){
yum install -y wget && wget -O install.sh https://download.moetas.com/ltd/install/install_6.0.sh && sh install.sh
}

#Ubuntu&Debian
function btfh2(){
wget -O install.sh https://download.moetas.com/ltd/install/install-ubuntu_6.0.sh && sudo bash install.sh
}
#Python3通用版 已整合ARM
function btfh3(){
curl -sSO https://download.moetas.com/ltd/install/install_panel.sh && bash install_panel.sh
}
#升级与更新
function btfh4(){
curl https://download.moetas.com/ltd/install/update6.sh|bash
}


#主菜单
function start_menu(){
    clear
    red " 宝塔面板安装" 
    yellow " =================================================="
    red "宝塔面板 官方版 v7.6.0"
    green " 11. CentOS"
    green " 12. Ubuntu&Debian"
    green " 13. Python3通用版"
    green " 14. 升级与更新"
    red "宝塔面板 Hostcli 净化版 v7.6.0"
    green " 21. Centos"
    green " 22. Ubuntu&Debian"
    green " 23. 一键转移/升级"
    red "宝塔面板 Fenhao 开心版 v7.7.0"
    green " 31. CentOS"
    green " 32. Ubuntu&Debian"
    green " 33. Python3通用版"
    green " 34. 升级与更新"
    green " =================================================="
    green " 0. 退出脚本"
    echo
    read -p "请输入数字:" menuNumberInput
    case "$menuNumberInput" in

	11 )
           btof1
	;;
	12 )
           btof2
	;;
	13 )
           btof3
	;;
	14 )
           btof4
	;;
	21 )
           btcli1
	;;
	22 )
           btcli2
	;;
	23 )
           btcli3
	;;
	31 )
           btfh1
	;;
	32 )
           btfh2
	;;
	33 )
           btfh3
	;;
	34 )
           btfh4
	;;
	35 )
           btfh5
	;;
	36 )
           btfh6
	;;
        0 )
            exit 1
        ;;
        * )
            clear
            red "请输入正确数字 !"
            start_menu
        ;;
    esac
}
start_menu "first"
