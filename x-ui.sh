#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "Error:  This script must be run as root!\n" && exit 1

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
    LOGE "OS version not detected. Please contact the script author！\n" && exit 1
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
        LOGE "Please use CentOS 7 or above system！\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        LOGE "Please use Ubuntu 16 or above system！\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        LOGE "Please use Debian 8 or above system！\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [default: $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Do you want to restart the panel? Restarting the panel will also restart Xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press Enter to return to the main menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/miipan/x-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "This feature will force reinstall the latest version. Data will not be lost. Continue?" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelled"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/miipan/x-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "Update complete. The panel has been restarted automatically."
        exit 0
    fi
}

uninstall() {
    confirm "Are you sure you want to uninstall the panel? xray will also be uninstalled." "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "Uninstallation successful. If you also want to delete this script, run ${green}rm /usr/bin/x-ui -f${plain} after exiting."
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "Are you sure you want to reset the username and password to admin?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -username admin -password admin
    echo -e "Username and password have been reset to ${green}admin${plain}. Please restart the panel now."
    confirm_restart
}

reset_config() {
    confirm "re you sure you want to reset all panel settings? Account data will not be lost, and the username and password will remain unchanged." "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "All panel settings have been reset to default. Please restart the panel and access it using the default port ${green}54321${plain}"
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "Enter port number [1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "Port has been set. Please restart the panel and access it using the new port ${green}${port}${plain}"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "The panel is already running."
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui started successfully."
        else
            LOGE "Failed to start the panel."
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "The panel is already stopped."
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui stopped successfully."
        else
            LOGE "Failed to stop the panel."
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui restarted successfully."
    else
        LOGE "Failed to restart the panel."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui has been set to start on boot successfully."
    else
        LOGE "Failed to set x-ui to start on boot."
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui has been disabled from starting on boot successfully."
    else
        LOGE "Failed to disable x-ui from starting on boot."
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/x-ui/x-ui v2-ui

    before_show_menu
}

install_bbr() {
    # temporary workaround for installing bbr
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate https://github.com/miipan/x-ui/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Failed to download the script Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "The upgrade script was successful, please re-run the script" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "The panel is already installed. Please do not reinstall it."
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Please install the panel first"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Panel status: ${green}Running${plain}"
        show_enable_status
        ;;
    1)
        echo -e "Panel status: ${yellow}Not running${plain}"
        show_enable_status
        ;;
    2)
        echo -e "Panel status: ${red}Not installed${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Auto-start on boot: ${green}Yes${plain}"
    else
        echo -e "Auto-start on boot: ${red}No${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray status: ${green}Running${plain}"
    else
        echo -e "xray status: ${red}Not running${plain}"
    fi
}

ssl_cert_issue() {
    echo -E ""
    LOGD "******Usage Instructions******"
    LOGI "This script will use the Acme script to apply for a certificate. Please ensure the following before proceeding:"
    LOGI "1. You know the registered Cloudflare email"
    LOGI "2. You know the Cloudflare Global API Key"
    LOGI "3. The domain has already been resolved to this server via Cloudflare"
    LOGI "4. The default certificate installation path for this script is the /root/cert directory"
    confirm "I have confirmed the above content [y/n]" "y"
    if [ $? -eq 0 ]; then
        cd ~
        LOGI "Installing Acme script"
        curl https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            LOGE "Failed to install Acme script"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "Please set your domain:"
        read -p "Input your domain here:" CF_Domain
        LOGD "Your domain is set to:${CF_Domain}"
        LOGD "Please set your API key:"
        read -p "Input your key here:" CF_GlobalKey
        LOGD "Your API key is:${CF_GlobalKey}"
        LOGD "Please set your registered email:"
        read -p "Input your email here:" CF_AccountEmail
        LOGD "Your registered email is:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "Failed to set default CA to Let's Encrypt, exiting script"
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "Certificate issuance failed, exiting script"
            exit 1
        else
            LOGI "Certificate issued successfully, installing..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "Certificate installation failed, exiting script"
            exit 1
        else
            LOGI "Certificate installed successfully, enabling auto-update..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Failed to enable auto-update, exiting script"
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "Certificate installed and auto-update enabled. Details:"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

show_usage() {
    echo "x-ui Management Script Usage: "
    echo "------------------------------------------"
    echo "x-ui              - Show management menu (more features)"
    echo "x-ui start        - start x-ui panel"
    echo "x-ui stop         - stop x-ui panel"
    echo "x-ui restart      - restart x-ui panel"
    echo "x-ui status       - Check x-ui status"
    echo "x-ui enable       - Enable x-ui to start at boot"
    echo "x-ui disable      - Disable x-ui from starting at boot"
    echo "x-ui log          - View x-ui logs"
    echo "x-ui v2-ui        - Migrate v2-ui account data from this machine to x-ui"
    echo "x-ui update       - update x-ui panel"
    echo "x-ui install      - install x-ui panel"
    echo "x-ui uninstall    - uninstall x-ui panel"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}x-ui Panel Management Script${plain}
  ${green}0.${plain} Exit Script
————————————————
  ${green}1.${plain} Install x-ui
  ${green}2.${plain} Update x-ui
  ${green}3.${plain} Uninstall x-ui
————————————————
  ${green}4.${plain} Reset Username and Password
  ${green}5.${plain} Reset Panel Settings
  ${green}6.${plain} Set Panel Port
  ${green}7.${plain} View Current Panel Settings
————————————————
  ${green}8.${plain} Start x-ui
  ${green}9.${plain} Stop x-ui
  ${green}10.${plain} Restart x-ui
  ${green}11.${plain} View x-ui Status
  ${green}12.${plain} View x-ui Logs
————————————————
  ${green}13.${plain} Enable x-ui on Startup
  ${green}14.${plain} Disable x-ui on Startup
————————————————
  ${green}15.${plain} One-Click Install BBR (Latest Kernel)
  ${green}16.${plain} One-Click Apply SSL Certificate (via acme)
 "
    show_status
    echo && read -p "请输入选择 [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && reset_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && show_log
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        install_bbr
        ;;
    16)
        ssl_cert_issue
        ;;
    *)
        LOGE "Please enter a valid number [0-16]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "v2-ui")
        check_install 0 && migrate_v2_ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
