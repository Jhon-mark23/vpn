#!/bin/bash
# ============================================================
# MARCSCRIPT VPN INSTALLER v3.1
# Based on Original setup.sh with Improvements
# Compatible with Ubuntu 22.04 / 24.04 & Debian
# ============================================================

# ---------- SUPPRESS INTERACTIVE PROMPTS ----------
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
fi

# ---------- CLEANUP ----------
clear
rm -rf setup.sh
rm -rf /etc/xray/domain
rm -rf /etc/v2ray/domain
rm -rf /etc/xray/scdomain
rm -rf /etc/v2ray/scdomain
rm -rf /var/lib/ipvps.conf

# ---------- COLOURS ----------
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

# ---------- COLOR FUNCTIONS ----------
purple() { echo -e "\\033[35;1m${*}\\033[0m"; }
tyblue() { echo -e "\\033[36;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
blue() { echo -e "\\033[34;1m${*}\\033[0m"; }
white() { echo -e "\\033[37;1m${*}\\033[0m"; }

print_info()  { echo -e "[ ${BGreen}✓${NC} ] $1"; }
print_error() { echo -e "[ ${BRed}✗${NC} ] $1"; }
print_warning(){ echo -e "[ ${BYellow}⚠${NC} ] $1"; }
print_success(){ echo -e "[ ${BCyan}▶${NC} ] $1"; }

# ---------- BANNER ----------
show_banner() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██╔████╔██║███████║██████╔╝██║     ███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BCyan}           VPN INSTALLER v3.1                          ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ---------- DOMAIN ----------
CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
cd /root

# ---------- ROOT CHECK ----------
if [ "${EUID}" -ne 0 ]; then
    echo -e "[ ${BRed}ERROR${NC} ] You need to run this script as root"
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo -e "[ ${BRed}ERROR${NC} ] OpenVZ is not supported"
    exit 1
fi

# ---------- HOSTS FIX ----------
localip=$(hostname -I | cut -d\  -f1)
hst=( `hostname` )
dart=$(cat /etc/hosts | grep -w `hostname` | awk '{print $2}')
if [[ "$hst" != "$dart" ]]; then
    echo "$localip $(hostname)" >> /etc/hosts
fi

# ---------- CREATE DIRECTORIES ----------
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

# ---------- KERNEL HEADERS ----------
totet=`uname -r`
REQUIRED_PKG="linux-headers-$totet"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2>/dev/null|grep "install ok installed")
echo -e "[ ${BGreen}✓ INFO${NC} ] Checking for $REQUIRED_PKG: $PKG_OK"
if [ "" = "$PKG_OK" ]; then
    echo -e "[ ${BRed}⚠ WARNING${NC} ] Trying to install..."
    apt-get --yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install $REQUIRED_PKG >/dev/null 2>&1 || true
fi
clear

# ---------- TIME & SYSTEM ----------
secs_to_human() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BGreen}   Installation time : $(( ${1} / 3600 )) hours $(( (${1} / 60) % 60 )) minutes $(( ${1} % 60 )) seconds${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
start=$(date +%s)
ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

# ---------- INSTALL BASE PACKAGES ----------
echo -e "[ ${BGreen}✓ INFO${NC} ] Preparing installation files..."
apt install git curl -y >/dev/null 2>&1
apt install python3 python3-pip python3-is-python -y >/dev/null 2>&1

# ---------- PYTHON SYMLINK (Debian) ----------
if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
    ln -s /usr/bin/python3 /usr/bin/python
fi

echo -e "[ ${BGreen}✓ INFO${NC} ] Installation files ready"
sleep 0.5
echo -ne "[ ${BGreen}✓ INFO${NC} ] Checking permissions : "
echo -e "${BGreen}Permission Accepted!${NC}"
sleep 2

mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf

# ---------- FIND PREVIOUS DOMAIN ----------
PREVIOUS_DOMAIN=""
for path in "/root/domain.txt" "/root/domain" "/etc/xray/domain" "/etc/v2ray/domain"; do
    if [ -s "$path" ]; then
        PREVIOUS_DOMAIN=$(cat "$path" | tr -d '[:space:]')
        break
    fi
done

# ---------- DOMAIN SELECTION ----------
while true; do
    echo ""
    show_banner
    echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BCyan}║${BWhite}                    DOMAIN CONFIGURATION                  ${BCyan}║${NC}"
    echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BGreen} 1. ${NC}Use Random Domain (via Cloudflare)"
    echo -e "${BGreen} 2. ${NC}Use Your Own Domain"
    echo -e "${BGreen} 3. ${NC}Re-use Previous Domain"
    echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -n "$PREVIOUS_DOMAIN" ]; then
        echo -e "${BCyan} ℹ Previous domain found: ${BYellow}${PREVIOUS_DOMAIN}${NC}"
    else
        echo -e "${BCyan} ℹ No previous domain found.${NC}"
    fi
    echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    read -rp " Select domain option [1-3]: " dns
    dns="${dns//[[:space:]]/}"

    if [[ "$dns" == "1" ]]; then
        clear
        show_banner
        echo -e "[ ${BGreen}✓ INFO${NC} ] Generating random domain..."
        apt install jq curl -y
        wget -q -O /root/cf "${CDN}/cf" >/dev/null 2>&1
        chmod +x /root/cf
        bash /root/cf | tee /root/install.log
        
        # Get generated domain
        if [ -f /root/domain.txt ]; then
            PREVIOUS_DOMAIN=$(cat /root/domain.txt | tr -d '[:space:]')
        elif [ -f /root/domain ]; then
            PREVIOUS_DOMAIN=$(cat /root/domain | tr -d '[:space:]')
        fi
        
        if [ -z "$PREVIOUS_DOMAIN" ]; then
            echo -e "[ ${BRed}✗ ERROR${NC} ] Failed to generate domain"
            sleep 2
            continue
        fi
        break

    elif [[ "$dns" == "2" ]]; then
        read -rp " Enter Your Domain : " dom
        dom="${dom//[[:space:]]/}"
        if [ -z "$dom" ]; then
            echo -e "[ ${BRed}✗ ERROR${NC} ] Domain cannot be empty"
            sleep 1
            continue
        fi
        PREVIOUS_DOMAIN="$dom"
        break

    elif [[ "$dns" == "3" ]]; then
        if [ -z "$PREVIOUS_DOMAIN" ]; then
            echo ""
            echo -e "${BRed}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BRed}║${BWhite}  ✗ NO PREVIOUS DOMAIN FOUND!                             ${BRed}║${NC}"
            echo -e "${BRed}║                                                          ${BRed}║${NC}"
            echo -e "${BRed}║  Please select option 1 (Random) or 2 (Custom)           ${BRed}║${NC}"
            echo -e "${BRed}╚══════════════════════════════════════════════════════════════╝${NC}"
            sleep 2
            continue
        fi
        break

    else
        echo -e "[ ${BRed}✗ ERROR${NC} ] Invalid Option. Please choose 1, 2, or 3."
        sleep 1
        continue
    fi
done

# ---------- SAVE DOMAIN ----------
mkdir -p /etc/xray /etc/v2ray
echo "$PREVIOUS_DOMAIN" > /root/scdomain
echo "$PREVIOUS_DOMAIN" > /etc/xray/scdomain
echo "$PREVIOUS_DOMAIN" > /etc/xray/domain
echo "$PREVIOUS_DOMAIN" > /etc/v2ray/domain
echo "$PREVIOUS_DOMAIN" > /root/domain
echo "$PREVIOUS_DOMAIN" > /root/domain.txt
echo "IP=$PREVIOUS_DOMAIN" > /var/lib/ipvps.conf

echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Domain set to: ${BYellow}${PREVIOUS_DOMAIN}${NC}"
sleep 2
clear

# ---------- INSTALLATION STAGES ----------
show_banner
echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BCyan}║${BWhite}                   INSTALLATION PROGRESS                  ${BCyan}║${NC}"
echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ---------- STAGE 1: SSH VPN ----------
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [1/3] Installing SSH & Setting Up VPS                   │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
echo -e "[ ${BGreen}✓ INFO${NC} ] Installing SSH VPN..."
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh -O ssh-vpn.sh
sed -i 's/\r$//' ssh-vpn.sh
chmod +x ssh-vpn.sh
bash ssh-vpn.sh

# ---------- STAGE 2: SSH WEBSOCKET ----------
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [2/3] Installing SSH WebSocket                          │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
echo -e "[ ${BGreen}✓ INFO${NC} ] Installing SSH WebSocket..."
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh -O insshws.sh
sed -i 's/\r$//' insshws.sh
chmod +x insshws.sh
bash insshws.sh

# ---------- STAGE 3: XRAY ----------
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [3/3] Installing Xray                                   │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
echo -e "[ ${BGreen}✓ INFO${NC} ] Installing Xray..."
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh -O ins-xray.sh
sed -i 's/\r$//' ins-xray.sh
chmod +x ins-xray.sh
bash ins-xray.sh

# ---------- FINALIZE ----------
clear
cat > /root/.profile << END
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

# ---------- CLEANUP ----------
rm -f /root/log-install.txt > /dev/null 2>&1
rm -f /etc/afak.conf > /dev/null 2>&1

touch /etc/log-create-ssh.log 2>/dev/null
touch /etc/log-create-vmess.log 2>/dev/null
touch /etc/log-create-vless.log 2>/dev/null
touch /etc/log-create-trojan.log 2>/dev/null
touch /etc/log-create-shadowsocks.log 2>/dev/null

history -c
serverV=$( curl -sS https://raw.githubusercontent.com/Jhon-mark23/vpn/main/menu/versi )
echo $serverV > /opt/.ver
curl -sS ipv4.icanhazip.com > /etc/myipvps

# ---------- FINAL OUTPUT ----------
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

# ---------- CLEANUP INSTALL FILES ----------
rm -f /root/setup.sh /root/ins-xray.sh /root/insshws.sh /root/ssh-vpn.sh 2>/dev/null

# ---------- REBOOT PROMPT ----------
echo -ne "[ ${yell}⚠ WARNING${NC} ] Reboot now? (y/n)? "
read answer
if [ "$answer" == "${answer#[Yy]}" ] ;then
    exit 0
else
    reboot
fi