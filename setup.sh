#!/bin/bash
# ============================================================
# MARCSCRIPT VPN INSTALLER
# All-in-One VPN Solution for Debian & Ubuntu
# 
# Installation:
#   unzip multiport-edited.zip -d /root/
#   cd /root/xray-edited
#   bash setup.sh
#
# Author: MarcScript
# Version: 2.0
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

# ============================================================
# COLOR DEFINITIONS - MARCSCRIPT THEME
# ============================================================
red='\e[1;31m'
green='\e[0;32m'
yell='\e[1;33m'
tyblue='\e[1;36m'
BRed='\e[1;31m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
BCyan='\e[1;36m'
BWhite='\e[1;37m'
NC='\e[0m'

# Font styles
BOLD='\033[1m'
BLINK='\033[5m'
DIM='\033[2m'

# Color functions
purple() { echo -e "\\033[35;1m${*}\\033[0m"; }
tyblue() { echo -e "\\033[36;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
blue() { echo -e "\\033[34;1m${*}\\033[0m"; }
white() { echo -e "\\033[37;1m${*}\\033[0m"; }

# ============================================================
# BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}                                                          ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██╔████╔██║███████║██████╔╝██║     ███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}                                                          ${BPurple}║${NC}"
    echo -e "${BPurple}║${BCyan}           ALL-IN-ONE VPN INSTALLER v2.0                  ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}                                                          ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Now detect OS
detect_os

# Domain random
CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
cd /root

# System version number
if [ "${EUID}" -ne 0 ]; then
    echo -e "${BRed}✗ ERROR:${NC} You need to run this script as root"
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo -e "${BRed}✗ ERROR:${NC} OpenVZ is not supported"
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

echo -e "[ ${BBlue}ℹ NOTES${NC} ] Before we go.. "
sleep 0.5
echo -e "[ ${BBlue}ℹ NOTES${NC} ] I need to check your headers first.."
sleep 0.5
echo -e "[ ${BGreen}✓ INFO${NC} ] Checking headers"
sleep 0.5

# Fix: Linux headers handling for Debian/Ubuntu
totet=`uname -r`
REQUIRED_PKG="linux-headers-$totet"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2>/dev/null|grep "install ok installed")
echo -e "[ ${BGreen}✓ INFO${NC} ] Checking for $REQUIRED_PKG: $PKG_OK"
if [ "" = "$PKG_OK" ]; then
    echo -e "[ ${BRed}⚠ WARNING${NC} ] Trying to install ...."
    apt-get --yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $REQUIRED_PKG >/dev/null 2>&1 || true
fi
clear

secs_to_human() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BGreen}   Installation time : $(( ${1} / 3600 )) hours $(( (${1} / 60) % 60 )) minutes $(( ${1} % 60 )) seconds${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
start=$(date +%s)
ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

echo -e "[ ${BGreen}✓ INFO${NC} ] Preparing the installation files"
apt install git curl -y >/dev/null 2>&1

# Fix: Python installation for both OS
echo -e "[ ${BGreen}✓ INFO${NC} ] Installing Python..."
if [[ "$OS" == "ubuntu" ]]; then
    apt install python3 python3-pip python3-is-python -y >/dev/null 2>&1
elif [[ "$OS" == "debian" ]]; then
    apt install python3 python3-pip -y >/dev/null 2>&1
    if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi
fi

echo -e "[ ${BGreen}✓ INFO${NC} ] Great ... installation files are ready"
sleep 0.5
echo -ne "[ ${BGreen}✓ INFO${NC} ] Checking permissions : "
echo -e "${BGreen}Permission Accepted!${NC}"
sleep 2

mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf

echo ""
show_banner
echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BCyan}║${BWhite}                    DOMAIN CONFIGURATION                  ${BCyan}║${NC}"
echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BGreen} 1. ${NC}Use Random Domain (via Cloudflare)"
echo -e "${BGreen} 2. ${NC}Use Your Own Domain"
echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -rp " Select domain option [1-2]: " dns
dns="${dns//[[:space:]]/}"
if [[ "$dns" == "1" ]]; then
    clear
    show_banner
    echo -e "[ ${BGreen}✓ INFO${NC} ] Generating random domain..."
    apt install jq curl -y
    wget -q -O /root/cf "${CDN}/cf" >/dev/null 2>&1
    chmod +x /root/cf
    bash /root/cf | tee /root/install.log
    echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Random Domain Setup Complete"
elif [[ "$dns" == "2" ]]; then
    read -rp " Enter Your Domain : " dom
    dom="${dom//[[:space:]]/}"
    mkdir -p /etc/xray /etc/v2ray
    echo "$dom" > /root/scdomain
    echo "$dom" > /etc/xray/scdomain
    echo "$dom" > /etc/xray/domain
    echo "$dom" > /etc/v2ray/domain
    echo "$dom" > /root/domain
    echo "IP=$dom" > /var/lib/ipvps.conf
else
    echo -e "${BRed}✗ ERROR:${NC} Invalid Option"
    exit 1
fi
echo -e "${BGreen}✓ Done!${NC}"
sleep 2
clear

# ============================================================
# INSTALLATION PROGRESS
# ============================================================
show_banner
echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BCyan}║${BWhite}                   INSTALLATION PROGRESS                  ${BCyan}║${NC}"
echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Install SSH & VPN
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [1/3] Installing SSH & Setting Up VPS                   │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing SSH & VPN...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh && chmod +x ssh-vpn.sh && bash ssh-vpn.sh

# Install SSH Websocket
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [2/3] Installing SSH WebSocket                          │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing SSH WebSocket...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh && chmod +x insshws.sh && bash insshws.sh

# Install Xray with improved script
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [3/3] Installing Xray                                   │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing Xray...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh -O ins-xray.sh && chmod +x ins-xray.sh && bash ins-xray.sh

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

# ============================================================
# FINAL OUTPUT - MARCSCRIPT STYLE
# ============================================================
clear
show_banner

echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BGreen}              ✅ INSTALLATION COMPLETE!                   ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}                   📡 SERVICE & PORTS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BGreen}   SSH & VPN Services:${NC}"
echo -e "   ├─ OpenSSH                  : ${BYellow}22, 9696${NC}"
echo -e "   ├─ SSH Websocket            : ${BYellow}80 (via Nginx → ws-dropbear:2095)${NC}"
echo -e "   ├─ SSH SSL Websocket        : ${BYellow}443${NC}"
echo -e "   ├─ Stunnel4                 : ${BYellow}222, 777${NC}"
echo -e "   ├─ Dropbear                 : ${BYellow}109, 143${NC}"
echo -e "   └─ Badvpn                   : ${BYellow}7100-7400${NC}"
echo ""
echo -e "${BGreen}   Xray Services:${NC}"
echo -e "   ├─ Nginx                    : ${BYellow}81${NC}"
echo -e "   ├─ Vmess WS TLS             : ${BYellow}443${NC}"
echo -e "   ├─ Vless WS TLS             : ${BYellow}443${NC}"
echo -e "   ├─ Trojan WS TLS            : ${BYellow}443${NC}"
echo -e "   ├─ Shadowsocks WS TLS       : ${BYellow}443${NC}"
echo -e "   ├─ Vmess WS none TLS        : ${BYellow}80${NC}"
echo -e "   ├─ Vless WS none TLS        : ${BYellow}80${NC}"
echo -e "   ├─ Trojan WS none TLS       : ${BYellow}80${NC}"
echo -e "   ├─ Shadowsocks WS none TLS  : ${BYellow}80${NC}"
echo -e "   ├─ Vmess gRPC               : ${BYellow}443${NC}"
echo -e "   ├─ Vless gRPC               : ${BYellow}443${NC}"
echo -e "   ├─ Trojan gRPC              : ${BYellow}443${NC}"
echo -e "   └─ Shadowsocks gRPC         : ${BYellow}443${NC}"
echo ""
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}                   🔧 MANAGEMENT COMMANDS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   ${BGreen}menu${NC}         - Main menu"
echo -e "   ${BGreen}create${NC}       - Create SSH user"
echo -e "   ${BGreen}vpn-status${NC}   - Check service status"
echo ""
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}                   📁 INSTALLATION LOGS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   📄 Log file: ${BYellow}/root/log-install.txt${NC}"
echo -e "   📄 Xray log: ${BYellow}/var/log/xray/access.log${NC}"
echo ""

secs_to_human "$(($(date +%s) - ${start}))" | tee -a log-install.txt

echo ""
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}           THANK YOU FOR USING MARCSCRIPT!              ${BPurple}║${NC}"
echo -e "${BPurple}║${BCyan}              Enjoy your VPN Server!                       ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

rm /root/setup.sh >/dev/null 2>&1
rm /root/ins-xray.sh >/dev/null 2>&1
rm /root/insshws.sh >/dev/null 2>&1

echo -ne "[ ${yell}⚠ WARNING${NC} ] Reboot now ? (y/n)? "
read answer
if [ "$answer" == "${answer#[Yy]}" ] ;then
exit 0
else
reboot
fi