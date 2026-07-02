#!/bin/bash
# ============================================================
# MARCSCRIPT DNSTT INSTALLER
# DNS Tunnel with DoH/DoT/UDP Support
# Compatible with existing SSH/Xray/OpenVPN setup
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
DNSTT_DIR="/etc/dnstt"
DNSTT_LOG_DIR="/var/log/dnstt"

# Ports (non-conflicting)
DNSTT_UDP_PORT="5300"        # DNS tunnel server port
DNSTT_FALLBACK_PORT="8888"   # Fallback for non-DNS packets
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
        x86_64)  DNSTT_ARCH="amd64" ;;
        i386|i686) DNSTT_ARCH="386" ;;
        aarch64|arm64) DNSTT_ARCH="arm64" ;;
        armv7l)  DNSTT_ARCH="armv7" ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    print_info "Architecture: $ARCH → $DNSTT_ARCH"
    
    DNSTT_CLIENT_BIN="dnstt-client-linux-${DNSTT_ARCH}"
    DNSTT_SERVER_BIN="dnstt-server-linux-${DNSTT_ARCH}"
}

# ============================================================
# CHECK REQUIREMENTS
# ============================================================
check_requirements() {
    print_step "Checking requirements..."
    
    # Check if already installed
    if [ -f /etc/systemd/system/dnstt-server.service ]; then
        print_warn "DNSTT appears to be already installed!"
        read -p "Reinstall? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
        systemctl stop dnstt-server dnstt-client 2>/dev/null || true
    fi
    
    # Check SSH port
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        print_warn "SSH port $SSH_PORT not found in config"
        print_info "Adding SSH port $SSH_PORT..."
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    # Check port conflicts
    for port in $DNSTT_UDP_PORT $DNSTT_FALLBACK_PORT; do
        if ss -tuln | grep -q ":$port "; then
            print_warn "Port $port is in use!"
        fi
    done
    
    print_success "Requirements check passed"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Configuring DNS Tunnel domain..."
    
    if [ -f /root/domain ]; then
        DOMAIN=$(cat /root/domain)
        print_info "Using existing domain: $DOMAIN"
    elif [ -f /root/nsdomain ]; then
        DOMAIN=$(cat /root/nsdomain)
        print_info "Using existing NS domain: $DOMAIN"
    else
        read -rp "Enter main domain: " DOMAIN
    fi
    
    read -rp "Enter subdomain prefix [dnstt]: " sub
    sub=${sub:-dnstt}
    NS_DOMAIN="${sub}.${DOMAIN}"
    echo "$NS_DOMAIN" > /root/nsdomain
    
    print_info "NS Domain: ${CYAN}$NS_DOMAIN${NC}"
}

# ============================================================
# INSTALL DNSTT BINARIES
# ============================================================
install_binaries() {
    print_step "Installing DNSTT binaries..."
    
    # Create directories
    mkdir -p "$DNSTT_DIR" "$DNSTT_LOG_DIR"
    
    # Download client binary
    print_info "Downloading DNSTT client ($DNSTT_ARCH)..."
    CLIENT_URL="$GITHUB_RAW/dnstt/$DNSTT_CLIENT_BIN"
    wget -q -O "$DNSTT_DIR/dnstt-client" "$CLIENT_URL" 2>/dev/null || {
        print_error "Failed to download DNSTT client!"
        print_error "URL: $CLIENT_URL"
        exit 1
    }
    
    # Download server binary
    print_info "Downloading DNSTT server ($DNSTT_ARCH)..."
    SERVER_URL="$GITHUB_RAW/dnstt/$DNSTT_SERVER_BIN"
    wget -q -O "$DNSTT_DIR/dnstt-server" "$SERVER_URL" 2>/dev/null || {
        print_error "Failed to download DNSTT server!"
        print_error "URL: $SERVER_URL"
        exit 1
    }
    
    # Make executable
    chmod +x "$DNSTT_DIR/dnstt-client" "$DNSTT_DIR/dnstt-server"
    
    # Verify binaries
    if "$DNSTT_DIR/dnstt-client" 2>&1 | grep -q "Usage"; then
        print_success "DNSTT client binary verified"
    else
        print_error "DNSTT client binary verification failed!"
    fi
    
    if "$DNSTT_DIR/dnstt-server" 2>&1 | grep -q "Usage"; then
        print_success "DNSTT server binary verified"
    else
        print_error "DNSTT server binary verification failed!"
    fi
}

# ============================================================
# GENERATE KEYS
# ============================================================
generate_keys() {
    print_step "Generating DNSTT keypair..."
    
    cd "$DNSTT_DIR"
    
    # Check if keys already exist
    if [ -f "$DNSTT_DIR/server.key" ] && [ -f "$DNSTT_DIR/server.pub" ]; then
        print_info "Keys already exist"
        read -p "Regenerate? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Generate keys
    ./dnstt-server -gen-key -privkey-file "$DNSTT_DIR/server.key" -pubkey-file "$DNSTT_DIR/server.pub" 2>/dev/null
    
    if [ -f "$DNSTT_DIR/server.key" ] && [ -f "$DNSTT_DIR/server.pub" ]; then
        chmod 600 "$DNSTT_DIR/server.key"
        chmod 644 "$DNSTT_DIR/server.pub"
        
        # Display public key
        PUBKEY=$(cat "$DNSTT_DIR/server.pub")
        print_success "Keypair generated"
        print_info "Public Key: ${YELLOW}${PUBKEY}${NC}"
    else
        print_error "Key generation failed!"
        exit 1
    fi
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
# CREATE SYSTEMD SERVICES
# ============================================================
create_services() {
    print_step "Creating systemd services..."
    
    # DNSTT Server Service
    cat > /etc/systemd/system/dnstt-server.service <<EOF
[Unit]
Description=MarcScript DNSTT Server (DNS Tunnel)
Documentation=https://github.com/Jhon-mark23/vpn
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$DNSTT_DIR/dnstt-server -udp :$DNSTT_UDP_PORT -privkey-file $DNSTT_DIR/server.key $NS_DOMAIN 127.0.0.1:$SSH_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # DNSTT Client Service (for reference, usually runs on client device)
    cat > /etc/systemd/system/dnstt-client.service <<EOF
[Unit]
Description=MarcScript DNSTT Client (DNS Tunnel)
Documentation=https://github.com/Jhon-mark23/vpn
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$DNSTT_DIR/dnstt-client -udp $PUBLIC_DNS -pubkey-file $DNSTT_DIR/server.pub $NS_DOMAIN 127.0.0.1:$DNSTT_ALT_SSH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod +x /etc/systemd/system/dnstt-server.service
    chmod +x /etc/systemd/system/dnstt-client.service
    
    print_success "Systemd services created"
}

# ============================================================
# CONFIGURE FIREWALL
# ============================================================
configure_firewall() {
    print_step "Configuring firewall..."
    
    # Allow DNSTT ports
    iptables -I INPUT -p udp --dport $DNSTT_UDP_PORT -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport $SSH_PORT -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport $DNSTT_ALT_SSH -j ACCEPT 2>/dev/null || true
    
    # Allow fallback port
    iptables -I INPUT -p udp --dport $DNSTT_FALLBACK_PORT -j ACCEPT 2>/dev/null || true
    
    # Save rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    netfilter-persistent save 2>/dev/null || true
    
    print_success "Firewall configured"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting DNSTT services..."
    
    systemctl daemon-reload
    
    # Stop existing if running
    systemctl stop dnstt-server dnstt-client 2>/dev/null || true
    
    # Enable and start server
    systemctl enable dnstt-server 2>/dev/null
    systemctl start dnstt-server 2>/dev/null
    
    # Enable and start client (optional, for local testing)
    systemctl enable dnstt-client 2>/dev/null
    systemctl start dnstt-client 2>/dev/null
    
    sleep 3
    
    # Verify
    if systemctl is-active --quiet dnstt-server; then
        print_success "DNSTT Server running on UDP port $DNSTT_UDP_PORT"
    else
        print_error "DNSTT Server failed!"
        journalctl -u dnstt-server --no-pager -n 10
    fi
    
    if systemctl is-active --quiet dnstt-client; then
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
    PUBKEY=$(cat "$DNSTT_DIR/server.pub")
    
    # Client config file
    cat > "$DNSTT_DIR/client-config.txt" <<EOF
====================================
MarcScript DNSTT Client Config
====================================
Server IP    : $SERVER_IP
NS Domain    : $NS_DOMAIN
DNS Port     : $DNSTT_UDP_PORT
SSH Port     : $SSH_PORT
Public Key   : $PUBKEY

====================================
CLIENT COMMAND EXAMPLES:
====================================

# UDP Mode (recommended for server)
dnstt-client -udp $SERVER_IP:$DNSTT_UDP_PORT -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

# Using public DNS resolver
dnstt-client -udp $PUBLIC_DNS -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

# DoH Mode (DNS over HTTPS)
dnstt-client -doh https://dns.google/dns-query -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

# DoT Mode (DNS over TLS)
dnstt-client -dot dns.google:853 -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

# With uTLS fingerprint (bypass DPI)
dnstt-client -udp $PUBLIC_DNS -utls "3*Chrome_120,2*Firefox_120,1*iOS_14" -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

====================================
SOCKS PROXY SETUP:
====================================
# Run DNSTT client locally
./dnstt-client -udp $PUBLIC_DNS -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000

# Connect SSH through tunnel
ssh -p $SSH_PORT -o ProxyCommand="nc -X 5 -x 127.0.0.1:7000 %h %p" user@$SERVER_IP

====================================
EOF

    print_success "Client config saved to $DNSTT_DIR/client-config.txt"
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================
display_summary() {
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    PUBKEY=$(cat "$DNSTT_DIR/server.pub")
    
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         ✅ MARCSCRIPT DNSTT INSTALLED SUCCESSFULLY         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📡 SERVER INFORMATION:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server IP" "$SERVER_IP"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "NS Domain" "$NS_DOMAIN"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "DNS Port" "$DNSTT_UDP_PORT (UDP)"
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
    echo -e "  ${YELLOW}dnstt-client -udp $SERVER_IP:$DNSTT_UDP_PORT -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    echo -e "  ${WHITE}DoH Mode:${NC}"
    echo -e "  ${YELLOW}dnstt-client -doh https://dns.google/dns-query -pubkey $PUBKEY $NS_DOMAIN 127.0.0.1:7000${NC}"
    echo ""
    
    echo -e "${CYAN}⚙️  SERVICE CONTROL:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Server Status:${NC} systemctl status dnstt-server"
    echo -e "  ${WHITE}Server Logs:${NC}  journalctl -u dnstt-server -f"
    echo -e "  ${WHITE}Restart:${NC}      systemctl restart dnstt-server"
    echo ""
    
    echo -e "${CYAN}📁 FILES:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Binaries:${NC}    $DNSTT_DIR/"
    echo -e "  ${WHITE}Keys:${NC}        $DNSTT_DIR/server.key | server.pub"
    echo -e "  ${WHITE}Config:${NC}      $DNSTT_DIR/client-config.txt"
    echo -e "  ${WHITE}NS Domain:${NC}   /root/nsdomain"
    echo ""
    
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${CYAN}  🌐 Client binary download:                               ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}  ${GITHUB_RAW}/dnstt/${DNSTT_CLIENT_BIN}${NC}"
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
    echo -e "  • uTLS fingerprint support"
    echo -e "  • No conflict with existing services"
    echo -e "  • Multi-architecture support"
    echo ""
    echo -e "${CYAN}Ports:${NC}"
    echo -e "  DNS Tunnel: $DNSTT_UDP_PORT (UDP)"
    echo -e "  SSH: $SSH_PORT, $DNSTT_ALT_SSH"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    detect_arch
    check_requirements
    get_domain
    install_binaries
    generate_keys
    configure_ssh
    create_services
    configure_firewall
    start_services
    create_client_config
    display_summary
}

main "$@"