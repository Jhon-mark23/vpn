#!/bin/bash
# ============================================================
# MARCSCRIPT VPN INSTALLER v3.2 (Ubuntu/Debian Compatible)
# All-in-One VPN Solution for Debian & Ubuntu
# ============================================================
# Version: 3.2 (Fixed PEP 668, Improved Error Handling)
# Author: MarcScript
# ============================================================

set -euo pipefail  # Strict error handling

# ---------- COLOURS ----------
readonly RED='\e[1;31m'
readonly GREEN='\e[0;32m'
readonly YELLOW='\e[1;33m'
readonly BLUE='\e[1;34m'
readonly PURPLE='\e[1;35m'
readonly CYAN='\e[1;36m'
readonly WHITE='\e[1;37m'
readonly NC='\e[0m'

# ---------- LOGGING FUNCTIONS ----------
log_info()    { echo -e "[ ${GREEN}✓${NC} ] $1"; }
log_error()   { echo -e "[ ${RED}✗${NC} ] $1" >&2; }
log_warning() { echo -e "[ ${YELLOW}⚠${NC} ] $1"; }
log_success() { echo -e "[ ${CYAN}▶${NC} ] $1"; }
log_header()  { echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ---------- BANNER ----------
show_banner() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗            ║
║     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝            ║
║     ██╔████╔██║███████║██████╔╝██║     ███████╗            ║
║     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║            ║
║     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║            ║
║     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝            ║
║         ALL-IN-ONE VPN INSTALLER v3.2                      ║
║         Ubuntu / Debian Compatible                         ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# ---------- DETECT OS ----------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        readonly OS=$ID
        readonly VER=$VERSION_ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi
    
    log_info "Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "This script only supports Ubuntu or Debian"
        exit 1
    fi
    
    # Detect if Debian 13 (trixie) for PEP 668 handling
    if [[ "$OS" == "debian" ]] && [[ "$VER" == "13" ]] || [[ "$VER" == "trixie" ]]; then
        readonly DEBIAN_13=true
        log_info "Debian 13 (trixie) detected - using PEP 668 workaround"
    else
        readonly DEBIAN_13=false
    fi
}

# ---------- PRE-FLIGHT CHECKS ----------
pre_flight_checks() {
    # Root check
    if [ "${EUID}" -ne 0 ]; then
        log_error "You need to run this script as root"
        exit 1
    fi
    
    # Virtualization check
    if [ "$(systemd-detect-virt)" == "openvz" ]; then
        log_error "OpenVZ is not supported"
        exit 1
    fi
    
    # Fix hosts file
    local localip=$(hostname -I | awk '{print $1}')
    local hostname=$(hostname)
    if ! grep -q "$hostname" /etc/hosts; then
        echo "$localip $hostname" >> /etc/hosts
        log_info "Added hostname to /etc/hosts"
    fi
}

# ---------- CLEANUP SERVICES ----------
cleanup_services() {
    log_info "Cleaning old services..."
    
    local services=(
        "nginx" "stunnel4" "dropbear" "fail2ban" "xray"
        "ws-dropbear" "ws-stunnel" "server-sldns-udp" "server-sldns-doh"
        "client-sldns" "dnstt-server" "dnstt-client"
        "systemd-networkd" "systemd-resolved"  # Network services
    )
    
    # Stop and disable services
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$svc"; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
        fi
    done
    
    # Kill processes
    local processes=(
        "nginx" "stunnel4" "badvpn-udpgw" "screen.*badvpn" "xray"
        "ws-dropbear" "ws-stunnel" "sldns-server" "sldns-client"
        "dnstt-server" "dnstt-client"
    )
    
    for proc in "${processes[@]}"; do
        pkill -f "$proc" 2>/dev/null || true
    done
    
    # Remove directories
    local dirs=(
        "/etc/slowdns" "/etc/dnstt" "/etc/nginx/conf.d"
        "/etc/stunnel" "/etc/xray" "/etc/v2ray"
        "/var/log/xray" "/opt/ws-proxy" "/root/.acme.sh"
    )
    
    for dir in "${dirs[@]}"; do
        rm -rf "$dir" 2>/dev/null || true
    done
    
    # Recreate empty directories with proper permissions
    mkdir -p /etc/xray /etc/v2ray /etc/stunnel /etc/nginx/conf.d
    mkdir -p /var/log/xray
    
    # Remove service files
    find /etc/systemd/system/ -name "*sldns*.service" -delete 2>/dev/null || true
    find /etc/systemd/system/ -name "dnstt*.service" -delete 2>/dev/null || true
    
    # Remove binaries
    local binaries=(
        "/usr/bin/badvpn-udpgw" "/usr/local/bin/ws-dropbear"
        "/usr/local/bin/ws-stunnel" "/usr/local/bin/xray"
        "/usr/local/bin/create-cert.sh"
    )
    
    for bin in "${binaries[@]}"; do
        rm -f "$bin" 2>/dev/null || true
    done
    
    # Remove menu scripts
    rm -f /usr/bin/menu /usr/bin/m-* /usr/bin/usernew /usr/bin/trial
    rm -f /usr/bin/renew /usr/bin/hapus /usr/bin/cek /usr/bin/member
    rm -f /usr/bin/delete /usr/bin/autokill /usr/bin/ceklim /usr/bin/tendang
    
    # Clean iptables
    cleanup_iptables
    
    # Restart network services
    systemctl restart systemd-networkd 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
    
    # Clean package cache
    apt clean 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# ---------- CLEANUP IPTABLES ----------
cleanup_iptables() {
    # Remove DNSTT redirect rules
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Save rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save 2>/dev/null || true
    fi
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
}

# ---------- CONFIGURE SSH ----------
configure_ssh() {
    log_info "Configuring SSH..."
    
    # Backup config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true
    
    # Write new config
    cat > /etc/ssh/sshd_config <<'EOF'
# ============================================================
# MARCSCRIPT SSH CONFIG - Secure Remote Access
# ============================================================

Port 22
Port 9696
Port 2222
Port 2269

PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
PermitEmptyPasswords no

MaxAuthTries 5
MaxSessions 10
LoginGraceTime 60
ClientAliveInterval 60
ClientAliveCountMax 3

UseDNS no
PrintMotd no
X11Forwarding no

Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    
    # Restart SSH
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    
    log_success "SSH configured on ports 22, 9696, 2222, 2269"
}

# ---------- INSTALL DEPENDENCIES ----------
install_dependencies() {
    log_info "Installing dependencies..."
    
    apt update -y
    
    local packages=(
        "git" "curl" "wget" "jq" "python3" "python3-pip"
        "net-tools" "dnsutils" "iptables" "iptables-persistent"
        "sudo" "gnutls-bin" "dos2unix" "debconf-utils"
        "ca-certificates" "openssl" "python3-dnslib"
        "nginx" "stunnel4" "dropbear" "squid"
    )
    
    # Install packages with fallback for missing ones
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            apt install -y "$pkg" 2>/dev/null || {
                log_warning "Failed to install $pkg (may not be available)"
            }
        else
            log_info "$pkg already installed"
        fi
    done
    
    # Python symlink for Debian
    if [[ "$OS" == "debian" ]] && [ ! -f /usr/bin/python ]; then
        ln -sf /usr/bin/python3 /usr/bin/python
    fi
    
    # Install pip packages with proper handling
    # PEP 668 protection workaround for Debian 13+
    install_pip_packages
    
    log_success "Dependencies installed"
}

# ---------- INSTALL PIP PACKAGES ----------
install_pip_packages() {
    # Upgrade pip
    if [[ "$DEBIAN_13" == true ]]; then
        python3 -m pip install --upgrade pip --break-system-packages 2>/dev/null || true
    else
        python3 -m pip install --upgrade pip 2>/dev/null || true
    fi
    
    # Install required pip packages
    local pip_packages=("websocket-client" "websockets")
    
    for pkg in "${pip_packages[@]}"; do
        if ! python3 -c "import $pkg" 2>/dev/null; then
            log_info "Installing Python package: $pkg"
            if [[ "$DEBIAN_13" == true ]]; then
                python3 -m pip install "$pkg" --break-system-packages 2>/dev/null || {
                    log_warning "Failed to install $pkg via pip, trying apt..."
                    # Try apt fallback for Debian 13
                    apt install -y "python3-${pkg//-/_}" 2>/dev/null || true
                }
            else
                python3 -m pip install "$pkg" 2>/dev/null || {
                    log_warning "Failed to install $pkg via pip"
                }
            fi
        fi
    done
}

# ---------- INSTALL COMPONENT ----------
install_component() {
    local name=$1
    local url=$2
    local target=$3
    local args=${4:-}
    
    log_info "Installing $name..."
    
    # Add retry logic
    local max_retries=3
    local retry=0
    local success=0
    
    while [ $retry -lt $max_retries ] && [ $success -eq 0 ]; do
        if wget -q --timeout=30 --tries=2 -O "$target" "$url" 2>/dev/null; then
            success=1
        else
            retry=$((retry + 1))
            log_warning "Download failed, retry $retry/$max_retries"
            sleep 2
        fi
    done
    
    if [ $success -eq 0 ]; then
        log_error "Failed to download $name after $max_retries attempts"
        return 1
    fi
    
    # Fix line endings
    sed -i 's/\r$//' "$target"
    chmod +x "$target"
    
    # Run the script
    if [ -n "$args" ]; then
        bash "$target" "$args"
    else
        bash "$target"
    fi
    
    log_success "$name installed"
}

# ---------- INSTALL ALL COMPONENTS ----------
install_components() {
    local domain=$1
    local nsdomain="ns.${domain}"
    
    # Create directories
    mkdir -p /etc/xray /etc/v2ray /var/lib
    
    # Set up domain
    echo "$domain" > /root/scdomain
    echo "$domain" > /etc/xray/scdomain
    echo "$domain" > /etc/xray/domain
    echo "$domain" > /etc/v2ray/domain
    echo "$domain" > /root/domain
    echo "$domain" > /root/domain.txt
    echo "IP=$domain" > /var/lib/ipvps.conf
    
    log_info "Domain set to: $domain"
    log_info "NS Domain: $nsdomain"
    
    # Export for sub-scripts
    export DOMAIN="$domain"
    export nsdomain="$nsdomain"
    
    # Install components
    local components=(
        "Certificate|https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/create-cert.sh|/usr/local/bin/create-cert.sh"
        "SSH VPN|https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/ssh-vpn.sh|/root/ssh-vpn.sh"
        "WebSocket|https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/insshws.sh|/root/insshws.sh"
        "Xray|https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/ins-xray.sh|/root/ins-xray.sh"
        "DNSTT|https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/dnstt/install-dnstt.sh|/root/install-dnstt.sh"
    )
    
    for comp in "${components[@]}"; do
        IFS='|' read -r name url target <<< "$comp"
        install_component "$name" "$url" "$target"
    done
}

# ---------- DOMAIN SELECTION ----------
select_domain() {
    local previous_domain=""
    
    # Find previous domain
    for path in "/root/domain.txt" "/root/domain" "/etc/xray/domain" "/etc/v2ray/domain"; do
        if [ -s "$path" ]; then
            previous_domain=$(cat "$path" | tr -d '[:space:]')
            break
        fi
    done
    
    while true; do
        show_banner
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${WHITE}                    DOMAIN CONFIGURATION                  ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN} 1. ${NC}Use Random Domain (via Cloudflare)"
        echo -e "${GREEN} 2. ${NC}Use Your Own Domain"
        echo -e "${GREEN} 3. ${NC}Re-use Previous Domain"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        if [ -n "$previous_domain" ]; then
            echo -e "${CYAN} ℹ Previous domain: ${YELLOW}${previous_domain}${NC}"
        else
            echo -e "${CYAN} ℹ No previous domain found.${NC}"
        fi
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        read -rp " Select domain option [1-3]: " choice
        
        case "${choice//[[:space:]]/}" in
            1)
                show_banner
                log_info "Generating random domain..."
                
                # Use CDN variable
                local CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
                
                if ! wget -q -O /root/cf "${CDN}/cf" 2>/dev/null; then
                    log_error "Failed to download Cloudflare script"
                    sleep 2
                    continue
                fi
                chmod +x /root/cf
                bash /root/cf | tee /root/install.log
                
                # Get the generated domain
                if [ -f /root/domain.txt ]; then
                    previous_domain=$(cat /root/domain.txt | tr -d '[:space:]')
                elif [ -f /root/domain ]; then
                    previous_domain=$(cat /root/domain | tr -d '[:space:]')
                fi
                
                if [ -z "$previous_domain" ]; then
                    log_error "Failed to generate domain"
                    sleep 2
                    continue
                fi
                
                echo "$previous_domain"
                return 0
                ;;
            2)
                read -rp " Enter Your Domain: " domain
                domain="${domain//[[:space:]]/}"
                if [ -z "$domain" ]; then
                    log_error "Domain cannot be empty"
                    sleep 1
                    continue
                fi
                echo "$domain"
                return 0
                ;;
            3)
                if [ -z "$previous_domain" ]; then
                    log_error "No previous domain found!"
                    sleep 2
                    continue
                fi
                echo "$previous_domain"
                return 0
                ;;
            *)
                log_error "Invalid option. Please choose 1, 2, or 3."
                sleep 1
                continue
                ;;
        esac
    done
}

# ---------- FINALIZE INSTALLATION ----------
finalize_installation() {
    # Create profile
    cat > /root/.profile << 'EOF'
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
tty -s && mesg n || true
clear
menu
EOF
    chmod 644 /root/.profile
    
    # Create log files
    touch /etc/log-create-ssh.log 2>/dev/null || true
    touch /etc/log-create-vmess.log 2>/dev/null || true
    touch /etc/log-create-vless.log 2>/dev/null || true
    touch /etc/log-create-trojan.log 2>/dev/null || true
    touch /etc/log-create-shadowsocks.log 2>/dev/null || true
    
    # Save version
    local version=$(curl -sS --connect-timeout 5 https://raw.githubusercontent.com/Jhon-mark23/vpn/main/menu/versi 2>/dev/null || echo "3.2")
    echo "$version" > /opt/.ver
    
    # Save IP
    curl -sS --connect-timeout 5 ipv4.icanhazip.com > /etc/myipvps 2>/dev/null || echo "0.0.0.0" > /etc/myipvps
    
    # Clean up
    rm -f /root/setup.sh /root/ins-xray.sh /root/insshws.sh 2>/dev/null || true
    rm -f /root/ssh-vpn.sh /root/create-cert.sh /root/install-dnstt.sh 2>/dev/null || true
    rm -f /root/cf /root/install.log 2>/dev/null || true
    
    history -c
}

# ---------- SECONDS TO HUMAN ----------
secs_to_human() {
    local seconds=$1
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Installation time: $(( seconds / 3600 ))h $(( (seconds / 60) % 60 ))m $(( seconds % 60 ))s${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---------- SHOW COMPLETE ----------
show_complete() {
    show_banner
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              ✅ INSTALLATION COMPLETE!                      ║
╚══════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  🔧 MANAGEMENT COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   menu         - Main menu
   create       - Create SSH user
   vpn-status   - Check service status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  📡 SERVICE PORTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   SSH Direct    : 22, 9696
   SSH SSL       : 222, 777
   SSH WS        : 80, 2095
   SSH WSS       : 443, 700
   Xray          : 80, 443
   Squid Proxy   : 3128, 8082, 8888
   DNSTT (UDP)   : 5300
   DNSTT (DoH)   : 8443

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# ---------- MAIN ----------
main() {
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    
    # Configure needrestart
    if [ -f /etc/needrestart/needrestart.conf ]; then
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
        sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi
    
    # Setup
    readonly CDN="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ssh"
    local start_time=$(date +%s)
    
    # Set timezone
    ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
    timedatectl set-timezone Asia/Manila 2>/dev/null || true
    
    # Disable IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    
    # Initial checks
    show_banner
    detect_os
    pre_flight_checks
    
    # Cleanup
    cleanup_services
    
    # Configure SSH
    configure_ssh
    
    # Install dependencies
    install_dependencies
    
    # Select and set domain
    local domain=$(select_domain)
    
    # Install components
    install_components "$domain"
    
    # Finalize
    finalize_installation
    show_complete
    secs_to_human "$(($(date +%s) - start_time))" | tee -a log-install.txt
    
    # Check if xray is running
    if systemctl is-active --quiet xray.service 2>/dev/null; then
        log_success "Xray service is running successfully!"
    else
        log_warning "Xray service may need manual start. Check with: systemctl status xray"
    fi
    
    exit 0
}

# ---------- SCRIPT ENTRY ----------
main "$@"