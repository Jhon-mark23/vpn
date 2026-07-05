#!/bin/bash
# ============================================================
# MARCSCRIPT VPN INSTALLER (Unified Cert Edition)
# All-in-One VPN Solution for Debian & Ubuntu
# 
# NEW ORDER (Updated):
#   1. Domain config
#   2. Clean old services & DNSTT
#   3. Secure SSH (safe remote access)
#   4. Create unified certificate (create-cert.sh)
#   5. Install SSH‑VPN (ssh-vpn.sh)
#   6. Install Python WS proxy + Squid + BADVPN (insshws.sh)
#   7. Install Xray core (ins-xray.sh)
#   8. Install Nginx reverse proxy (nginx-setup.sh)
#   9. Install DNSTT (install-dnstt.sh)
#
# NOTE: Nginx is now separate (nginx-setup.sh) for unified proxy
#       Squid & BADVPN moved to insshws.sh
#       All services go through Nginx on ports 80 & 443
#
# Author: MarcScript
# Version: 3.0 (Modular Architecture - Nginx Unified Proxy)
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
print_warning(){ echo -e "[ ${BYellow}⚠${NC} ] $1"; }
print_success(){ echo -e "[ ${BCyan}▶${NC} ] $1"; }

show_banner() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██╔████╔██║███████║██████╔╝██║     ███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BCyan}         ALL-IN-ONE VPN INSTALLER v3.0                    ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}         Modular • Nginx Unified Proxy • No Conflicts     ${BPurple}║${NC}"
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

# ============================================================
# CLEAN DNSTT & OLD SERVICES
# ============================================================
clean_old_services() {
    print_info "Cleaning old services before installation..."
    
    # Stop all services
    systemctl stop nginx 2>/dev/null || true
    systemctl stop stunnel4 2>/dev/null || true
    systemctl stop dropbear 2>/dev/null || true
    systemctl stop fail2ban 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    systemctl stop ws-dropbear 2>/dev/null || true
    systemctl stop ws-stunnel 2>/dev/null || true
    systemctl stop ws-proxy 2>/dev/null || true
    systemctl stop squid 2>/dev/null || true
    systemctl stop server-sldns-udp 2>/dev/null || true
    systemctl stop server-sldns-doh 2>/dev/null || true
    systemctl stop client-sldns 2>/dev/null || true
    systemctl stop dnstt-server 2>/dev/null || true
    systemctl stop dnstt-client 2>/dev/null || true
    
    # Kill processes
    pkill -f nginx 2>/dev/null || true
    pkill -f stunnel4 2>/dev/null || true
    pkill -f badvpn-udpgw 2>/dev/null || true
    pkill -f "screen.*badvpn" 2>/dev/null || true
    pkill -f xray 2>/dev/null || true
    pkill -f ws-dropbear 2>/dev/null || true
    pkill -f ws-stunnel 2>/dev/null || true
    pkill -f ws-proxy 2>/dev/null || true
    pkill -f squid 2>/dev/null || true
    pkill -f sldns-server 2>/dev/null || true
    pkill -f sldns-client 2>/dev/null || true
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f dnstt-client 2>/dev/null || true
    
    # Remove DNSTT configs
    rm -rf /etc/slowdns 2>/dev/null || true
    rm -rf /etc/dnstt 2>/dev/null || true
    rm -f /root/nsdomain 2>/dev/null || true
    rm -f /root/nsdomain.txt 2>/dev/null || true
    
    # Remove DNSTT services
    rm -f /etc/systemd/system/server-sldns*.service 2>/dev/null || true
    rm -f /etc/systemd/system/client-sldns*.service 2>/dev/null || true
    rm -f /etc/systemd/system/dnstt*.service 2>/dev/null || true
    
    # Remove old configs (backup first if needed)
    rm -rf /etc/nginx/conf.d/* 2>/dev/null || true
    rm -rf /etc/nginx/stream.d/* 2>/dev/null || true
    rm -rf /etc/stunnel/* 2>/dev/null || true
    rm -rf /etc/xray/* 2>/dev/null || true
    rm -rf /etc/v2ray/* 2>/dev/null || true
    rm -f /var/log/xray/* 2>/dev/null || true
    rm -rf /opt/ws-proxy 2>/dev/null || true
    rm -rf /root/.acme.sh 2>/dev/null || true
    rm -f /etc/squid/squid.conf 2>/dev/null || true
    
    # Remove binaries
    rm -f /usr/bin/badvpn-udpgw 2>/dev/null || true
    rm -f /usr/local/bin/ws-dropbear 2>/dev/null || true
    rm -f /usr/local/bin/ws-stunnel 2>/dev/null || true
    rm -f /usr/local/bin/xray 2>/dev/null || true
    rm -f /usr/local/bin/create-cert.sh 2>/dev/null || true
    rm -f /usr/local/bin/http-proxy.py 2>/dev/null || true
    
    # Remove menu scripts
    rm -f /usr/bin/menu 2>/dev/null || true
    rm -f /usr/bin/m-* 2>/dev/null || true
    rm -f /usr/bin/usernew 2>/dev/null || true
    rm -f /usr/bin/trial 2>/dev/null || true
    rm -f /usr/bin/renew 2>/dev/null || true
    rm -f /usr/bin/hapus 2>/dev/null || true
    rm -f /usr/bin/cek 2>/dev/null || true
    rm -f /usr/bin/member 2>/dev/null || true
    
    # Clean iptables rules (DNSTT related)
    print_info "Cleaning iptables rules..."
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    iptables -D INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Save iptables
    netfilter-persistent save 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    # Clean apt
    apt clean 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    
    print_success "All old services, DNSTT, and iptables rules cleaned"
}

# ============================================================
# SECURE SSH - SAFE REMOTE ACCESS
# ============================================================
secure_ssh() {
    print_info "Securing SSH for safe remote access..."
    
    # Backup current config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    
    # Ensure port 22 is enabled with password auth
    cat > /etc/ssh/sshd_config <<'EOF'
# ============================================================
# MARCSCRIPT SSH CONFIG - Safe Remote Access
# ============================================================

# Ports (primary + fallback)
Port 22
Port 9696
Port 2222
Port 2269

# Authentication - Password auth enabled for remote access
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
PermitEmptyPasswords no

# Security - Prevent brute force
MaxAuthTries 5
MaxSessions 10
LoginGraceTime 60
ClientAliveInterval 60
ClientAliveCountMax 3

# Performance
UseDNS no
PrintMotd no
X11Forwarding no

# Banner
Banner /etc/ssh/ssh_banner

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    # Restart SSH
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    
    print_success "SSH secured on ports 22, 9696, 2222, 2269"
}

# ============================================================
# SHOW INSTALLATION PLAN
# ============================================================
show_install_plan() {
    echo ""
    echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BCyan}║${BWhite}                  INSTALLATION PLAN v3.0                  ${BCyan}║${NC}"
    echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${BGreen}1.${NC} Domain Configuration"
    echo -e "   ${BGreen}2.${NC} Clean Old Services"
    echo -e "   ${BGreen}3.${NC} Secure SSH Access"
    echo -e "   ${BGreen}4.${NC} SSL Certificate (create-cert.sh)"
    echo -e "   ${BGreen}5.${NC} SSH/Dropbear/Stunnel/WS Proxy (ssh-vpn.sh)"
    echo -e "   ${BGreen}6.${NC} Python WS + Squid + BADVPN (insshws.sh)"
    echo -e "   ${BGreen}7.${NC} Xray Core - Internal Ports (ins-xray.sh)"
    echo -e "   ${BGreen}8.${NC} Nginx Unified Reverse Proxy (nginx-setup.sh)"
    echo -e "   ${BGreen}9.${NC} DNSTT - SlowDNS (install-dnstt.sh)"
    echo ""
    echo -e "   ${BYellow}Architecture:${NC}"
    echo -e "   ${BWhite}Client → Nginx (80/443) → Backend Services (internal)${NC}"
    echo ""
    echo -e "   ${BYellow}No Port Conflicts • Modular • Easy Maintenance${NC}"
    echo ""
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

# PRE-FETCH DOMAIN PRESERVATIONS
PREVIOUS_DOMAIN=""
for path in "/root/domain.txt" "/root/domain" "/etc/xray/domain" "/etc/v2ray/domain"; do
    if [ -s "$path" ]; then
        PREVIOUS_DOMAIN=$(cat "$path" | tr -d '[:space:]')
        break
    fi
done

show_banner
show_install_plan
detect_os

# Clean everything before install
clean_old_services

# Secure SSH before anything else
secure_ssh

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

mkdir -p /etc/xray /etc/v2ray /etc/nginx/conf.d /etc/nginx/stream.d

echo -e "[ ${BBlue}ℹ NOTES${NC} ] Checking headers"
sleep 0.5

totet=`uname -r`
REQUIRED_PKG="linux-headers-$totet"
PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2>/dev/null|grep "install ok installed")
if [ "" = "$PKG_OK" ]; then
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

apt install git curl -y >/dev/null 2>&1

if [[ "$OS" == "ubuntu" ]]; then
    apt install python3 python3-pip python3-is-python -y >/dev/null 2>&1
elif [[ "$OS" == "debian" ]]; then
    apt install python3 python3-pip -y >/dev/null 2>&1
    [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ] && ln -s /usr/bin/python3 /usr/bin/python
fi
mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf

# ============================================================
# DOMAIN CHOICE INTERACTIVE LOOP
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
        
        if [ -f /root/domain.txt ]; then
            PREVIOUS_DOMAIN=$(cat /root/domain.txt | tr -d '[:space:]')
        elif [ -f /root/domain ]; then
            PREVIOUS_DOMAIN=$(cat /root/domain | tr -d '[:space:]')
        fi
        break

    elif [[ "$dns" == "2" ]]; then
        read -rp " Enter Your Domain : " dom
        dom="${dom//[[:space:]]/}"
        if [ -z "$dom" ]; then
            echo -e "${BRed}✗ ERROR:${NC} Domain cannot be empty"
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
        echo -e "${BRed}✗ ERROR:${NC} Invalid Option. Please choose 1, 2, or 3."
        sleep 1
        continue
    fi
done

# Sync domain variables
mkdir -p /etc/xray /etc/v2ray
echo "$PREVIOUS_DOMAIN" > /root/scdomain
echo "$PREVIOUS_DOMAIN" > /etc/xray/scdomain
echo "$PREVIOUS_DOMAIN" > /etc/xray/domain
echo "$PREVIOUS_DOMAIN" > /etc/v2ray/domain
echo "$PREVIOUS_DOMAIN" > /root/domain
echo "$PREVIOUS_DOMAIN" > /root/domain.txt
echo "IP=$PREVIOUS_DOMAIN" > /var/lib/ipvps.conf

# Set DNSTT variables AFTER domain is set
export DOMAIN="$PREVIOUS_DOMAIN"
export nsdomain="ns.${DOMAIN}"
export PUBKEY=""

echo -e "[ ${BGreen}✓ SUCCESS${NC} ] Active Configuration Domain set to: ${BYellow}${PREVIOUS_DOMAIN}${NC}"
echo -e "[ ${BGreen}✓ SUCCESS${NC} ] NS Domain: ${BYellow}${nsdomain}${NC}"
sleep 2
clear

# ============================================================
# DOWNLOAD & RUN CONSTITUENT INSTALLERS (Updated Order)
# ============================================================

show_banner
echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BCyan}║${BWhite}               STARTING MODULAR INSTALLATION              ${BCyan}║${NC}"
echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   ${BGreen}Step 1/6:${NC} SSL Certificate..."
echo -e "   ${BGreen}Step 2/6:${NC} SSH/Dropbear/Stunnel/WS Proxy..."
echo -e "   ${BGreen}Step 3/6:${NC} Python WS + Squid + BADVPN..."
echo -e "   ${BGreen}Step 4/6:${NC} Xray Core (Internal Ports)..."
echo -e "   ${BGreen}Step 5/6:${NC} Nginx Unified Reverse Proxy..."
echo -e "   ${BGreen}Step 6/6:${NC} DNSTT SlowDNS..."
echo ""

# ---- Step 1: Certificate ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 1/6: Generating SSL Certificate${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q -O /usr/local/bin/create-cert.sh "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/create-cert.sh"
sed -i 's/\r$//' /usr/local/bin/create-cert.sh
chmod +x /usr/local/bin/create-cert.sh
bash /usr/local/bin/create-cert.sh
print_success "Certificate created"

# ---- Step 2: SSH VPN ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 2/6: Installing SSH/Dropbear/Stunnel/WS Proxy${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh -O ssh-vpn.sh
sed -i 's/\r$//' ssh-vpn.sh
chmod +x ssh-vpn.sh
bash ssh-vpn.sh
print_success "SSH VPN installed"

# ---- Step 3: WebSocket + Proxy + BADVPN ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 3/6: Installing Python WS + Squid Proxy + BADVPN${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh -O insshws.sh
sed -i 's/\r$//' insshws.sh
chmod +x insshws.sh
bash insshws.sh
print_success "WebSocket + Proxy + BADVPN installed"

# ---- Step 4: Xray Core ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 4/6: Installing Xray Core (Internal Ports)${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh -O ins-xray.sh
sed -i 's/\r$//' ins-xray.sh
chmod +x ins-xray.sh
bash ins-xray.sh
print_success "Xray core installed"

# ---- Step 5: Nginx Reverse Proxy (NEW) ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 5/6: Installing Nginx Unified Reverse Proxy${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/nginx/nginx-setup.sh -O nginx-setup.sh
sed -i 's/\r$//' nginx-setup.sh
chmod +x nginx-setup.sh
# Auto-detect mode (option 1) for automated install
echo "1" | bash nginx-setup.sh 2>/dev/null || bash nginx-setup.sh
print_success "Nginx reverse proxy installed"

# ---- Step 6: DNSTT (UDP + DoH) ----
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  STEP 6/6: Installing DNSTT SlowDNS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/dnstt/install-dnstt.sh -O install-dnstt.sh
sed -i 's/\r$//' install-dnstt.sh
chmod +x install-dnstt.sh
bash install-dnstt.sh
print_success "DNSTT installed"

# ============================================================
# FINALIZE
# ============================================================
clear
cat > /root/.profile << END
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
touch /etc/log-create-ssh.log /etc/log-create-vmess.log /etc/log-create-vless.log /etc/log-create-trojan.log /etc/log-create-shadowsocks.log
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
echo -e "${BWhite}                   🔧 MANAGEMENT COMMANDS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   ${BGreen}menu${NC}           - Main menu"
echo -e "   ${BGreen}vpn-status${NC}     - Check all services"
echo -e "   ${BGreen}nginx-proxy${NC}    - Nginx proxy management"
echo -e "   ${BGreen}xray-info${NC}      - Xray configuration info"
echo -e "   ${BGreen}proxy-status${NC}   - Proxy services status"
echo -e "   ${BGreen}usernew${NC}        - Create SSH user"
echo -e "   ${BGreen}trial${NC}          - Create trial user"
echo -e "   ${BGreen}cek${NC}            - Check user accounts"
echo ""
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}                   📡 CONNECTION PORTS${NC}"
echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "   ${BYellow}All services via Nginx reverse proxy:${NC}"
echo -e "   ├── Port 80  : HTTP (WebSocket, Xray NTLS)"
echo -e "   ├── Port 443 : HTTPS (WebSocket SSL, Xray TLS, gRPC)"
echo -e "   ├── Port 22  : SSH Direct"
echo -e "   ├── Port 109 : Dropbear"
echo -e "   ├── Port 143 : Dropbear Alt"
echo -e "   ├── Port 3128: Squid Proxy"
echo -e "   ├── Port 8082: Squid Proxy"
echo -e "   └── Port 8888: Squid Proxy"
echo ""

secs_to_human "$(($(date +%s) - ${start}))" | tee -a log-install.txt

# Save install log
echo "Installation completed on: $(date)" >> /root/log-install.txt
echo "Domain: $PREVIOUS_DOMAIN" >> /root/log-install.txt
echo "Version: 3.0 (Modular - Nginx Unified Proxy)" >> /root/log-install.txt

rm -f /root/setup.sh /root/ins-xray.sh /root/insshws.sh /root/ssh-vpn.sh /root/create-cert.sh /root/install-dnstt.sh /root/nginx-setup.sh 2>/dev/null
exit 0