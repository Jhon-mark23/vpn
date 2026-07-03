#!/bin/bash
# ============================================================
# MARCSCRIPT DNSTT INSTALLER
# DNS Tunnel (SlowDNS) with UDP Support
# Compatible with existing SSH/Xray setup
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

# Ports (non-conflicting)
DNSTT_UDP_PORT="5300"        # DNS tunnel server port
SSH_PORT="2222"              # Existing SSH port (from ssh-vpn.sh)
DNSTT_ALT_SSH="2269"         # Alternative SSH port

# DNS Resolver
PUBLIC_DNS="8.8.8.8:53"

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

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
# SETUP IPTABLES
# ============================================================
setup_iptables() {
    print_step "Setting up iptables rules..."
    
    # Allow UDP port 5300
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    
    # Redirect DNS (port 53) to DNSTT port (5300)
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Save rules
    netfilter-persistent save 2>/dev/null || true
    netfilter-persistent reload 2>/dev/null || true
    
    print_success "Iptables configured"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Configuring DNS Tunnel domain..."
    
    # Read domain
    read -rp "Enter main domain: " DOMAIN
    
    # Read subdomain
    read -rp "Enter subdomain prefix [dnstt]: " SUB
    SUB=${SUB:-dnstt}
    
    # Build NS domain
    SUB_DOMAIN="${SUB}.${DOMAIN}"
    NS_DOMAIN="slowdns-${SUB_DOMAIN}"
    
    echo "$NS_DOMAIN" > /root/nsdomain
    echo "$NS_DOMAIN" > /root/nsdomain.txt
    
    print_info "NS Domain: ${CYAN}${NS_DOMAIN}${NC}"
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    apt update -y
    apt install -y python3 python3-dnslib net-tools ncurses-utils dnsutils \
                   git curl wget screen cron iptables dropbear \
                   sudo gnutls-bin dos2unix debconf-utils
    
    # Reload cron
    systemctl reload cron
    systemctl restart cron
    
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
    
    # Enable TCP forwarding
    sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    
    # Restart SSH
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    sleep 2
    
    if systemctl is-active --quiet ssh; then
        print_success "SSH configured and running"
    else
        print_error "SSH failed to restart!"
    fi
}

# ============================================================
# INSTALL DNSTT BINARIES
# ============================================================
install_binaries() {
    print_step "Installing DNSTT binaries..."
    
    # Remove old directory
    rm -rf "$SLOWDNS_DIR"
    
    # Create directories
    mkdir -m 777 "$SLOWDNS_DIR"
    mkdir -p "$SLOWDNS_LOG_DIR"
    
    # Download binaries and keys from repo
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
    
    # Make executable
    chmod +x "$SLOWDNS_DIR/sldns-server"
    chmod +x "$SLOWDNS_DIR/sldns-client" 2>/dev/null || true
    
    # Verify server binary
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
    
    # Check if keys already exist
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        print_info "Keys already exist"
        read -p "Regenerate? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            chmod +x "$SLOWDNS_DIR/server.key" 2>/dev/null || true
            chmod +x "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
            return 0
        fi
    fi
    
    # Generate keys
    ./sldns-server -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub" 2>/dev/null
    
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        chmod +x "$SLOWDNS_DIR/server.key" 2>/dev/null || true
        chmod +x "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
        
        # Display public key
        PUBKEY=$(cat "$SLOWDNS_DIR/server.pub")
        print_success "Keypair generated"
        print_info "Public Key: ${YELLOW}${PUBKEY}${NC}"
    else
        print_error "Key generation failed!"
        exit 1
    fi
}

# ============================================================
# CREATE SYSTEMD SERVICES
# ============================================================
create_services() {
    print_step "Creating systemd services..."
    
    # Server Service
    cat > /etc/systemd/system/server-sldns.service <<EOF
[Unit]
Description=MarcScript DNSTT Server (SlowDNS)
Documentation=https://github.com/Jhon-mark23/vpn
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$SLOWDNS_DIR/sldns-server -udp :5300 -privkey-file $SLOWDNS_DIR/server.key $NS_DOMAIN 127.0.0.1:$DNSTT_ALT_SSH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Client Service (optional, for local testing)
    cat > /etc/systemd/system/client-sldns.service <<EOF
[Unit]
Description=MarcScript DNSTT Client (SlowDNS)
Documentation=https://github.com/Jhon-mark23/vpn
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

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod +x /etc/systemd/system/server-sldns.service
    chmod +x /etc/systemd/system/client-sldns.service
    
    print_success "Systemd services created"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting DNSTT services..."
    
    # Kill existing processes
    pkill sldns-server 2>/dev/null || true
    pkill sldns-client 2>/dev/null || true
    
    systemctl daemon-reload
    
    # Stop existing if running
    systemctl stop server-sldns client-sldns 2>/dev/null || true
    
    # Enable and start server
    systemctl enable server-sldns 2>/dev/null
    systemctl start server-sldns 2>/dev/null
    
    # Enable and start client (optional)
    systemctl enable client-sldns 2>/dev/null
    systemctl start client-sldns 2>/dev/null
    
    sleep 3
    
    # Verify
    if systemctl is-active --quiet server-sldns; then
        print_success "DNSTT Server running on UDP port 5300"
        print_info "NS Domain: $NS_DOMAIN"
    else
        print_error "DNSTT Server failed!"
        journalctl -u server-sldns --no-pager -n 10
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
    
    # Client config file
    cat > "$SLOWDNS_DIR/client-config.txt" <<EOF
====================================
MarcScript DNSTT Client Config
====================================
Server IP    : $SERVER_IP
NS Domain    : $NS_DOMAIN
DNS Port     : 5300 (UDP)
SSH Port     : $SSH_PORT
Alt SSH      : $DNSTT_ALT_SSH
Public Key   : $PUBKEY

====================================
CLIENT COMMAND EXAMPLES:
====================================

# UDP Mode (recommended)
$SLOWDNS_DIR/sldns-client -udp $SERVER_IP:5300 --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

# Using public DNS resolver
$SLOWDNS_DIR/sldns-client -udp $PUBLIC_DNS --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

# DoH Mode (DNS over HTTPS)
$SLOWDNS_DIR/sldns-client -doh https://dns.google/dns-query --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

# DoT Mode (DNS over TLS)
$SLOWDNS_DIR/sldns-client -dot dns.google:853 --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

====================================
CONNECT SSH THROUGH TUNNEL:
====================================
# Run DNSTT client locally
$SLOWDNS_DIR/sldns-client -udp $PUBLIC_DNS --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000

# Connect SSH through tunnel
ssh -p $SSH_PORT -o ProxyCommand="nc -X 5 -x 127.0.0.1:7000 %h %p" root@$SERVER_IP

# Or using direct SSH
ssh -p $SSH_PORT root@127.0.0.1

====================================
CLIENT BINARY DOWNLOAD:
====================================
$GITHUB_RAW/dnstt/dnstt-client-linux-\$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/;s/armv7l/armv7/')

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
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "DNS Port" "5300 (UDP)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "SSH Port" "$SSH_PORT"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Alt SSH" "$DNSTT_ALT_SSH"
    echo ""
    
    echo -e "${CYAN}🔑 PUBLIC KEY:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}${PUBKEY}${NC}"
    echo ""
    
    echo -e "${CYAN}📱 CLIENT QUICK COMMANDS:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}UDP Mode:${NC}"
    echo -e "  ${YELLOW}$SLOWDNS_DIR/sldns-client -udp $SERVER_IP:5300 --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    echo -e "  ${WHITE}DoH Mode:${NC}"
    echo -e "  ${YELLOW}$SLOWDNS_DIR/sldns-client -doh https://dns.google/dns-query --pubkey-file $SLOWDNS_DIR/server.pub $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    
    echo -e "${CYAN}⚙️  SERVICE CONTROL:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Server Status:${NC} systemctl status server-sldns"
    echo -e "  ${WHITE}Server Logs:${NC}  journalctl -u server-sldns -f"
    echo -e "  ${WHITE}Restart:${NC}      systemctl restart server-sldns"
    echo ""
    
    echo -e "${CYAN}📁 FILES:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Binaries:${NC}    $SLOWDNS_DIR/"
    echo -e "  ${WHITE}Keys:${NC}        $SLOWDNS_DIR/server.key | server.pub"
    echo -e "  ${WHITE}Config:${NC}      $SLOWDNS_DIR/client-config.txt"
    echo -e "  ${WHITE}NS Domain:${NC}   /root/nsdomain"
    echo ""
    
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${CYAN}  🌐 Client binary download:                               ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}  ${GITHUB_RAW}/dnstt/dnstt-client-linux-\$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         🔒 MARCSCRIPT DNSTT INSTALLER                      ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${WHITE}         DNS Tunnel with DoH/DoT/UDP Support                ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Features:${NC}"
    echo -e "  • DNS Tunnel (DoH/DoT/UDP)"
    echo -e "  • No conflict with existing services"
    echo -e "  • Multi-architecture support"
    echo -e "  • Port 5300 (non-conflicting)"
    echo ""
    echo -e "${CYAN}Ports:${NC}"
    echo -e "  DNS Tunnel: 5300 (UDP)"
    echo -e "  SSH: $SSH_PORT, $DNSTT_ALT_SSH"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    detect_arch
    setup_iptables
    get_domain
    install_packages
    configure_ssh
    install_binaries
    generate_keys
    create_services
    start_services
    create_client_config
    display_summary
}

main "$@"