#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN INSTALLER WITH STUNNEL TLS SUPPORT
# Uses existing Stunnel certificate from create-cert.sh
# Ports: TCP 1194, UDP 2200, TLS 4443, TLS-Alt 4444
# ============================================================

set -e

# Colors (matching your existing style)
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
OVPN_DIR="/etc/openvpn"
OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
OVPN_LOG_DIR="/var/log/openvpn"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CERT_DIR="/etc/ssl/vpn"
STUNNEL_DIR="/etc/stunnel"
USER_DB="$OVPN_CLIENT_DIR/users.db"

# Non-conflicting ports
OVPN_TCP_PORT="1194"
OVPN_UDP_PORT="2200"
OVPN_TLS_PORT="4443"       # Stunnel wrapped TCP
OVPN_TLS_ALT_PORT="4444"   # Stunnel wrapped alternate
OVPN_MGMT_PORT="7505"

# Internal ports (localhost only)
OVPN_TLS_INTERNAL="11940"   # Internal port for TLS-wrapped OpenVPN

# Network subnets
OVPN_NET_TCP="10.30.0"
OVPN_NET_UDP="10.40.0"
OVPN_NET_TLS="10.50.0"
OVPN_NETMASK="255.255.255.0"

SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
NGINX_PORT="81"
WEB_DIR="/home/vps/public_html/ovpn"

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
        systemctl stop openvpn@server-tcp openvpn@server-udp openvpn@server-tls 2>/dev/null || true
    fi
    
    # Check port conflicts
    print_info "Checking port availability..."
    PORTS_TO_CHECK="$OVPN_TCP_PORT $OVPN_UDP_PORT $OVPN_TLS_PORT $OVPN_TLS_ALT_PORT"
    for port in $PORTS_TO_CHECK; do
        if ss -tuln | grep -q ":$port "; then
            print_warn "Port $port is in use!"
            ss -tulnp | grep ":$port "
        fi
    done
    
    # Check if Stunnel certificate exists
    if [ -f "$STUNNEL_DIR/stunnel.pem" ]; then
        print_success "Existing Stunnel certificate found: $STUNNEL_DIR/stunnel.pem"
        STUNNEL_CERT_EXISTS=true
    elif [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
        print_info "Creating Stunnel PEM from VPN certificates..."
        mkdir -p "$STUNNEL_DIR"
        cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" > "$STUNNEL_DIR/stunnel.pem"
        chmod 600 "$STUNNEL_DIR/stunnel.pem"
        print_success "Stunnel PEM created from existing certificates"
        STUNNEL_CERT_EXISTS=true
    else
        print_warn "No SSL certificate found!"
        print_info "You can:"
        echo "  1. Run create-cert.sh first"
        echo "  2. Place certificate at $STUNNEL_DIR/stunnel.pem"
        echo "  3. Continue with self-signed certificate"
        read -p "Generate self-signed certificate? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$CERT_DIR" "$STUNNEL_DIR"
            DOMAIN=${DOMAIN:-$(hostname)}
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout "$CERT_DIR/privkey.pem" \
                -out "$CERT_DIR/fullchain.pem" \
                -subj "/C=PH/ST=Manila/L=Manila/O=MarcScript/CN=$DOMAIN" 2>/dev/null
            cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" > "$STUNNEL_DIR/stunnel.pem"
            chmod 600 "$STUNNEL_DIR/stunnel.pem" "$CERT_DIR/privkey.pem"
            chmod 644 "$CERT_DIR/fullchain.pem"
            print_success "Self-signed certificate generated"
            STUNNEL_CERT_EXISTS=true
        else
            print_warn "TLS support will be disabled"
            STUNNEL_CERT_EXISTS=false
        fi
    fi
    
    print_success "Requirements check passed"
}

# ============================================================
# INSTALL OPENVPN3 BINARY FROM GITHUB
# ============================================================
install_openvpn3_binary() {
    print_step "Installing OpenVPN3 binary from GitHub..."
    
    mkdir -p /usr/local/bin
    
    if [ -f /usr/local/bin/ovpncli ] && [ -x /usr/local/bin/ovpncli ]; then
        print_info "OpenVPN3 binary already exists"
        read -p "Re-download? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    print_info "Downloading OpenVPN3 binary..."
    wget -q -O /usr/local/bin/ovpncli "$GITHUB_RAW/ovpn/binaries/ovpncli" 2>/dev/null || \
    wget -q -O /usr/local/bin/ovpncli "$GITHUB_RAW/ovpn/binaries/ovpnclis" 2>/dev/null || {
        print_warn "Binary not available, continuing without OpenVPN3 client"
        return 0
    }
    
    chmod 755 /usr/local/bin/ovpncli
    ln -sf /usr/local/bin/ovpncli /usr/bin/ovpncli 2>/dev/null || true
    ln -sf /usr/local/bin/ovpncli /usr/local/bin/openvpn3 2>/dev/null || true
    
    # Install runtime dependencies
    MISSING_LIBS=$(ldd /usr/local/bin/ovpncli 2>/dev/null | grep "not found" | wc -l)
    if [ $MISSING_LIBS -gt 0 ]; then
        apt install -y libssl3 liblz4-1 libxxhash0 libfmt9 libjsoncpp25 2>/dev/null || true
    fi
    
    print_success "OpenVPN3 binary installed"
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing packages..."
    
    apt update -y
    
    PACKAGES="openvpn easy-rsa stunnel4 iptables-persistent netfilter-persistent wget curl openssl"
    
    for pkg in $PACKAGES; do
        if ! dpkg -l | grep -qE "^ii|^hi" "$pkg"; then
            print_info "Installing $pkg..."
            apt install -y --no-install-recommends $pkg 2>/dev/null || print_warn "Failed to install $pkg"
        else
            print_info "$pkg already installed"
        fi
    done
    
    print_success "Packages installed"
}

# ============================================================
# SETUP EASY-RSA
# ============================================================
setup_easyrsa() {
    print_step "Setting up Easy-RSA..."
    
    if [ -d "$EASYRSA_DIR" ]; then
        mv "$EASYRSA_DIR" "${EASYRSA_DIR}.backup.$(date +%s)" 2>/dev/null
    fi
    
    make-cadir "$EASYRSA_DIR"
    cd "$EASYRSA_DIR"
    
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

    print_info "Building PKI..."
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass
    
    print_info "Generating server certificate..."
    ./easyrsa --batch gen-req server nopass
    ./easyrsa --batch sign-req server server
    
    print_info "Generating DH parameters..."
    ./easyrsa --batch gen-dh
    
    print_info "Generating TLS auth key..."
    openvpn --genkey --secret "$EASYRSA_DIR/pki/ta.key"
    ./easyrsa gen-crl
    
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
    
    OVPN_VERSION=$(openvpn --version 2>/dev/null | head -1 | awk '{print $2}' | cut -d. -f1,2)
    print_info "OpenVPN version: $OVPN_VERSION"
    
    if [[ "$OVPN_VERSION" =~ ^2\.[6-9] ]] || [[ "$OVPN_VERSION" =~ ^2\.[1-9][0-9] ]]; then
        CIPHER_LINE="data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC"
    else
        CIPHER_LINE="# OpenVPN $OVPN_VERSION - using cipher only"
    fi
    
    # ============================================================
    # TCP Server (Direct - Port 1194)
    # ============================================================
    cat > "$OVPN_DIR/server-tcp.conf" <<EOF
# ============================================
# MarcScript OpenVPN TCP Server (Direct)
# Port: $OVPN_TCP_PORT
# Network: ${OVPN_NET_TCP}.0/24
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

tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384

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
$CIPHER_LINE
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

    # ============================================================
    # UDP Server (Direct - Port 2200)
    # ============================================================
    cat > "$OVPN_DIR/server-udp.conf" <<EOF
# ============================================
# MarcScript OpenVPN UDP Server (Direct)
# Port: $OVPN_UDP_PORT
# Network: ${OVPN_NET_UDP}.0/24
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

tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384

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
$CIPHER_LINE
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

    # ============================================================
    # TLS-Wrapped Server (Internal - Port 11940, Stunnel forwards 4443→here)
    # ============================================================
    cat > "$OVPN_DIR/server-tls.conf" <<EOF
# ============================================
# MarcScript OpenVPN TLS-Wrapped Server
# Internal Port: $OVPN_TLS_INTERNAL (localhost)
# Stunnel forwards: $OVPN_TLS_PORT → $OVPN_TLS_INTERNAL
# Network: ${OVPN_NET_TLS}.0/24
# ============================================

port $OVPN_TLS_INTERNAL
proto tcp
dev tun

ca $OVPN_DIR/ca.crt
cert $OVPN_DIR/server.crt
key $OVPN_DIR/server.key
dh $OVPN_DIR/dh.pem
tls-auth $OVPN_DIR/ta.key 0
crl-verify $OVPN_DIR/crl.pem

tls-version-min 1.2

topology subnet
server ${OVPN_NET_TLS}.0 $OVPN_NETMASK
ifconfig-pool-persist $OVPN_DIR/ipp-tls.txt

push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "dhcp-option DNS 1.1.1.1"
push "redirect-gateway def1 bypass-dhcp"

keepalive 10 120
cipher AES-256-GCM
auth SHA256
$CIPHER_LINE
compress lz4-v2
push "compress lz4-v2"

max-clients 50
user nobody
group nogroup
persist-key
persist-tun

status $OVPN_LOG_DIR/openvpn-tls-status.log
log-append $OVPN_LOG_DIR/openvpn-tls.log
verb 3

management 127.0.0.1 $((OVPN_MGMT_PORT + 2))
EOF

    print_success "Server configs created (Direct + TLS-Wrapped)"
}

# ============================================================
# CONFIGURE STUNNEL FOR OPENVPN
# ============================================================
configure_stunnel() {
    print_step "Configuring Stunnel for OpenVPN TLS..."
    
    if [ "$STUNNEL_CERT_EXISTS" = false ]; then
        print_warn "No certificate available, skipping Stunnel configuration"
        return 0
    fi
    
    # Ensure Stunnel is installed
    if ! command -v stunnel4 &>/dev/null; then
        apt install -y stunnel4
    fi
    
    # Create Stunnel user if not exists
    if ! id stunnel4 &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi
    
    # Create directories
    mkdir -p /var/log/stunnel4 /var/run/stunnel4
    chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4
    
    # Backup existing config
    if [ -f "$STUNNEL_DIR/stunnel.conf" ]; then
        cp "$STUNNEL_DIR/stunnel.conf" "$STUNNEL_DIR/stunnel.conf.bak.$(date +%s)" 2>/dev/null
    fi
    
    # Check if OpenVPN Stunnel section already exists
    if [ -f "$STUNNEL_DIR/stunnel.conf" ] && grep -q "\[ovpn-tls\]" "$STUNNEL_DIR/stunnel.conf"; then
        print_info "OpenVPN Stunnel entries already exist in config"
    else
        print_info "Adding OpenVPN Stunnel entries..."
        
        # Append to existing config or create new
        if [ -f "$STUNNEL_DIR/stunnel.conf" ]; then
            cat >> "$STUNNEL_DIR/stunnel.conf" <<'EOF'

; ============================================
; OpenVPN over TLS (Stunnel Wrapper)
; ============================================
[ovpn-tls]
accept = 4443
connect = 127.0.0.1:11940
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ovpn-tls-alt]
accept = 4444
connect = 127.0.0.1:11940
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
EOF
        else
            # Create new config
            cat > "$STUNNEL_DIR/stunnel.conf" <<'EOF'
; Stunnel4 Config - MarcScript VPN
; Includes SSH, WebSocket, and OpenVPN TLS support

cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
pid = /var/run/stunnel4/stunnel4.pid
debug = 3
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3
ciphers = DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4

; OpenVPN over TLS
[ovpn-tls]
accept = 4443
connect = 127.0.0.1:11940
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ovpn-tls-alt]
accept = 4444
connect = 127.0.0.1:11940
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
EOF
        fi
    fi
    
    # Enable Stunnel
    if [ ! -f /etc/default/stunnel4 ]; then
        echo 'ENABLED=1' > /etc/default/stunnel4
    else
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
    fi
    
    # Create systemd override
    mkdir -p /etc/systemd/system/stunnel4.service.d/
    cat > /etc/systemd/system/stunnel4.service.d/override.conf <<EOF
[Service]
RuntimeDirectory=stunnel4
RuntimeDirectoryMode=0755
ExecStartPre=/bin/mkdir -p /var/run/stunnel4
ExecStartPre=/bin/chown stunnel4:stunnel4 /var/run/stunnel4
EOF
    
    systemctl daemon-reload
    systemctl enable stunnel4 2>/dev/null || true
    systemctl restart stunnel4 2>/dev/null || true
    
    sleep 2
    
    if systemctl is-active --quiet stunnel4; then
        print_success "Stunnel configured for OpenVPN TLS"
        print_info "OpenVPN TLS available on ports: $OVPN_TLS_PORT, $OVPN_TLS_ALT_PORT"
    else
        print_warn "Stunnel failed to start"
        journalctl -u stunnel4 --no-pager -n 5
    fi
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
    
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    [ -z "$NIC" ] && NIC=$(ip -4 addr show | grep -v "127.0.0.1" | grep "inet " | head -1 | awk '{print $NF}')
    print_info "Network interface: $NIC"
    
    # Allow OpenVPN ports
    iptables -A INPUT -p tcp --dport $OVPN_TCP_PORT -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p udp --dport $OVPN_UDP_PORT -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport $OVPN_TLS_PORT -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport $OVPN_TLS_ALT_PORT -j ACCEPT 2>/dev/null || true
    
    # NAT rules
    iptables -t nat -A POSTROUTING -s ${OVPN_NET_TCP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s ${OVPN_NET_UDP}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s ${OVPN_NET_TLS}.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
    
    # Forward rules
    iptables -A FORWARD -s ${OVPN_NET_TCP}.0/24 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -s ${OVPN_NET_UDP}.0/24 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -s ${OVPN_NET_TLS}.0/24 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    # Save rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    netfilter-persistent save 2>/dev/null || true
    
    print_success "System and firewall configured"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting OpenVPN services..."
    
    systemctl daemon-reload
    
    # Start TCP server
    systemctl enable openvpn@server-tcp 2>/dev/null
    systemctl start openvpn@server-tcp 2>/dev/null
    
    # Start UDP server
    systemctl enable openvpn@server-udp 2>/dev/null
    systemctl start openvpn@server-udp 2>/dev/null
    
    # Start TLS server (if Stunnel is active)
    if systemctl is-active --quiet stunnel4; then
        systemctl enable openvpn@server-tls 2>/dev/null
        systemctl start openvpn@server-tls 2>/dev/null
    fi
    
    sleep 3
    
    # Verify services
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
    
    if systemctl is-active --quiet openvpn@server-tls 2>/dev/null; then
        print_success "OpenVPN TLS running (internal port $OVPN_TLS_INTERNAL)"
    fi
    
    if systemctl is-active --quiet stunnel4; then
        print_success "Stunnel TLS wrapper running on ports $OVPN_TLS_PORT, $OVPN_TLS_ALT_PORT"
    fi
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_step "Downloading management scripts..."
    
    mkdir -p /root/ovpn "$WEB_DIR"
    
    SCRIPTS="create-user.sh renew-user.sh delete-user.sh list-user.sh menu-ovpn.sh check-expired.sh"
    
    for script in $SCRIPTS; do
        wget -q -O "/root/ovpn/$script" "$GITHUB_RAW/ovpn/$script" 2>/dev/null && \
        chmod +x "/root/ovpn/$script" || print_warn "Could not download $script"
    done
    
    touch "$USER_DB"
    print_success "Scripts downloaded"
}

# ============================================================
# SETUP CRON & AUTO-EXPIRATION
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
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         ✅ OPENVPN INSTALLED WITH STUNNEL TLS!             ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📡 SERVER INFORMATION:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "IP Address" "$SERVER_IP"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC} %s\n" "TCP (Direct)" "$OVPN_TCP_PORT" "(OpenVPN TLS)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC} %s\n" "UDP (Direct)" "$OVPN_UDP_PORT" "(OpenVPN TLS)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC} %s\n" "TLS (Stunnel)" "$OVPN_TLS_PORT" "(Stunnel + OpenVPN)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC} %s\n" "TLS Alt" "$OVPN_TLS_ALT_PORT" "(Stunnel + OpenVPN)"
    echo ""
    
    echo -e "${CYAN}🔐 CERTIFICATE:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ -f "$STUNNEL_DIR/stunnel.pem" ]; then
        echo -e "  ${WHITE}Stunnel PEM${NC} : ${GREEN}$STUNNEL_DIR/stunnel.pem${NC}"
        echo -e "  ${WHITE}Status${NC}     : ${GREEN}Using existing certificate${NC}"
    else
        echo -e "  ${RED}No certificate found${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}🌐 NETWORK SUBNETS:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}TCP Subnet${NC} : ${GREEN}${OVPN_NET_TCP}.0/24${NC}"
    echo -e "  ${WHITE}UDP Subnet${NC} : ${GREEN}${OVPN_NET_UDP}.0/24${NC}"
    echo -e "  ${WHITE}TLS Subnet${NC} : ${GREEN}${OVPN_NET_TLS}.0/24${NC}"
    echo ""
    
    echo -e "${CYAN}🔧 MANAGEMENT:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Create User${NC} : ${YELLOW}bash /root/ovpn/create-user.sh${NC}"
    echo -e "  ${WHITE}OVPN Menu${NC}   : ${YELLOW}bash /root/ovpn/menu-ovpn.sh${NC}"
    echo -e "  ${WHITE}List Users${NC}  : ${YELLOW}bash /root/ovpn/list-user.sh${NC}"
    echo ""
    
    echo -e "${CYAN}⚙️  SERVICE CONTROL:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}TCP Status${NC}  : systemctl status openvpn@server-tcp"
    echo -e "  ${WHITE}UDP Status${NC}  : systemctl status openvpn@server-udp"
    echo -e "  ${WHITE}TLS Status${NC}  : systemctl status openvpn@server-tls"
    echo -e "  ${WHITE}Stunnel${NC}     : systemctl status stunnel4"
    echo ""
    
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${CYAN}  🔐 TLS uses existing Stunnel certificate                  ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}  📁 Certificate: /etc/stunnel/stunnel.pem                 ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}  🔄 Auto-renewal via cert-renew.sh cron job               ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_success "Installation completed!"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}       🔐 MARCSCRIPT OPENVPN + STUNNEL TLS INSTALLER       ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Features:${NC}"
    echo -e "  • OpenVPN3 pre-compiled binary"
    echo -e "  • Direct TCP/UDP with built-in TLS"
    echo -e "  • Stunnel TLS wrapper (ports 4443, 4444)"
    echo -e "  • Uses existing SSL certificate"
    echo -e "  • User management with expiration"
    echo -e "  • Download URLs for config files"
    echo ""
    echo -e "${YELLOW}Ports (no conflict with SSH/Xray):${NC}"
    echo -e "  TCP: $OVPN_TCP_PORT | UDP: $OVPN_UDP_PORT | TLS: $OVPN_TLS_PORT | TLS-Alt: $OVPN_TLS_ALT_PORT"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
    configure_stunnel
    configure_system
    start_services
    download_scripts
    setup_cron
    display_summary
}

main "$@"