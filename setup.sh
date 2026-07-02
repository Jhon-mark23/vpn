#!/bin/bash
# ============================================================
# MARCSCRIPT VPN INSTALLER (Unified Cert Edition)
# All-in-One VPN Solution for Debian & Ubuntu
# 
# Order:
#   1. Domain config
#   2. Create unified certificate (create-cert.sh)
#   3. Install SSH‑VPN (ssh-vpn.sh)
#   4. Install Python WS proxy (insshws.sh)
#   5. Install Xray (ins-xray.sh)
#
# Author: MarcScript
# Version: 2.3
# ============================================================

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

purple() { echo -e "\\033[35;1m${*}\\033[0m"; }
tyblue() { echo -e "\\033[36;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
blue() { echo -e "\\033[34;1m${*}\\033[0m"; }
white() { echo -e "\\033[37;1m${*}\\033[0m"; }

print_info()  { echo -e "[ ${BGreen}✓${NC} ] $1"; }
print_error() { echo -e "[ ${BRed}✗${NC} ] $1"; }
print_warning() { echo -e "[ ${BYellow}⚠${NC} ] $1"; }
print_success() { echo -e "[ ${BCyan}▶${NC} ] $1"; }

show_banner() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██╔████╔██║███████║██████╔╝██║     ███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BCyan}           ALL-IN-ONE VPN INSTALLER v2.3                  ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    print_info "Detected OS: $OS $VER"
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "This script only supports Ubuntu or Debian"
        exit 1
    fi
}

clean_old_services() {
    print_info "Cleaning old services before installation..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop stunnel4 2>/dev/null || true
    systemctl stop dropbear 2>/dev/null || true
    systemctl stop fail2ban 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    systemctl stop ws-dropbear 2>/dev/null || true
    systemctl stop ws-stunnel 2>/dev/null || true
    
    pkill -f nginx 2>/dev/null || true
    pkill -f stunnel4 2>/dev/null || true
    pkill -f badvpn-udpgw 2>/dev/null || true
    pkill -f "screen.*badvpn" 2>/dev/null || true
    pkill -f xray 2>/dev/null || true
    pkill -f ws-dropbear 2>/dev/null || true
    pkill -f ws-stunnel 2>/dev/null || true
    
    rm -rf /etc/nginx/conf.d/* 2>/dev/null || true
    rm -rf /etc/stunnel/* 2>/dev/null || true
    rm -rf /etc/xray 2>/dev/null || true
    rm -rf /etc/v2ray 2>/dev/null || true
    rm -var/log/xray 2>/dev/null || true
    rm -rf /opt/ws-proxy 2>/dev/null || true
    rm -rf /root/.acme.sh 2>/dev/null || true
    
    rm -f /usr/bin/badvpn-udpgw 2>/dev/null || true
    rm -f /usr/local/bin/ws-dropbear 2>/dev/null || true
    rm -f /usr/local/bin/ws-stunnel 2>/dev/null || true
    rm -f /usr/local/bin/xray 2>/dev/null || true
    
    rm -f /usr/bin/menu 2>/dev/null || true
    rm -f /usr/bin/m-* 2>/dev/null || true
    rm -f /usr/bin/usernew 2>/dev/null || true
    rm -f /usr/bin/trial 2>/dev/null || true
    rm -f /usr/bin/renew 2>/dev/null || true
    rm -f /usr/bin/hapus 2>/dev/null || true
    rm -f /usr/bin/cek 2>/dev/null || true
    rm -f /usr/bin/member 2>/dev/null || true
    
    apt clean 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    print_success "Old services cleaned"
}

# ============================================================
# MAIN
# ============================================================
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
fi

show_banner
detect_os
clean_old_services

# Domain setup - DO NOT delete domain files prematurely
clear

CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
cd /root

if [ "${EUID}" -ne 0 ]; then
    print_error "You need to run this script as root"
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    print_error "OpenVZ is not supported"
    exit 1
fi

localip=$(hostname -I | cut -d\  -f1)
hst=( `hostname` )
dart=$(cat /etc/hosts | grep -w `hostname` | awk '{print $2}')
if [[ "$hst" != "$dart" ]]; then
    echo "$localip $(hostname)" >> /etc/hosts
fi

mkdir -p /etc/xray /etc/v2ray

echo -e "[ ${BBlue}ℹ NOTES${NC} ] Before we go.. "
sleep 0.5
echo -e "[ ${BBlue}ℹ NOTES${NC} ] I need to check your headers first.."
sleep 0.5
echo -e "[ ${BGreen}✓ INFO${NC} ] Checking headers"
sleep 0.5

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

echo -e "[ ${BGreen}✓ INFO${NC} ] Installing Python..."
if [[ "$OS" == "ubuntu" ]]; then
    apt install python3 python3-pip python3-is-python -y >/dev/null 2>&1
elif [[ "$OS" == "debian" ]]; then
    apt install python3 python3-pip -y >/dev/null 2>&1
    [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ] && ln -s /usr/bin/python3 /usr/bin/python
fi
mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf

# ============================================================
# DOMAIN CHOICE (loop until valid, option 3 reuses previous)
# ============================================================
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

    # Check for previous domain
    PREVIOUS_DOMAIN=""
    if [ -f /root/domain.txt ]; then
        PREVIOUS_DOMAIN=$(cat /root/domain.txt 2>/dev/null)
    fi

    if [ -n "$PREVIOUS_DOMAIN" ]; then
        echo -e "${BCyan} ℹ Previous domain found: ${BYellow}${PREVIOUS_DOMAIN}${NC}"
    else
        echo -e "${BCyan} ℹ No previous domain found.${NC}"
    fi
    echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    read -rp " Select domain option [1-3]: " dns
    dns="${dns//[[:space:]]/}"

    if [[ "$dns" == "1" ]]; then
        # ---- Random Domain ----
        rm -f /root/domain.txt /root/domain /root/scdomain /etc/xray/domain /etc/xray/scdomain /etc/v2ray/domain /var/lib/ipvps.conf 2>/dev/null || true
        clear
        show_banner
        echo -e "[ ${BGreen}✓ INFO${NC} ] Generating random domain..."
        apt install jq curl -y
        wget -q -O /root/cf "${CDN}/cf" >/dev/null 2>&1
        chmod +x /root/cf
        bash /root/cf | tee /root/install.log
        echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Random Domain Setup Complete"
        break

    elif [[ "$dns" == "2" ]]; then
        # ---- Custom Domain ----
        rm -f /root/domain.txt /root/domain /root/scdomain /etc/xray/domain /etc/xray/scdomain /etc/v2ray/domain /var/lib/ipvps.conf 2>/dev/null || true
        read -rp " Enter Your Domain : " dom
        dom="${dom//[[:space:]]/}"
        if [ -z "$dom" ]; then
            echo -e "${BRed}✗ ERROR:${NC} Domain cannot be empty"
            sleep 1
            continue
        fi
        mkdir -p /etc/xray /etc/v2ray
        echo "$dom" > /root/scdomain
        echo "$dom" > /etc/xray/scdomain
        echo "$dom" > /etc/xray/domain
        echo "$dom" > /etc/v2ray/domain
        echo "$dom" > /root/domain
        echo "$dom" > /root/domain.txt
        echo "IP=$dom" > /var/lib/ipvps.conf
        echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Custom Domain Setup Complete"
        break

    elif [[ "$dns" == "3" ]]; then
        # ---- Reuse Previous Domain ----
        if [ -z "$PREVIOUS_DOMAIN" ]; then
            echo ""
            echo -e "${BRed}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BRed}║${BWhite}  ✗ NO PREVIOUS DOMAIN FOUND!                             ${BRed}║${NC}"
            echo -e "${BRed}║${BWhite}                                                          ${BRed}║${NC}"
            echo -e "${BRed}║${BWhite}  No domain file exists in /root/domain                    ${BRed}║${NC}"
            echo -e "${BRed}║${BWhite}  Please select option 1 (Random) or 2 (Custom)           ${BRed}║${NC}"
            echo -e "${BRed}║${BWhite}  to add a new domain.                                    ${BRed}║${NC}"
            echo -e "${BRed}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            sleep 2
            continue
        fi
        mkdir -p /etc/xray /etc/v2ray
        echo "$PREVIOUS_DOMAIN" > /root/scdomain
        echo "$PREVIOUS_DOMAIN" > /etc/xray/scdomain
        echo "$PREVIOUS_DOMAIN" > /etc/xray/domain
        echo "$PREVIOUS_DOMAIN" > /etc/v2ray/domain
        echo "IP=$PREVIOUS_DOMAIN" > /var/lib/ipvps.conf
        echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Re-using previous domain: ${BYellow}${PREVIOUS_DOMAIN}${NC}"
        break
    else
        echo -e "${BRed}✗ ERROR:${NC} Invalid Option. Please choose 1, 2, or 3."
        sleep 1
        continue
    fi
done

echo -e "${BGreen}✓ Done!${NC}"
sleep 2
clear

# ---------- DOWNLOAD & RUN create-cert.sh ----------
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [CERT] Creating unified SSL certificate                │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Creating certificate (Let's Encrypt or self-signed)...${NC}"
wget -q -O /usr/local/bin/create-cert.sh "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/create-cert.sh"
sed -i 's/\r$//' /usr/local/bin/create-cert.sh
chmod +x /usr/local/bin/create-cert.sh
bash /usr/local/bin/create-cert.sh
print_success "Certificate ready for Stunnel & Xray"

# Continue with original scripts
echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [1/3] Installing SSH & Setting Up VPS                  │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing SSH & VPN...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh -O ssh-vpn.sh
sed -i 's/\r$//' ssh-vpn.sh
chmod +x ssh-vpn.sh
bash ssh-vpn.sh

echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [2/3] Installing SSH WebSocket                         │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing SSH WebSocket...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh -O insshws.sh
sed -i 's/\r$//' insshws.sh
chmod +x insshws.sh
bash insshws.sh

echo -e "${BYellow}┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│  [3/3] Installing Xray                                  │${NC}"
echo -e "${BYellow}└──────────────────────────────────────────────────────────┘${NC}"
sleep 0.5
clear
show_banner
echo -e "${BGreen}▶ Installing Xray...${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh -O ins-xray.sh
sed -i 's/\r$//' ins-xray.sh
chmod +x ins-xray.sh
bash ins-xray.sh

# Final steps
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

rm -f /root/log-install.txt 2>/dev/null
rm -f /etc/afak.conf 2>/dev/null
touch /etc/log-create-ssh.log
touch /etc/log-create-vmess.log
touch /etc/log-create-vless.log
touch /etc/log-create-trojan.log
touch /etc/log-create-shadowsocks.log
history -c
serverV=$( curl -sS https://raw.githubusercontent.com/Jhon-mark23/vpn/main/menu/versi )
echo $serverV > /opt/.ver
curl -sS ipv4.icanhazip.com > /etc/myipvps

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
echo -e "   ├─ OpenSSH                  : ${BYellow}22, 80${NC}"
echo -e "   ├─ SSH Websocket            : ${BYellow}80 (via Nginx → ws-dropbear:2095)${NC}"
echo -e "   ├─ SSH SSL Websocket        : ${BYellow}443${NC}"
echo -e "   ├─ Stunnel4                 : ${BYellow}222, 777${NC}"
echo -e "   ├─ Dropbear                 : ${BYellow}109, 143${NC}"
echo -e "   └─ Badvpn                   : ${BYellow}7100-7400${NC}"
echo ""
echo -e "${BGreen}   Xray Services:${NC}"
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
echo -e "${BWhite}                   🔐 SECURITY NOTES${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   ${BGreen}✓${NC} SSH Password Authentication: ${BYellow}Enabled${NC}"
echo -e "   ${BGreen}✓${NC} SSH Port: ${BYellow}22, 80${NC}"
echo -e "   ${BGreen}✓${NC} Root Login: ${BYellow}Allowed${NC}"
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

rm -f /root/setup.sh /root/ins-xray.sh /root/insshws.sh /root/ssh-vpn.sh /root/create-cert.sh 2>/dev/null
exit 0
