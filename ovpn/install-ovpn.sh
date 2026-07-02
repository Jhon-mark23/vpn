#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN INSTALLER (OpenVPN3 Binary)
# No conflict with SSH (22,80,443,etc) & Xray (443,80)
# Uses pre-compiled OpenVPN3 binary from GitHub
# Ports: TCP 1194, UDP 2200
# ============================================================

set -e

# Colors (matching your existing style)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
OVPN_DIR="/etc/openvpn"
OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
OVPN_LOG_DIR="/var/log/openvpn"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CERT_DIR="/etc/ssl/vpn"
USER_DB="$OVPN_CLIENT_DIR/users.db"

# Non-conflicting ports
OVPN_TCP_PORT="1194"
OVPN_UDP_PORT="2200"
OVPN_MGMT_PORT="7505"

# Network subnets
OVPN_NET_TCP="10.30.0"
OVPN_NET_UDP="10.40.0"
OVPN_NETMASK="255.255.255.0"

SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# ============================================================
# CHECK REQUIREMENTS
# ============================================================
check_requirements() {
    print_step "Checking requirements..."
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
    
    # Check if already installed
    if [ -f /etc/openvpn/server-tcp.conf ] && systemctl is-active --quiet openvpn@server-tcp 2>/dev/null; then
        print_warn "OpenVPN appears to be already installed and running!"
        read -p "Reinstall? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
        print_info "Stopping existing OpenVPN services..."
        systemctl stop openvpn@server-tcp openvpn@server-udp 2>/dev/null || true
    fi
    
    # Check port conflicts
    print_info "Checking port availability..."
    for port in $OVPN_TCP_PORT $OVPN_UDP_PORT; do
        if ss -tuln | grep -q ":$port "; then
            print_warn "Port $port is in use!"
            ss -tulnp | grep ":$port "
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done
    
    print_success "Requirements check passed"
}

# ============================================================
# INSTALL OPENVPN3 BINARY FROM GITHUB
# ============================================================
install_openvpn3_binary() {
    print_step "Installing OpenVPN3 binary from GitHub..."
    
    # Create directories
    mkdir -p /usr/local/bin
    
    # Check if binary already exists
    if [ -f /usr/local/bin/ovpncli ] && [ -x /usr/local/bin/ovpncli ]; then
        print_info "OpenVPN3 binary already exists at /usr/local/bin/ovpncli"
        read -p "Re-download? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping binary download"
            return 0
        fi
    fi
    
    # Download OpenVPN3 binary
    print_info "Downloading OpenVPN3 binary (ovpncli)..."
    wget -q -O /usr/local/bin/ovpncli "$GITHUB_RAW/ovpn/binaries/ovpncli" 2>/dev/null || {
        # Try stripped version if full binary not available
        print_warn "Full binary not found, trying stripped version..."
        wget -q -O /usr/local/bin/ovpncli "$GITHUB_RAW/ovpn/binaries/ovpnclis" 2>/dev/null || {
            # Try DEB package
            print_warn "Binary not found, trying DEB package..."
            wget -q -O /tmp/openvpn3.deb "$GITHUB_RAW/ovpn/binaries/openvpn3_1.0_amd64.deb" 2>/dev/null && {
                print_info "Installing from DEB package..."
                dpkg -i /tmp/openvpn3.deb 2>/dev/null || apt install -y /tmp/openvpn3.deb 2>/dev/null
                rm -f /tmp/openvpn3.deb
            } || {
                print_error "Failed to download OpenVPN3 binary!"
                print_error "URL: $GITHUB_RAW/ovpn/binaries/ovpncli"
                print_error "Please check your GitHub repository"
                exit 1
            }
        }
    }
    
    # Make executable
    chmod 755 /usr/local/bin/ovpncli 2>/dev/null
    
    # Create symlinks
    ln -sf /usr/local/bin/ovpncli /usr/bin/ovpncli 2>/dev/null || true
    ln -sf /usr/local/bin/ovpncli /usr/local/bin/openvpn3 2>/dev/null || true
    
    # Verify binary works
    if [ -x /usr/local/bin/ovpncli ]; then
        print_info "Testing OpenVPN3 binary..."
        if /usr/local/bin/ovpncli --version 2>/dev/null || /usr/local/bin/ovpncli -h 2>/dev/null | head -1 | grep -q "OpenVPN"; then
            print_success "OpenVPN3 binary installed and working!"
        else
            print_warn "Binary installed but version check failed (may still work)"
        fi
    else
        print_error "Binary installation failed!"
        exit 1
    fi
    
    # Install runtime dependencies if needed
    print_info "Checking runtime dependencies..."
    MISSING_LIBS=$(ldd /usr/local/bin/ovpncli 2>/dev/null | grep "not found" | wc -l)
    if [ $MISSING_LIBS -gt 0 ]; then
        print_warn "Missing $MISSING_LIBS libraries. Installing dependencies..."
        apt update -y
        apt install -y libssl3 liblz4-1 libxxhash0 libfmt9 libjsoncpp25 2>/dev/null || \
        apt install -y libssl-dev liblz4-dev libxxhash-dev libfmt-dev libjsoncpp-dev 2>/dev/null || true
    fi
}

# ============================================================
# INSTALL OPENVPN SERVER PACKAGES
# ============================================================
install_packages() {
    print_step "Installing OpenVPN server packages..."
    
    apt update -y
    
    # Install OpenVPN server and tools
    apt install -y --no-install-recommends \
        openvpn \
        easy-rsa \
        iptables-persistent \
        netfilter-persistent \
        wget \
        curl \
        openssl
    
    print_success "Server packages installed"
}

# ============================================================
# SETUP EASY-RSA
# ============================================================
setup_easyrsa() {
    print_step "Setting up Easy-RSA Certificate Authority..."
    
    # Backup old if exists
    if [ -d "$EASYRSA_DIR" ]; then
        mv "$EASYRSA_DIR" "${EASYRSA_DIR}.backup.$(date +%s)" 2>/dev/null
    fi
    
    make-cadir "$EASYRSA_DIR"
    cd "$EASYRSA_DIR"
    
    # Configure Easy-RSA
    cat > vars <<EOF
set_var EASYRSA_REQ_COUNTRY    "PH"
set_var EASYRSA_REQ_PROVINCE   "Metro Manila"
set_var EASYRSA_REQ_CITY       "Manila"
set_var EASYRSA_REQ_ORG        "MarcScript"
set_var EASYRSA_REQ_EMAIL      "admin@marcscript.com"
set_var EASYRSA_REQ_OU         "OpenVPN"
set_var EASYRSA_KEY_SIZE       2048
set_var EASYRSA_ALGO           rsa
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    365
EOF

    print_info "Building PKI infrastructure..."
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass
    
    print_info "Generating server certificate..."
    ./easyrsa --batch gen-req server nopass
    ./easyrsa --batch sign-req server server
    
    print_info "Generating DH parameters (may take time)..."
    ./easyrsa --batch gen-dh
    
    print_info "Generating TLS auth key..."
    openvpn --genkey --secret "$EASYRSA_DIR/pki/ta.key"
    
    ./easyrsa gen-crl
    
    # Copy to OpenVPN directory
    cp "$EASYRSA_DIR/pki/ca.crt" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/issued/server.crt" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/private/server.key" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/dh.pem" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/ta.key" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/crl.pem" "$OVPN_DIR/"
    
    chmod 600 "$OVPN_DIR/server.key" "$OVPN_DIR/ta.key"
    
    print_success "Easy-RSA configured"
}

# ============================================================
# CREATE SERVER CONFIGS
# ============================================================
create_server_configs() {
    print_step "Creating server configurations..."
    
    mkdir -p "$OVPN_LOG_DIR" "$OVPN_CLIENT_DIR"
    
    # TCP Server Config
    cat > "$OVPN_DIR/server-tcp.conf" <<EOF
# ============================================
# MarcScript OpenVPN TCP Server
# Port: $OVPN_TCP_PORT
# Network: ${OVPN_NET_TCP}.0/24
# Binary: OpenVPN3
# ============================================

port $OVPN_TCP_PORT
proto tcp
dev tun

ca $OVPN_DIR/ca.crt
cert $OVPN_DIR/server.crt
key $OVPN_DIR/server.key
dh $OVPN_DIR/dh.pem
tls-auth $OVPN_DIR/ta.key 0
crl-verify $OVPN_DIR/crl.pem

topology subnet
server ${OVPN_NET_TCP}.0 $OVPN_NETMASK
ifconfig-pool-persist $OVPN_DIR/ipp-tcp.txt

push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "dhcp-option DNS 1.1.1.1"
push "redirect-gateway def1 bypass-dhcp"

keepalive 10 120
cipher AES-256-GCM
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
compress lz4-v2
push "compress lz4-v2"

max-clients 50
user nobody
group nogroup
persist-key
persist-tun

status $OVPN_LOG_DIR/openvpn-tcp-status.log
log-append $OVPN_LOG_DIR/openvpn-tcp.log
verb 3
explicit-exit-notify 1

management 127.0.0.1 $OVPN_MGMT_PORT
EOF

    # UDP Server Config
    cat > "$OVPN_DIR/server-udp.conf" <<EOF
# ============================================
# MarcScript OpenVPN UDP Server
# Port: $OVPN_UDP_PORT
# Network: ${OVPN_NET_UDP}.0/24
# Binary: OpenVPN3
# ============================================

port $OVPN_UDP_PORT
proto udp
dev tun

ca $OVPN_DIR/ca.crt
cert $OVPN_DIR/server.crt
key $OVPN_DIR/server.key
dh $OVPN_DIR/dh.pem
tls-auth $OVPN_DIR/ta.key 0
crl-verify $OVPN_DIR/crl.pem

topology subnet
server ${OVPN_NET_UDP}.0 $OVPN_NETMASK
ifconfig-pool-persist $OVPN_DIR/ipp-udp.txt

push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "dhcp-option DNS 1.1.1.1"
push "redirect-gateway def1 bypass-dhcp"

keepalive 10 120
cipher AES-256-GCM
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
compress lz4-v2
push "compress lz4-v2"

max-clients 50
user nobody
group nogroup
persist-key
persist-tun

status $OVPN_LOG_DIR/openvpn-udp-status.log
log-append $OVPN_LOG_DIR/openvpn-udp.log
verb 3
explicit-exit-notify 1

management 127.0.0.1 $((OVPN_MGMT_PORT + 1))
EOF

    print_success "Server configs created"
}

# ============================================================
# CONFIGURE FIREWALL & SYSTEM
# ============================================================
configure_system() {
    print_step "Configuring system and firewall..."
    
    # Enable IP forwarding
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo '# OpenVPN IP Forwarding' >> /etc/sysctl.conf
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    
    # Get network interface
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    [ -z "$NIC" ] && NIC=$(ip -4 addr show | grep -v "127.0.0.1" | grep "inet " | head -1 | awk '{print $NF}')
    
    print_info "Network interface: $NIC"
    
    # iptables rules
    iptables -A INPUT -p tcp --dport $OVPN_TCP_PORT -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p udp --dport $OVPN_UDP_PORT -j ACCEPT 2>/dev/null || true
    
    iptables -t nat -A POSTROUTING -s ${OVPN_NET_TCP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s ${OVPN_NET_UDP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
    
    iptables -A FORWARD -s ${OVPN_NET_TCP}.0/24 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -s ${OVPN_NET_UDP}.0/24 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    # Save rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    netfilter-persistent save 2>/dev/null || true
    
    print_success "System configured"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting OpenVPN services..."
    
    systemctl daemon-reload
    systemctl enable openvpn@server-tcp openvpn@server-udp 2>/dev/null
    systemctl start openvpn@server-tcp openvpn@server-udp 2>/dev/null
    
    sleep 3
    
    if systemctl is-active --quiet openvpn@server-tcp; then
        print_success "OpenVPN TCP running on port $OVPN_TCP_PORT"
    else
        print_error "OpenVPN TCP failed!"
        journalctl -u openvpn@server-tcp --no-pager -n 5
    fi
    
    if systemctl is-active --quiet openvpn@server-udp; then
        print_success "OpenVPN UDP running on port $OVPN_UDP_PORT"
    else
        print_error "OpenVPN UDP failed!"
        journalctl -u openvpn@server-udp --no-pager -n 5
    fi
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_step "Downloading management scripts..."
    
    mkdir -p /root/ovpn
    
    SCRIPTS="create-user.sh renew-user.sh delete-user.sh list-user.sh menu-ovpn.sh check-expired.sh"
    
    for script in $SCRIPTS; do
        print_info "Downloading $script..."
        wget -q -O "/root/ovpn/$script" "$GITHUB_RAW/ovpn/$script" 2>/dev/null || {
            print_warn "Could not download $script"
        }
        chmod +x "/root/ovpn/$script" 2>/dev/null
    done
    
    # Create user database
    touch "$USER_DB"
    
    print_success "Scripts downloaded"
}

# ============================================================
# SETUP CRON
# ============================================================
setup_cron() {
    print_step "Setting up auto-expiration..."
    
    if ! crontab -l 2>/dev/null | grep -q "check-expired.sh"; then
        (crontab -l 2>/dev/null; echo "0 * * * * /root/ovpn/check-expired.sh >/dev/null 2>&1") | crontab -
        print_success "Hourly expiration check enabled"
    fi
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================
display_summary() {
    clear
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${BLUE}   ✅ OPENVPN INSTALLED WITH OPENVPN3!${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo -e "${GREEN}📡 SERVER:${NC}"
    echo "   IP        : $SERVER_IP"
    echo "   TCP Port  : $OVPN_TCP_PORT"
    echo "   UDP Port  : $OVPN_UDP_PORT"
    echo ""
    echo -e "${GREEN}🔧 OPENVPN3 BINARY:${NC}"
    echo "   Location  : /usr/local/bin/ovpncli"
    echo "   Symlink   : /usr/bin/ovpncli"
    echo "   Version   : $(/usr/local/bin/ovpncli --version 2>/dev/null | head -1 || echo 'OpenVPN3')"
    echo ""
    echo -e "${GREEN}📁 DIRECTORIES:${NC}"
    echo "   Server    : $OVPN_DIR"
    echo "   Clients   : $OVPN_CLIENT_DIR"
    echo "   Logs      : $OVPN_LOG_DIR"
    echo ""
    echo -e "${GREEN}👤 MANAGEMENT:${NC}"
    echo "   Create    : bash /root/ovpn/create-user.sh"
    echo "   Menu      : bash /root/ovpn/menu-ovpn.sh"
    echo "   List      : bash /root/ovpn/list-user.sh"
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${YELLOW}Quick Start:${NC}"
    echo "   bash /root/ovpn/create-user.sh"
    echo "   bash /root/ovpn/menu-ovpn.sh"
    echo ""
    echo -e "${GREEN}OpenVPN3 CLI Usage:${NC}"
    echo "   ovpncli client.ovpn"
    echo "   ovpncli --username user --password pass client.ovpn"
    echo -e "${CYAN}===========================================${NC}"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${BLUE}   🔐 MARCSCRIPT OPENVPN INSTALLER${NC}"
    echo -e "${BLUE}   Powered by OpenVPN3 Binary${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo -e "${GREEN}Features:${NC}"
    echo "  • OpenVPN3 pre-compiled binary"
    echo "  • No port conflicts (1194/2200)"
    echo "  • User management + expiration"
    echo "  • Auto-expiration check"
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    check_requirements
    install_openvpn3_binary
    install_packages
    setup_easyrsa
    create_server_configs
    configure_system
    start_services
    download_scripts
    setup_cron
    display_summary
}

main "$@"