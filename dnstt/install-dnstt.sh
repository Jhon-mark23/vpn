#!/bin/bash
# ============================================================
# MARCSCRIPT DNSTT INSTALLER
# DNS Tunnel with UDP + DoH Support
# No port conflicts with existing services
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}OK${NC} ] $1"; }
print_step()  { echo -e "[ ${CYAN}STEP${NC} ] $1"; }

# ============================================================
# CONFIGURATION
# ============================================================
GITHUB_RAW="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_LOG_DIR="/var/log/slowdns"

# Ports (non-conflicting - Xray safe)
DNSTT_UDP_PORT="5300"        # DNS tunnel UDP port (Xray safe)
DNSTT_DOH_PORT="8443"        # DNS over HTTPS port (Xray uses 443)
SSH_PORT="2222"              # Existing SSH port
DNSTT_ALT_SSH="2269"         # Alternative SSH port

# DNS Resolvers
PUBLIC_DNS="8.8.8.8:53"
DOH_RESOLVER="https://dns.google/dns-query"

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    print_step "Detecting operating system..."
    
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
# DETECT ARCHITECTURE
# ============================================================
detect_arch() {
    print_step "Detecting system architecture..."
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  SLOWDNS_ARCH="amd64" ;;
        i386|i686) SLOWDNS_ARCH="386" ;;
        aarch64|arm64) SLOWDNS_ARCH="arm64" ;;
        armv7l)  SLOWDNS_ARCH="armv7" ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    print_info "Architecture: $ARCH → $SLOWDNS_ARCH"
}

# ============================================================
# CHECK PORT AVAILABILITY
# ============================================================
check_ports() {
    print_step "Checking port availability..."
    
    # Check UDP port 5300
    if ss -uln | grep -q ":5300 "; then
        print_warn "Port 5300 is already in use!"
        read -p "Use different UDP port? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -rp "Enter new UDP port: " DNSTT_UDP_PORT
        else
            print_error "Port conflict detected. Cannot continue."
            exit 1
        fi
    fi
    
    # Check port 8443 (DoH)
    if ss -tuln | grep -q ":8443 "; then
        print_warn "Port 8443 is already in use!"
        read -p "Use different DoH port? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -rp "Enter new DoH port: " DNSTT_DOH_PORT
        else
            print_warn "DoH will use port 443 (may conflict with Xray)"
            DNSTT_DOH_PORT="443"
        fi
    fi
    
    print_success "Ports checked: UDP $DNSTT_UDP_PORT, DoH $DNSTT_DOH_PORT"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Configuring DNS Tunnel domain..."
    
    # Try to get domain from existing files
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "")
    
    if [ -z "$DOMAIN" ]; then
        read -rp "Enter main domain: " DOMAIN
    else
        print_info "Using existing domain: $DOMAIN"
        read -p "Use different domain? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -rp "Enter main domain: " DOMAIN
        fi
    fi
    
    # Read subdomain
    read -rp "Enter subdomain prefix [ns]: " SUB
    SUB=${SUB:-ns}
    
    # Build NS domain
    SUB_DOMAIN="${SUB}.${DOMAIN}"
    NS_DOMAIN="${SUB_DOMAIN}"
    
    echo "$NS_DOMAIN" > /root/nsdomain
    echo "$NS_DOMAIN" > /root/nsdomain.txt
    echo "$DOMAIN" > /root/domain
    
    print_info "NS Domain: ${CYAN}${NS_DOMAIN}${NC}"
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    apt update -y
    apt install -y python3 python3-dnslib net-tools dnsutils \
                   git curl wget screen cron iptables dropbear \
                   sudo gnutls-bin dos2unix debconf-utils \
                   ca-certificates openssl ncat netcat-openbsd
    
    apt install -y ncurses-utils 2>/dev/null || {
        print_warn "ncurses-utils not found, skipping (not critical)"
    }
    
    systemctl restart cron 2>/dev/null || {
        print_warn "Failed to restart cron, continuing..."
    }
    
    print_success "Packages installed"
}

# ============================================================
# CONFIGURE SSH
# ============================================================
configure_ssh() {
    print_step "Configuring SSH for DNSTT..."
    
    # Add SSH ports if not present
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        print_info "Added SSH port $SSH_PORT"
    fi
    
    if ! grep -q "^Port $DNSTT_ALT_SSH" /etc/ssh/sshd_config; then
        echo "Port $DNSTT_ALT_SSH" >> /etc/ssh/sshd_config
        print_info "Added SSH port $DNSTT_ALT_SSH"
    fi
    
    sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    sleep 2
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        print_success "SSH configured and running"
    else
        print_warn "SSH may not be running, check manually"
    fi
}

# ============================================================
# SETUP IPTABLES (No port 53 redirect to avoid conflicts)
# ============================================================
setup_iptables() {
    print_step "Setting up iptables rules (no port 53 redirect)..."
    
    # Install iptables if not present
    apt install -y iptables iptables-persistent netfilter-persistent 2>/dev/null || true
    
    # Allow UDP port 5300 (DNSTT)
    iptables -I INPUT -p udp --dport $DNSTT_UDP_PORT -j ACCEPT 2>/dev/null || true
    
    # Allow DoH port
    iptables -I INPUT -p tcp --dport $DNSTT_DOH_PORT -j ACCEPT 2>/dev/null || true
    
    # DO NOT redirect port 53 - this avoids Nginx conflict
    # iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Save rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    print_success "Iptables configured (no port 53 redirect)"
}

# ============================================================
# INSTALL DNSTT BINARIES
# ============================================================
install_binaries() {
    print_step "Installing DNSTT binaries..."
    
    rm -rf "$SLOWDNS_DIR"
    mkdir -m 755 "$SLOWDNS_DIR"
    mkdir -p "$SLOWDNS_LOG_DIR"
    
    print_info "Downloading DNSTT server binary..."
    wget -q -O "$SLOWDNS_DIR/sldns-server" "$GITHUB_RAW/dnstt/dnstt-server-linux-${SLOWDNS_ARCH}" 2>/dev/null || {
        print_error "Failed to download server binary!"
        print_error "URL: $GITHUB_RAW/dnstt/dnstt-server-linux-${SLOWDNS_ARCH}"
        exit 1
    }
    
    print_info "Downloading DNSTT client binary..."
    wget -q -O "$SLOWDNS_DIR/sldns-client" "$GITHUB_RAW/dnstt/dnstt-client-linux-${SLOWDNS_ARCH}" 2>/dev/null || {
        print_warn "Failed to download client binary (may be normal on server)"
    }
    
    chmod +x "$SLOWDNS_DIR/sldns-server"
    chmod +x "$SLOWDNS_DIR/sldns-client" 2>/dev/null || true
    
    if "$SLOWDNS_DIR/sldns-server" 2>&1 | grep -q "Usage\|privkey-file"; then
        print_success "DNSTT server binary verified"
    else
        print_error "DNSTT server binary verification failed!"
        exit 1
    fi
}

# ============================================================
# GENERATE KEYS
# ============================================================
generate_keys() {
    print_step "Generating DNSTT keypair..."
    
    cd "$SLOWDNS_DIR"
    
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        print_info "Keys already exist"
        read -p "Regenerate? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
            chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
            return 0
        fi
    fi
    
    ./sldns-server -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub" 2>/dev/null
    
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
        chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
        
        PUBKEY=$(cat "$SLOWDNS_DIR/server.pub")
        print_success "Keypair generated"
        print_info "Public Key: ${YELLOW}${PUBKEY}${NC}"
    else
        print_error "Key generation failed!"
        exit 1
    fi
}

# ============================================================
# CREATE SYSTEMD SERVICES (UDP + DoH)
# ============================================================
create_services() {
    print_step "Creating systemd services..."
    
    # Server Service - UDP Mode (port 5300)
    cat > /etc/systemd/system/server-sldns-udp.service <<EOF
[Unit]
Description=MarcScript DNSTT Server (UDP Mode)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$SLOWDNS_DIR/sldns-server -udp :$DNSTT_UDP_PORT -privkey-file $SLOWDNS_DIR/server.key $NS_DOMAIN 127.0.0.1:$DNSTT_ALT_SSH
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Server Service - DoH Mode (port 8443)
    cat > /etc/systemd/system/server-sldns-doh.service <<EOF
[Unit]
Description=MarcScript DNSTT Server (DoH Mode)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$SLOWDNS_DIR/sldns-server -doh :$DNSTT_DOH_PORT -privkey-file $SLOWDNS_DIR/server.key $NS_DOMAIN 127.0.0.1:$DNSTT_ALT_SSH
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Client Service (UDP - optional)
    cat > /etc/systemd/system/client-sldns.service <<EOF
[Unit]
Description=MarcScript DNSTT Client (UDP Mode)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$SLOWDNS_DIR/sldns-client -udp $PUBLIC_DNS --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:$SSH_PORT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/server-sldns-udp.service
    chmod 644 /etc/systemd/system/server-sldns-doh.service
    chmod 644 /etc/systemd/system/client-sldns.service
    
    print_success "Systemd services created"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting DNSTT services..."
    
    pkill sldns-server 2>/dev/null || true
    pkill sldns-client 2>/dev/null || true
    
    systemctl daemon-reload
    
    # Stop existing
    systemctl stop server-sldns-udp server-sldns-doh client-sldns 2>/dev/null || true
    
    # Start UDP server
    systemctl enable server-sldns-udp 2>/dev/null
    systemctl start server-sldns-udp 2>/dev/null
    
    # Start DoH server
    systemctl enable server-sldns-doh 2>/dev/null
    systemctl start server-sldns-doh 2>/dev/null
    
    # Start client (optional)
    systemctl enable client-sldns 2>/dev/null
    systemctl start client-sldns 2>/dev/null
    
    sleep 3
    
    # Verify UDP
    if systemctl is-active --quiet server-sldns-udp; then
        print_success "DNSTT Server (UDP) running on port $DNSTT_UDP_PORT"
    else
        print_error "DNSTT Server (UDP) failed!"
        journalctl -u server-sldns-udp --no-pager -n 10 2>/dev/null || true
    fi
    
    # Verify DoH
    if systemctl is-active --quiet server-sldns-doh; then
        print_success "DNSTT Server (DoH) running on port $DNSTT_DOH_PORT"
    else
        print_error "DNSTT Server (DoH) failed!"
        journalctl -u server-sldns-doh --no-pager -n 10 2>/dev/null || true
    fi
    
    if systemctl is-active --quiet client-sldns; then
        print_success "DNSTT Client running"
    else
        print_warn "DNSTT Client not running (may be normal on server)"
    fi
}

# ============================================================
# CREATE CLIENT CONFIG
# ============================================================
create_client_config() {
    print_step "Creating client configuration..."
    
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    PUBKEY=$(cat "$SLOWDNS_DIR/server.pub")
    
    cat > "$SLOWDNS_DIR/client-config.txt" <<EOF
====================================
MARCSCRIPT DNSTT CLIENT CONFIG
====================================
Server IP    : $SERVER_IP
NS Domain    : $NS_DOMAIN
Public Key   : $PUBKEY

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 MODE 1: UDP (Port 5300) - WiFi Only
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$SLOWDNS_DIR/sldns-client -udp $SERVER_IP:$DNSTT_UDP_PORT --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 MODE 2: DoH (Port $DNSTT_DOH_PORT) - WiFi + Mobile Data
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$SLOWDNS_DIR/sldns-client -doh https://$SERVER_IP:$DNSTT_DOH_PORT --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 MODE 3: DoH via Google DNS (Mobile Data)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$SLOWDNS_DIR/sldns-client -doh https://dns.google/dns-query --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 HTTP Custom / KPN Tunnel Settings
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SSH Host    : $SERVER_IP
SSH Port    : $SSH_PORT
Username    : (your username)
Password    : (your password)
SlowDNS     : ON
DNS         : 8.8.8.8
NS Domain   : $NS_DOMAIN
Pubkey      : $PUBKEY

For mobile data, use DoH mode with Google DNS.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 SERVICE MANAGEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
UDP Server  : systemctl status server-sldns-udp
DoH Server  : systemctl status server-sldns-doh
Logs        : journalctl -u server-sldns-udp -f
            : journalctl -u server-sldns-doh -f
Restart UDP : systemctl restart server-sldns-udp
Restart DoH : systemctl restart server-sldns-doh

====================================
EOF

    print_success "Client config saved to $SLOWDNS_DIR/client-config.txt"
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================
display_summary() {
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    PUBKEY=$(cat "$SLOWDNS_DIR/server.pub")
    
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         ✅ MARCSCRIPT DNSTT INSTALLED SUCCESSFULLY         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📡 SERVER INFORMATION:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server IP" "$SERVER_IP"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "NS Domain" "$NS_DOMAIN"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "UDP Port" "$DNSTT_UDP_PORT"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "DoH Port" "$DNSTT_DOH_PORT"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "SSH Port" "$SSH_PORT"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Alt SSH" "$DNSTT_ALT_SSH"
    echo ""
    
    echo -e "${CYAN}🔑 PUBLIC KEY:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}${PUBKEY}${NC}"
    echo ""
    
    echo -e "${CYAN}📱 CLIENT COMMANDS:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${WHITE}UDP (WiFi):${NC}"
    echo -e "  ${YELLOW}$SLOWDNS_DIR/sldns-client -udp $SERVER_IP:$DNSTT_UDP_PORT --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    echo -e "  ${WHITE}DoH (Mobile Data):${NC}"
    echo -e "  ${YELLOW}$SLOWDNS_DIR/sldns-client -doh https://$SERVER_IP:$DNSTT_DOH_PORT --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    
    echo -e "${CYAN}⚙️  SERVICE CONTROL:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}UDP Server:${NC} systemctl status server-sldns-udp"
    echo -e "  ${WHITE}DoH Server:${NC} systemctl status server-sldns-doh"
    echo -e "  ${WHITE}Restart UDP:${NC} systemctl restart server-sldns-udp"
    echo -e "  ${WHITE}Restart DoH:${NC} systemctl restart server-sldns-doh"
    echo ""
    
    echo -e "${CYAN}📁 FILES:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Binaries:${NC}    $SLOWDNS_DIR/"
    echo -e "  ${WHITE}Keys:${NC}        $SLOWDNS_DIR/server.key | server.pub"
    echo -e "  ${WHITE}Config:${NC}      $SLOWDNS_DIR/client-config.txt"
    echo -e "  ${WHITE}NS Domain:${NC}   /root/nsdomain"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         🔒 MARCSCRIPT DNSTT INSTALLER                      ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${WHITE}         UDP + DoH Support - No Port Conflicts             ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Features:${NC}"
    echo -e "  • UDP Mode (Port 5300) - Works on WiFi"
    echo -e "  • DoH Mode (Port 8443) - Works on Mobile Data"
    echo -e "  • No port 53 redirect (no Nginx conflict)"
    echo -e "  • Xray compatible (uses 8443 instead of 443)"
    echo ""
    echo -e "${CYAN}Ports:${NC}"
    echo -e "  UDP Tunnel: $DNSTT_UDP_PORT"
    echo -e "  DoH Tunnel: $DNSTT_DOH_PORT"
    echo -e "  SSH: $SSH_PORT, $DNSTT_ALT_SSH"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    detect_os
    detect_arch
    check_ports
    get_domain
    install_packages
    configure_ssh
    setup_iptables
    install_binaries
    generate_keys
    create_services
    start_services
    create_client_config
    display_summary
}

main "$@"