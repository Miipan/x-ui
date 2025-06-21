#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}OS version not detected. Please contact the script author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${red}Detect architecture fail, use default: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "This software not support 32-bit system (x86), please use 64-bit system (x86_64). If wrong detect, please contact author"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or above system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or above system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or above system!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${yellow}For security, must change port and account password after install/update${plain}"
    read -p "Confirm continue?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Please set your username:" config_account
        echo -e "${yellow}Your username is:${config_account}${plain}"
        read -p "Please set your password:" config_password
        echo -e "${yellow}Your password is:${config_password}${plain}"
        read -p "Please set panel port:" config_port
        echo -e "${yellow}Your panel port is:${config_port}${plain}"
        echo -e "${yellow}Confirm setting, processing...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}Set username and password done${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}Set panel port done${plain}"
    else
        echo -e "${red}Cancelled, all use default setting, please change later${plain}"
    fi
}

install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/miipan/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Detect x-ui version fail, maybe exceed Github API limit, try again later or set version manually${plain}"
            exit 1
        fi
        echo -e "Detect latest x-ui version:${last_version}，start install"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/miipan/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui fail, make sure your server can download from Github${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/miipan/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "Start install x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui v$1 fail, make sure version exists${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/miipan/x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    #echo -e "If fresh install, default web port is ${green}54321${plain}, default username and password both are ${green}admin${plain}"
    #echo -e "Please make sure this port is not used by other program, ${yellow}and make sure port 54321 is open${plain}"
    #echo -e "If want to change 54321 to other port, use x-ui command to change, also make sure new port is open"
    #echo -e ""
    #echo -e "If update panel, then use your previous way to access panel"
    #echo -e ""
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} install success, panel started"
    echo -e ""
    echo -e "x-ui manage command: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Show manage menu (more functions)"
    echo -e "x-ui start        - Start x-ui panel"
    echo -e "x-ui stop         - Stop x-ui panel"
    echo -e "x-ui restart      - Restart x-ui panel"
    echo -e "x-ui status       - Check x-ui status"
    echo -e "x-ui enable       - Enable x-ui auto start"
    echo -e "x-ui disable      - Disable x-ui auto start"
    echo -e "x-ui log          - View x-ui log"
    echo -e "x-ui v2-ui        - Migrate v2-ui accounts to x-ui"
    echo -e "x-ui update       - Update x-ui panel"
    echo -e "x-ui install      - Install x-ui panel"
    echo -e "x-ui uninstall    - Uninstall x-ui panel"
    echo -e "----------------------------------------------"
}

echo -e "${green}Start install${plain}"
install_base
install_x-ui $1
