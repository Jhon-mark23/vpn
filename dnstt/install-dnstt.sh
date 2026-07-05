#!/bin/bash
# ============================================================
# MARCSCRIPT DNSTT INSTALLER
# DNS Tunnel (SlowDNS) with UDP Support
# Compatible with Ubuntu & Debian
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
SSH_PORT="2221"              # Existing SSH port
DNSTT_ALT_SSH="2269"         # Alternative SSH port

# DNS Resolver
PUBLIC_DNS="8.8.8.8:53"

# Service names
SERVER_SERVICE="server-sldns"
CLIENT_SERVICE="client-sldns"

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
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# ============================================================
# CHECK AND REMOVE EXISTING SERVICES
# ============================================================
remove_existing_services() {
    print_step "Checking for existing DNSTT services..."
    
    # Check and remove server-sldns service
    if systemctl list-unit-files | grep -q "${SERVER_SERVICE}.service"; then
        print_warn "Found existing ${SERVER_SERVICE} service"
        print_info "Stopping ${SERVER_SERVICE}..."
        systemctl stop ${SERVER_SERVICE} 2>/dev/null || true
        print_info "Disabling ${SERVER_SERVICE}..."
        systemctl disable ${SERVER_SERVICE} 2>/dev/null || true
        print_info "Removing ${SERVER_SERVICE} service file..."
        rm -f /etc/systemd/system/${SERVER_SERVICE}.service
        print_success "${SERVER_SERVICE} removed"
    else
        print_info "No existing ${SERVER_SERVICE} found"
    fi
    
    # Check and remove client-sldns service
    if systemctl list-unit-files | grep -q "${CLIENT_SERVICE}.service"; then
        print_warn "Found existing ${CLIENT_SERVICE} service"
        print_info "Stopping ${CLIENT_SERVICE}..."
        systemctl stop ${CLIENT_SERVICE} 2>/dev/null || true
        print_info "Disabling ${CLIENT_SERVICE}..."
        systemctl disable ${CLIENT_SERVICE} 2>/dev/null || true
        print_info "Removing ${CLIENT_SERVICE} service file..."
        rm -f /etc/systemd/system/${CLIENT_SERVICE}.service
        print_success "${CLIENT_SERVICE} removed"
    else
        print_info "No existing ${CLIENT_SERVICE} found"
    fi
    
    # Kill any running processes
    print_info "Killing any running DNSTT processes..."
    pkill -f "sldns-server" 2>/dev/null || true
    pkill -f "sldns-client" 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload
    
    print_success "All existing DNSTT services removed"
}

# ============================================================
# BACKUP EXISTING CONFIGURATION
# ============================================================
backup_existing_config() {
    if [ -d "$SLOWDNS_DIR" ]; then
        print_step "Backing up existing configuration..."
        BACKUP_DIR="${SLOWDNS_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$SLOWDNS_DIR" "$BACKUP_DIR"
        print_info "Backup saved to: $BACKUP_DIR"
        print_success "Configuration backed up"
    fi
}

# ============================================================
# SETUP IPTABLES
# ============================================================
setup_iptables() {
    print_step "Setting up iptables rules..."
    
    # Install iptables if not present
    apt install -y iptables iptables-persistent netfilter-persistent 2>/dev/null || true
    
    # Remove existing rules if any
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Allow UDP port 5300
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    
    # Redirect DNS (port 53) to DNSTT port (5300)
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Save rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    print_success "Iptables configured"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Configuring DNS Tunnel domain..."
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "None")
    
    # If no domain found, prompt user
    if [[ "$DOMAIN" == "None" ]]; then
        read -rp "Enter main domain: " DOMAIN
    else
        print_info "Found domain: $DOMAIN"
        read -rp "Use this domain? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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
    
    print_info "NS Domain: ${CYAN}${NS_DOMAIN}${NC}"
}

# ============================================================
# INSTALL PACKAGES (Ubuntu/Debian Compatible)
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    # Update package list
    apt update -y
    
    # Install packages with correct names for Ubuntu/Debian
    apt install -y python3 python3-dnslib net-tools dnsutils \
                   git curl wget screen cron iptables dropbear \
                   sudo gnutls-bin dos2unix debconf-utils \
                   ca-certificates openssl
    
    # Try to install ncurses-utils (may not exist on some versions)
    apt install -y ncurses-utils 2>/dev/null || {
        print_warn "ncurses-utils not found, skipping (not critical)"
    }
    
    # Restart cron
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
    
    # Remove duplicate port entries
    sed -i '/^Port 2221/d' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i '/^Port 2269/d' /etc/ssh/sshd_config 2>/dev/null || true
    
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
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        print_success "SSH configured and running"
    else
        print_warn "SSH may not be running, check manually"
    fi
}

# ============================================================
# INSTALL DNSTT BINARIES
# ============================================================
install_binaries() {
    print_step "Installing DNSTT binaries..."
    
    # Remove old directory and create new
    rm -rf "$SLOWDNS_DIR"
    mkdir -m 755 "$SLOWDNS_DIR"
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
    
    # Generate fresh keys
    ./sldns-server -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub" 2>/dev/null
    
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
        chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
        
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
    cat > /etc/systemd/system/${SERVER_SERVICE}.service <<EOF
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Client Service (optional, for local testing)
    cat > /etc/systemd/system/${CLIENT_SERVICE}.service <<EOF
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod 644 /etc/systemd/system/${SERVER_SERVICE}.service
    chmod 644 /etc/systemd/system/${CLIENT_SERVICE}.service
    
    print_success "Systemd services created"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting DNSTT services..."
    
    # Kill any existing processes
    pkill -f "sldns-server" 2>/dev/null || true
    pkill -f "sldns-client" 2>/dev/null || true
    
    systemctl daemon-reload
    
    # Enable and start server
    systemctl enable ${SERVER_SERVICE} 2>/dev/null
    systemctl start ${SERVER_SERVICE} 2>/dev/null
    
    # Enable and start client (optional)
    systemctl enable ${CLIENT_SERVICE} 2>/dev/null
    systemctl start ${CLIENT_SERVICE} 2>/dev/null
    
    sleep 3
    
    # Verify server
    if systemctl is-active --quiet ${SERVER_SERVICE}; then
        print_success "DNSTT Server running on UDP port 5300"
        print_info "NS Domain: $NS_DOMAIN"
    else
        print_error "DNSTT Server failed!"
        journalctl -u ${SERVER_SERVICE} --no-pager -n 10 2>/dev/null || true
    fi
    
    # Verify client
    if systemctl is-active --quiet ${CLIENT_SERVICE}; then
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

Configuration generated on: $(date)
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
    
    echo -e "${CYAN}📁 SERVICE INFORMATION:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server Service" "$SERVER_SERVICE"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Client Service" "$CLIENT_SERVICE"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Config Dir" "$SLOWDNS_DIR"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Log Dir" "$SLOWDNS_LOG_DIR"
    echo ""
    
    echo -e "${CYAN}📋 COMMANDS:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Check status:${NC} systemctl status $SERVER_SERVICE"
    echo -e "  ${WHITE}Restart:${NC}      systemctl restart $SERVER_SERVICE"
    echo -e "  ${WHITE}View logs:${NC}    journalctl -u $SERVER_SERVICE -f"
    echo ""
    
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✨ Installation completed successfully!${NC}"
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
    echo -e "  • Auto-detects and removes existing services"
    echo -e "  • No conflict with existing services"
    echo -e "  • Multi-architecture support"
    echo -e "  • Port 5300 (non-conflicting)"
    echo ""
    echo -e "${CYAN}Ports:${NC}"
    echo -e "  DNS Tunnel: 5300 (UDP)"
    echo -e "  SSH: $SSH_PORT, $DNSTT_ALT_SSH"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    sleep 2
    
    # Remove existing services first
    remove_existing_services
    
    # Backup existing config if exists
    backup_existing_config
    
    # Main installation
    detect_os
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