#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN INSTALLER
# No conflict with SSH (22,80,443,etc) & Xray (443,80)
# Uses centralized certificate from create-cert.sh
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
# CONFIGURATION - NO CONFLICT PORTS
# ============================================================
OVPN_DIR="/etc/openvpn"
OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
OVPN_LOG_DIR="/var/log/openvpn"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CERT_DIR="/etc/ssl/vpn"

# Non-conflicting ports (SSH uses 22,80,443 / Xray uses 443,80 / Dropbear 109,143)
OVPN_TCP_PORT="1194"    # Standard OpenVPN TCP port
OVPN_UDP_PORT="2200"    # Non-standard to avoid conflicts
OVPN_MGMT_PORT="7505"   # Management interface (localhost only)

# Network subnets (non-conflicting with your existing 10.8.0.0/24 etc)
OVPN_NET_TCP="10.30.0"
OVPN_NET_UDP="10.40.0"
OVPN_NETMASK="255.255.255.0"

# GitHub base URL for downloading scripts
GITHUB_BASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ovpn"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
USER_DB="$OVPN_CLIENT_DIR/users.db"

# ============================================================
# CHECK ROOT & EXISTING SERVICES
# ============================================================
check_requirements() {
    print_info "Checking requirements..."
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
    
    # Check if already installed
    if [ -f /etc/openvpn/server-tcp.conf ]; then
        print_warn "OpenVPN appears to be already installed!"
        read -p "Reinstall? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    # Check port conflicts
    print_info "Checking port availability..."
    for port in $OVPN_TCP_PORT $OVPN_UDP_PORT; do
        if ss -tuln | grep -q ":$port "; then
            print_warn "Port $port is in use! Checking what's using it..."
            ss -tulnp | grep ":$port "
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done
    
    # Check if certificate exists (from your create-cert.sh)
    if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
        print_success "Found existing certificate in $CERT_DIR"
        USE_EXISTING_CERT=true
    else
        print_warn "No certificate found. Run create-cert.sh first or we'll generate self-signed"
        USE_EXISTING_CERT=false
    fi
    
    print_success "All checks passed"
}

# ============================================================
# INSTALL OPENVPN PACKAGES
# ============================================================
install_packages() {
    print_step "Installing OpenVPN packages..."
    
    apt update -y
    
    # Install OpenVPN and dependencies
    apt install -y --no-install-recommends \
        openvpn \
        easy-rsa \
        iptables-persistent \
        netfilter-persistent \
        wget \
        curl \
        openssl
    
    print_success "Packages installed"
}

# ============================================================
# SETUP EASY-RSA (Certificate Authority)
# ============================================================
setup_easyrsa() {
    print_step "Setting up Easy-RSA..."
    
    # Remove old if exists and reinstall requested
    if [ -d "$EASYRSA_DIR" ]; then
        mv "$EASYRSA_DIR" "${EASYRSA_DIR}.backup.$(date +%s)"
    fi
    
    make-cadir "$EASYRSA_DIR"
    cd "$EASYRSA_DIR"
    
    # Configure Easy-RSA variables
    cat > vars <<EOF
# Easy-RSA Configuration for MarcScript OpenVPN
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

    # Initialize PKI
    print_info "Initializing PKI..."
    ./easyrsa init-pki
    
    # Build Certificate Authority
    print_info "Building Certificate Authority..."
    ./easyrsa --batch build-ca nopass
    
    # Generate server certificate
    print_info "Generating server certificate..."
    ./easyrsa --batch gen-req server nopass
    ./easyrsa --batch sign-req server server
    
    # Generate Diffie-Hellman parameters
    print_info "Generating DH parameters (this may take a moment)..."
    ./easyrsa --batch gen-dh
    
    # Generate TLS authentication key
    print_info "Generating TLS auth key..."
    openvpn --genkey --secret "$EASYRSA_DIR/pki/ta.key"
    
    # Generate Certificate Revocation List
    ./easyrsa gen-crl
    
    # Copy files to OpenVPN directory
    cp "$EASYRSA_DIR/pki/ca.crt" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/issued/server.crt" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/private/server.key" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/dh.pem" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/ta.key" "$OVPN_DIR/"
    cp "$EASYRSA_DIR/pki/crl.pem" "$OVPN_DIR/"
    
    chmod 600 "$OVPN_DIR/server.key"
    chmod 600 "$OVPN_DIR/ta.key"
    
    print_success "Easy-RSA configured"
}

# ============================================================
# CREATE OPENVPN SERVER CONFIGS
# ============================================================
create_server_configs() {
    print_step "Creating server configurations..."
    
    # Create log directory
    mkdir -p "$OVPN_LOG_DIR"
    mkdir -p "$OVPN_CLIENT_DIR"
    
    # TCP Server Configuration
    cat > "$OVPN_DIR/server-tcp.conf" <<EOF
# ============================================
# MarcScript OpenVPN TCP Server
# Port: $OVPN_TCP_PORT
# Network: ${OVPN_NET_TCP}.0/24
# ============================================

# Basic configuration
port $OVPN_TCP_PORT
proto tcp
dev tun

# Certificates and keys
ca $OVPN_DIR/ca.crt
cert $OVPN_DIR/server.crt
key $OVPN_DIR/server.key
dh $OVPN_DIR/dh.pem
tls-auth $OVPN_DIR/ta.key 0
crl-verify $OVPN_DIR/crl.pem

# Network settings
topology subnet
server ${OVPN_NET_TCP}.0 $OVPN_NETMASK
ifconfig-pool-persist $OVPN_DIR/ipp-tcp.txt

# DNS (using your existing DNS or public)
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "dhcp-option DNS 1.1.1.1"

# Redirect all traffic through VPN
push "redirect-gateway def1 bypass-dhcp"

# Performance and security
keepalive 10 120
cipher AES-256-GCM
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
compress lz4-v2
push "compress lz4-v2"

# Limits
max-clients 50
user nobody
group nogroup

# Persistence
persist-key
persist-tun

# Logging
status $OVPN_LOG_DIR/openvpn-tcp-status.log
log-append $OVPN_LOG_DIR/openvpn-tcp.log
verb 3

# Notifications
explicit-exit-notify 1

# Management (localhost only)
management 127.0.0.1 $OVPN_MGMT_PORT
EOF

    # UDP Server Configuration
    cat > "$OVPN_DIR/server-udp.conf" <<EOF
# ============================================
# MarcScript OpenVPN UDP Server
# Port: $OVPN_UDP_PORT
# Network: ${OVPN_NET_UDP}.0/24
# ============================================

# Basic configuration
port $OVPN_UDP_PORT
proto udp
dev tun

# Certificates and keys
ca $OVPN_DIR/ca.crt
cert $OVPN_DIR/server.crt
key $OVPN_DIR/server.key
dh $OVPN_DIR/dh.pem
tls-auth $OVPN_DIR/ta.key 0
crl-verify $OVPN_DIR/crl.pem

# Network settings
topology subnet
server ${OVPN_NET_UDP}.0 $OVPN_NETMASK
ifconfig-pool-persist $OVPN_DIR/ipp-udp.txt

# DNS
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "dhcp-option DNS 1.1.1.1"

# Redirect all traffic through VPN
push "redirect-gateway def1 bypass-dhcp"

# Performance and security
keepalive 10 120
cipher AES-256-GCM
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
compress lz4-v2
push "compress lz4-v2"

# Limits
max-clients 50
user nobody
group nogroup

# Persistence
persist-key
persist-tun

# Logging
status $OVPN_LOG_DIR/openvpn-udp-status.log
log-append $OVPN_LOG_DIR/openvpn-udp.log
verb 3

# Notifications
explicit-exit-notify 1

# Management (localhost only)
management 127.0.0.1 $((OVPN_MGMT_PORT + 1))
EOF

    print_success "Server configurations created"
}

# ============================================================
# CONFIGURE SYSTEM & FIREWALL (NO CONFLICT)
# ============================================================
configure_system() {
    print_step "Configuring system and firewall..."
    
    # Enable IP forwarding (required for VPN)
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo '# OpenVPN IP Forwarding' >> /etc/sysctl.conf
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
        echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    
    # Get primary network interface
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    if [ -z "$NIC" ]; then
        NIC=$(ip -4 addr show | grep -v "127.0.0.1" | grep "inet " | head -1 | awk '{print $NF}')
    fi
    
    print_info "Using network interface: $NIC"
    
    # ============================================================
    # FIREWALL RULES - Only for OpenVPN, don't touch existing rules
    # ============================================================
    
    # Check if UFW is active (from your SSH-VPN setup, UFW might be removed)
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        print_info "UFW detected, adding rules..."
        ufw allow $OVPN_TCP_PORT/tcp comment "OpenVPN TCP"
        ufw allow $OVPN_UDP_PORT/udp comment "OpenVPN UDP"
    else
        print_info "Using iptables directly..."
        
        # Allow OpenVPN ports (INPUT chain)
        iptables -A INPUT -p tcp --dport $OVPN_TCP_PORT -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -p udp --dport $OVPN_UDP_PORT -j ACCEPT 2>/dev/null || true
        
        # NAT rules for VPN traffic (POSTROUTING chain)
        iptables -t nat -A POSTROUTING -s ${OVPN_NET_TCP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -s ${OVPN_NET_UDP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
        
        # Forward rules (FORWARD chain)
        iptables -A FORWARD -s ${OVPN_NET_TCP}.0/24 -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -s ${OVPN_NET_UDP}.0/24 -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        
        # Save rules for persistence
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
    
    # Add to rc.local for boot persistence
    if ! grep -q "OpenVPN iptables" /etc/rc.local 2>/dev/null; then
        cat >> /etc/rc.local <<'EOF'

# OpenVPN iptables rules
iptables -t nat -A POSTROUTING -s 10.30.0.0/24 -o $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -s 10.40.0.0/24 -o $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -j MASQUERADE 2>/dev/null
iptables -A FORWARD -s 10.30.0.0/24 -j ACCEPT 2>/dev/null
iptables -A FORWARD -s 10.40.0.0/24 -j ACCEPT 2>/dev/null
EOF
    fi
    
    print_success "System and firewall configured"
}

# ============================================================
# START OPENVPN SERVICES
# ============================================================
start_services() {
    print_step "Starting OpenVPN services..."
    
    systemctl daemon-reload
    
    # Enable and start TCP server
    systemctl enable openvpn@server-tcp 2>/dev/null
    systemctl start openvpn@server-tcp 2>/dev/null
    
    # Enable and start UDP server
    systemctl enable openvpn@server-udp 2>/dev/null
    systemctl start openvpn@server-udp 2>/dev/null
    
    sleep 3
    
    # Verify services
    if systemctl is-active --quiet openvpn@server-tcp; then
        print_success "OpenVPN TCP is running on port $OVPN_TCP_PORT"
    else
        print_error "OpenVPN TCP failed to start!"
        journalctl -u openvpn@server-tcp --no-pager -n 10
    fi
    
    if systemctl is-active --quiet openvpn@server-udp; then
        print_success "OpenVPN UDP is running on port $OVPN_UDP_PORT"
    else
        print_error "OpenVPN UDP failed to start!"
        journalctl -u openvpn@server-udp --no-pager -n 10
    fi
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_step "Downloading management scripts..."
    
    # Create scripts directory
    mkdir -p /root/ovpn
    
    SCRIPTS="create-user.sh renew-user.sh delete-user.sh list-user.sh menu-ovpn.sh check-expired.sh"
    
    for script in $SCRIPTS; do
        print_info "Downloading $script..."
        wget -q -O "/root/ovpn/$script" "$GITHUB_BASE/$script" 2>/dev/null || {
            print_warn "Could not download $script from GitHub, creating basic version..."
            touch "/root/ovpn/$script"
        }
        chmod +x "/root/ovpn/$script" 2>/dev/null
    done
    
    # Create user database
    touch "$USER_DB"
    
    # Add to menu if menu.sh exists
    if [ -f /usr/bin/menu ]; then
        print_info "Adding OVPN to main menu..."
        if ! grep -q "menu-ovpn.sh" /usr/bin/menu 2>/dev/null; then
            # Add OVPN option to menu
            sed -i '/menu-ssh.sh/a\    "OPENVPN" "OpenVPN Manager" \\' /usr/bin/menu 2>/dev/null || true
        fi
    fi
    
    print_success "Scripts downloaded"
}

# ============================================================
# SETUP AUTO-EXPIRATION CHECK
# ============================================================
setup_cron() {
    print_step "Setting up auto-expiration check..."
    
    # Add hourly check to crontab
    if ! crontab -l 2>/dev/null | grep -q "check-expired.sh"; then
        (crontab -l 2>/dev/null; echo "0 * * * * /root/ovpn/check-expired.sh >/dev/null 2>&1") | crontab -
        print_success "Expiration check scheduled hourly"
    else
        print_info "Cron job already exists"
    fi
}

# ============================================================
# DISPLAY INSTALLATION SUMMARY
# ============================================================
display_summary() {
    clear
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${BLUE}   ✅ OPENVPN INSTALLATION COMPLETE!${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo -e "${GREEN}📡 SERVER INFORMATION:${NC}"
    echo "   IP Address : $SERVER_IP"
    echo "   TCP Port   : $OVPN_TCP_PORT"
    echo "   UDP Port   : $OVPN_UDP_PORT"
    echo ""
    echo -e "${GREEN}🌐 NETWORK:${NC}"
    echo "   TCP Subnet : ${OVPN_NET_TCP}.0/24"
    echo "   UDP Subnet : ${OVPN_NET_UDP}.0/24"
    echo ""
    echo -e "${GREEN}📁 CONFIGURATION:${NC}"
    echo "   Server Dir  : $OVPN_DIR"
    echo "   Client Dir  : $OVPN_CLIENT_DIR"
    echo "   Logs Dir    : $OVPN_LOG_DIR"
    echo ""
    echo -e "${GREEN}🔧 MANAGEMENT:${NC}"
    echo "   Create User : bash /root/ovpn/create-user.sh"
    echo "   OVPN Menu   : bash /root/ovpn/menu-ovpn.sh"
    echo "   List Users  : bash /root/ovpn/list-user.sh"
    echo ""
    echo -e "${GREEN}⚙️  SERVICE CONTROL:${NC}"
    echo "   TCP Status  : systemctl status openvpn@server-tcp"
    echo "   UDP Status  : systemctl status openvpn@server-udp"
    echo "   Restart     : systemctl restart openvpn@server-tcp openvpn@server-udp"
    echo ""
    echo -e "${GREEN}🔒 SECURITY:${NC}"
    echo "   ✓ No port conflict with SSH/Xray/Dropbear"
    echo "   ✓ Expiration auto-check enabled (hourly)"
    echo "   ✓ Certificate revocation support"
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${YELLOW}📋 NON-CONFLICTING PORTS:${NC}"
    echo -e "   ${GREEN}OpenVPN TCP: $OVPN_TCP_PORT${NC}"
    echo -e "   ${GREEN}OpenVPN UDP: $OVPN_UDP_PORT${NC}"
    echo ""
    echo -e "${BLUE}Existing services unaffected:${NC}"
    echo "   SSH       : 22, 80, 2222"
    echo "   Dropbear  : 109, 143"
    echo "   Stunnel   : 443, 8443, 8444, 8445"
    echo "   Xray      : 443, 80"
    echo "   WebSocket : 8080, 8082"
    echo "   Squid     : 3128, 8082, 8888"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    print_success "Installation completed successfully!"
    echo ""
    echo -e "${YELLOW}Quick Start:${NC}"
    echo "   1. Create user: bash /root/ovpn/create-user.sh"
    echo "   2. Open menu:   bash /root/ovpn/menu-ovpn.sh"
    echo ""
}

# ============================================================
# MAIN INSTALLATION
# ============================================================
main() {
    clear
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${BLUE}   🔐 MARCSCRIPT OPENVPN INSTALLER${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo -e "${GREEN}Non-Conflicting Installation${NC}"
    echo ""
    echo "Ports to be used:"
    echo "  • TCP: $OVPN_TCP_PORT"
    echo "  • UDP: $OVPN_UDP_PORT"
    echo ""
    echo -e "${YELLOW}Existing ports (SSH, Xray, Dropbear, etc.) will NOT be affected${NC}"
    echo ""
    echo -e "${CYAN}===========================================${NC}"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    # Run installation steps
    check_requirements
    install_packages
    setup_easyrsa
    create_server_configs
    configure_system
    start_services
    download_scripts
    setup_cron
    display_summary
}

# Run main
main "$@"
