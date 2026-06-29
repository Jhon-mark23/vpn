#!/bin/bash
# ============================================================
# VPN Install Script - Compatible with Debian & Ubuntu
# Installation:
#   unzip multiport-edited.zip -d /root/
#   cd /root/xray-edited
#   bash setup.sh
# ============================================================

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo "Cannot detect OS. Exiting..."
        exit 1
    fi
    
    echo -e "[ ${BGreen}INFO${NC} ] Detected OS: $OS $VER"
    
    # Check if Debian or Ubuntu
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo -e "[ ${BRed}ERROR${NC} ] This script only supports Ubuntu or Debian"
        exit 1
    fi
}

# Suppress interactive prompts for both OS
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Configure needrestart (works on both)
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
fi

clear
rm -rf setup.sh
rm -rf /etc/xray/domain
rm -rf /etc/v2ray/domain
rm -rf /etc/xray/scdomain
rm -rf /etc/v2ray/scdomain
rm -rf /var/lib/ipvps.conf

# Color definitions
red='\e[1;31m'
green='\e[0;32m'
yell='\e[1;33m'
tyblue='\e[1;36m'
BRed='\e[1;31m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
NC='\e[0m'
purple() { echo -e "\\033[35;1m${*}\\033[0m"; }
tyblue() { echo -e "\\033[36;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }

# Now detect OS
detect_os

# Domain random
CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
cd /root

# System version number
if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ is not supported"
    exit 1
fi

localip=$(hostname -I | cut -d\  -f1)
hst=( `hostname` )
dart=$(cat /etc/hosts | grep -w `hostname` | awk '{print $2}')
if [[ "$hst" != "$dart" ]]; then
    echo "$localip $(hostname)" >> /etc/hosts
fi

mkdir -p /etc/xray
mkdir -p /etc/v2ray
touch /etc/xray/domain
touch /etc/v2ray/domain
touch /etc/xray/scdomain
touch /etc/v2ray/scdomain

echo -e "[ ${BBlue}NOTES${NC} ] Before we go.. "
sleep 0.5
echo -e "[ ${BBlue}NOTES${NC} ] I need to check your headers first.."
sleep 0.5
echo -e "[ ${BGreen}INFO${NC} ] Checking headers"
sleep 0.5

# Fix: Linux headers handling for Debian/Ubuntu
totet=`uname -r`
REQUIRED_PKG="linux-headers-$totet"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2>/dev/null|grep "install ok installed")
echo "Checking for $REQUIRED_PKG: $PKG_OK"
if [ "" = "$PKG_OK" ]; then
    echo -e "[ ${BRed}WARNING${NC} ] Trying to install ...."
    apt-get --yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $REQUIRED_PKG >/dev/null 2>&1 || true
fi
clear

secs_to_human() {
    echo "Installation time : $(( ${1} / 3600 )) hours $(( (${1} / 60) % 60 )) minutes $(( ${1} % 60 )) seconds"
}
start=$(date +%s)
ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

echo -e "[ ${BGreen}INFO${NC} ] Preparing the installation files"
apt install git curl -y >/dev/null 2>&1

# Fix: Python installation for both OS
echo -e "[ ${BGreen}INFO${NC} ] Installing Python..."
if [[ "$OS" == "ubuntu" ]]; then
    # Ubuntu has python3-is-python package
    apt install python3 python3-pip python3-is-python -y >/dev/null 2>&1
elif [[ "$OS" == "debian" ]]; then
    # Debian: install python3 and create symlink if needed
    apt install python3 python3-pip -y >/dev/null 2>&1
    # Create python symlink if it doesn't exist
    if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi
fi

echo -e "[ ${BGreen}INFO${NC} ] Great ... installation files are ready"
sleep 0.5
echo -ne "[ ${BGreen}INFO${NC} ] Checking permissions : "
echo -e "$BGreen Permission Accepted!$NC"
sleep 2

mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf

echo ""
clear
echo -e "$BBlue                     SETUP DOMAIN VPS     $NC"
echo -e "$BYellow----------------------------------------------------------$NC"
echo -e "$BGreen 1. Use Random Domain $NC"
echo -e "$BGreen 2. Use Your Own Domain $NC"
echo -e "$BYellow----------------------------------------------------------$NC"
read -rp " Select domain option : " dns
dns="${dns//[[:space:]]/}"
if [[ "$dns" == "1" ]]; then
    clear
    apt install jq curl -y
    wget -q -O /root/cf "${CDN}/cf" >/dev/null 2>&1
    chmod +x /root/cf
    bash /root/cf | tee /root/install.log
    echo -e "${BGreen}Random Domain Setup Complete${NC}"
elif [[ "$dns" == "2" ]]; then
    read -rp "Enter Your Domain : " dom
    dom="${dom//[[:space:]]/}"
    mkdir -p /etc/xray /etc/v2ray
    echo "$dom" > /root/scdomain
    echo "$dom" > /etc/xray/scdomain
    echo "$dom" > /etc/xray/domain
    echo "$dom" > /etc/v2ray/domain
    echo "$dom" > /root/domain
    echo "IP=$dom" > /var/lib/ipvps.conf
else
    echo "Invalid Option"
    exit 1
fi
echo -e "${BGreen}Done!${NC}"
sleep 2
clear

# Install SSH & VPN
echo -e "\e[33m-----------------------------------\033[0m"
echo -e "$BGreen      Installing SSH & Setting Up VPS         $NC"
echo -e "\e[33m-----------------------------------\033[0m"
sleep 0.5
clear
wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh && chmod +x ssh-vpn.sh && bash ssh-vpn.sh

# Install SSH Websocket
echo -e "\e[33m-----------------------------------\033[0m"
echo -e "$BGreen      Installing SSH Websocket           $NC"
echo -e "\e[33m-----------------------------------\033[0m"
sleep 0.5
clear
wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh && chmod +x insshws.sh && bash insshws.sh

# Install Xray
echo -e "\e[33m-----------------------------------\033[0m"
echo -e "$BGreen          Installing XRAY              $NC"
echo -e "\e[33m-----------------------------------\033[0m"
sleep 0.5
clear
wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh && chmod +x ins-xray.sh && bash ins-xray.sh

clear
cat> /root/.profile << END
# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

tty -s && mesg n || true
clear
menu
END
chmod 644 /root/.profile

if [ -f "/root/log-install.txt" ]; then
    rm /root/log-install.txt > /dev/null 2>&1
fi
if [ -f "/etc/afak.conf" ]; then
    rm /etc/afak.conf > /dev/null 2>&1
fi
if [ ! -f "/etc/log-create-ssh.log" ]; then
    echo "Log SSH Account " > /etc/log-create-ssh.log
fi
if [ ! -f "/etc/log-create-vmess.log" ]; then
    echo "Log Vmess Account " > /etc/log-create-vmess.log
fi
if [ ! -f "/etc/log-create-vless.log" ]; then
    echo "Log Vless Account " > /etc/log-create-vless.log
fi
if [ ! -f "/etc/log-create-trojan.log" ]; then
    echo "Log Trojan Account " > /etc/log-create-trojan.log
fi
if [ ! -f "/etc/log-create-shadowsocks.log" ]; then
    echo "Log Shadowsocks Account " > /etc/log-create-shadowsocks.log
fi
history -c
serverV=$( curl -sS https://raw.githubusercontent.com/Jhon-mark23/vpn/main/menu/versi )
echo $serverV > /opt/.ver
curl -sS ipv4.icanhazip.com > /etc/myipvps
echo ""
echo "=================================================================="  | tee -a log-install.txt
echo "      ___                                    ___         ___      "  | tee -a log-install.txt
echo "     /  /\        ___           ___         /  /\       /__/\     "  | tee -a log-install.txt
echo "    /  /:/_      /  /\         /__/\       /  /::\      \  \:\    "  | tee -a log-install.txt
echo "   /  /:/ /\    /  /:/         \  \:\     /  /:/\:\      \  \:\   "  | tee -a log-install.txt
echo "  /  /:/_/::\  /__/::\          \  \:\   /  /:/~/:/  _____\__\:\  "  | tee -a log-install.txt
echo " /__/:/__\/\:\ \__\/\:\__   ___  \__\:\ /__/:/ /:/  /__/::::::::\ "  | tee -a log-install.txt
echo " \  \:\ /~~/:/    \  \:\/\ /__/\ |  |:| \  \:\/:/   \  \:\~~\~~\/ "  | tee -a log-install.txt
echo "  \  \:\  /:/      \__\::/ \  \:\|  |:|  \  \::/     \  \:\  ~~~  "  | tee -a log-install.txt
echo "   \  \:\/:/       /__/:/   \  \:\__|:|   \  \:\      \  \:\      "  | tee -a log-install.txt
echo "    \  \::/        \__\/     \__\::::/     \  \:\      \  \:\     "  | tee -a log-install.txt
echo "     \__\/                       ~~~~       \__\/       \__\/ 1.0 "  | tee -a log-install.txt
echo "=================================================================="  | tee -a log-install.txt
echo ""
echo "   >>> Service & Port"  | tee -a log-install.txt
echo "   - OpenSSH                  : 22, 9696"  | tee -a log-install.txt
echo "   - SSH Websocket            : 80 (via Nginx -> ws-dropbear:2095)" | tee -a log-install.txt
echo "   - SSH SSL Websocket        : 443" | tee -a log-install.txt
echo "   - Stunnel4                 : 222, 777" | tee -a log-install.txt
echo "   - Dropbear                 : 109, 143" | tee -a log-install.txt
echo "   - Badvpn                   : 7100-7400" | tee -a log-install.txt
echo "   - Nginx                    : 81" | tee -a log-install.txt
echo "   - Vmess WS TLS             : 443" | tee -a log-install.txt
echo "   - Vless WS TLS             : 443" | tee -a log-install.txt
echo "   - Trojan WS TLS            : 443" | tee -a log-install.txt
echo "   - Shadowsocks WS TLS       : 443" | tee -a log-install.txt
echo "   - Vmess WS none TLS        : 80" | tee -a log-install.txt
echo "   - Vless WS none TLS        : 80" | tee -a log-install.txt
echo "   - Trojan WS none TLS       : 80" | tee -a log-install.txt
echo "   - Shadowsocks WS none TLS  : 80" | tee -a log-install.txt
echo "   - Vmess gRPC               : 443" | tee -a log-install.txt
echo "   - Vless gRPC               : 443" | tee -a log-install.txt
echo "   - Trojan gRPC              : 443" | tee -a log-install.txt
echo "   - Shadowsocks gRPC         : 443" | tee -a log-install.txt
echo ""
echo "=============================Contact==============================" | tee -a log-install.txt
echo "---------------------------t.me/fahrialimudin-----------------------------" | tee -a log-install.txt
echo "==================================================================" | tee -a log-install.txt
echo -e ""
echo ""
echo "" | tee -a log-install.txt
rm /root/setup.sh >/dev/null 2>&1
rm /root/ins-xray.sh >/dev/null 2>&1
rm /root/insshws.sh >/dev/null 2>&1
secs_to_human "$(($(date +%s) - ${start}))" | tee -a log-install.txt
echo -e "
"
echo -ne "[ ${yell}WARNING${NC} ] Reboot now ? (y/n)? "
read answer
if [ "$answer" == "${answer#[Yy]}" ] ;then
exit 0
else
reboot
fi