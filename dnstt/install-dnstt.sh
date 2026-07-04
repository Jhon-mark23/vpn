#!/bin/bash
# ============================================================
# MARCSCRIPT DNSTT INSTALLER v2.0
# DNS Tunnel (SlowDNS) with UDP Support
# Compatible with Ubuntu & Debian (including Debian 13)
# ============================================================

set -euo pipefail

# ============================================================
# COLOURS
# ============================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================
# LOGGING FUNCTIONS
# ============================================================
print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}OK${NC} ] $1"; }
print_step()  { echo -e "[ ${CYAN}STEP${NC} ] $1"; }
print_fatal() { 
    echo -e "[ ${RED}FATAL${NC} ] $1" >&2
    exit 1
}

# ============================================================
# ERROR HANDLING
# ============================================================
trap 'print_error "Script interrupted at line $LINENO"' INT TERM
trap 'print_error "Error occurred at line $LINENO. Exit code: $?"' ERR

# ============================================================
# CONFIGURATION
# ============================================================
GITHUB_RAW="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_LOG_DIR="/var/log/slowdns"
DNSTT_UDP_PORT="5300"
SSH_PORT="2222"
DNSTT_ALT_SSH="2269"
PUBLIC_DNS="8.8.8.8:53"
MAX_RETRIES=3
RETRY_DELAY=3

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
        print_fatal "Cannot detect OS"
    fi
    
    print_info "Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_fatal "This script only supports Ubuntu or Debian"
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
            return 1
            ;;
    esac
    
    print_info "Architecture: $ARCH → $SLOWDNS_ARCH"
}

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_fatal "Please run as root"
fi

# ============================================================
# SETUP IPTABLES
# ============================================================
setup_iptables() {
    print_step "Setting up iptables rules..."
    
    # Install iptables if not present
    apt install -y iptables iptables-persistent netfilter-persistent 2>/dev/null || {
        print_warn "Failed to install iptables packages, continuing..."
    }
    
    # Check if port 5300 is already in use
    if ss -lun | grep -q ":5300"; then
        print_warn "Port 5300 is already in use"
        if ! read -p "Continue anyway? (y/n): " -n 1 -r; then
            print_info "Skipping iptables setup"
            return 0
        fi
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Backup existing rules
    mkdir -p /etc/iptables/backup
    iptables-save > "/etc/iptables/backup/rules.v4.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Allow UDP port 5300
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || {
        print_warn "Failed to add iptables rule (may already exist)"
    }
    
    # Redirect DNS (port 53) to DNSTT port (5300)
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || {
        print_warn "Failed to add NAT rule (may already exist)"
    }
    
    # Save rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || {
            print_warn "Failed to save iptables rules with netfilter-persistent"
        }
        netfilter-persistent reload 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || {
            print_warn "Failed to save iptables rules"
        }
    fi
    
    print_success "Iptables configured"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Configuring DNS Tunnel domain..."
    
    # Try multiple sources for domain
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || \
             cat /root/domain.txt 2>/dev/null || \
             cat /root/domain 2>/dev/null || \
             echo "None")
    
    if [ "$DOMAIN" = "None" ]; then
        print_warn "No domain found in common locations"
        read -rp "Enter your domain: " DOMAIN
        if [ -z "$DOMAIN" ]; then
            print_fatal "Domain cannot be empty"
        fi
    else
        print_info "Found domain: $DOMAIN"
    fi
    
    # Build NS domain
    SUB="ns"
    NS_DOMAIN="${SUB}.${DOMAIN}"
    
    echo "$NS_DOMAIN" > /root/nsdomain 2>/dev/null || true
    echo "$NS_DOMAIN" > /root/nsdomain.txt 2>/dev/null || true
    
    print_info "NS Domain: ${CYAN}${NS_DOMAIN}${NC}"
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    # Update package list with retry
    local retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        if apt update -y 2>/dev/null; then
            break
        fi
        retry=$((retry + 1))
        print_warn "Failed to update package list, retry $retry/$MAX_RETRIES"
        sleep $RETRY_DELAY
    done
    
    if [ $retry -eq $MAX_RETRIES ]; then
        print_warn "Failed to update package list, continuing with existing packages"
    fi
    
    # Install packages
    local packages=(
        "python3" "python3-dnslib" "python3-pip" "net-tools"
        "dnsutils" "git" "curl" "wget" "screen" "cron"
        "iptables" "dropbear" "sudo" "gnutls-bin"
        "dos2unix" "debconf-utils" "ca-certificates" "openssl"
    )
    
    # Install each package with retry
    for pkg in "${packages[@]}"; do
        retry=0
        while [ $retry -lt $MAX_RETRIES ]; do
            if apt install -y "$pkg" 2>/dev/null; then
                break
            fi
            retry=$((retry + 1))
            print_warn "Failed to install $pkg, retry $retry/$MAX_RETRIES"
            sleep $RETRY_DELAY
        done
        
        if [ $retry -eq $MAX_RETRIES ]; then
            print_warn "Failed to install $pkg, continuing..."
        fi
    done
    
    # Try to install ncurses-utils (optional)
    apt install -y ncurses-utils 2>/dev/null || {
        print_warn "ncurses-utils not available (optional, skipping)"
    }
    
    # Restart cron
    systemctl restart cron 2>/dev/null || {
        print_warn "Failed to restart cron (may not be installed)"
    }
    
    print_success "Packages installed"
}

# ============================================================
# CONFIGURE SSH
# ============================================================
configure_ssh() {
    print_step "Configuring SSH for DNSTT..."
    
    # Backup SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.dnstt.$(date +%Y%m%d) 2>/dev/null || true
    
    # Add SSH ports if not present
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        print_info "Added SSH port $SSH_PORT"
    else
        print_info "SSH port $SSH_PORT already configured"
    fi
    
    if ! grep -q "^Port $DNSTT_ALT_SSH" /etc/ssh/sshd_config; then
        echo "Port $DNSTT_ALT_SSH" >> /etc/ssh/sshd_config
        print_info "Added SSH port $DNSTT_ALT_SSH"
    else
        print_info "SSH port $DNSTT_ALT_SSH already configured"
    fi
    
    # Enable TCP forwarding
    sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    
    # Restart SSH with retry
    local retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
        sleep 2
        
        if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
            print_success "SSH configured and running"
            return 0
        fi
        
        retry=$((retry + 1))
        print_warn "SSH restart attempt $retry/$MAX_RETRIES failed"
        sleep $RETRY_DELAY
    done
    
    print_warn "SSH may not be running, please check manually"
}

# ============================================================
# DOWNLOAD WITH RETRY
# ============================================================
download_with_retry() {
    local url=$1
    local output=$2
    local description=${3:-"file"}
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if wget -q -O "$output" "$url" 2>/dev/null; then
            return 0
        fi
        retry=$((retry + 1))
        print_warn "Failed to download $description (attempt $retry/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    done
    
    return 1
}

# ============================================================
# INSTALL DNSTT BINARIES
# ============================================================
install_binaries() {
    print_step "Installing DNSTT binaries..."
    
    # Remove old directory
    rm -rf "$SLOWDNS_DIR" 2>/dev/null || true
    
    # Create directories
    mkdir -m 755 "$SLOWDNS_DIR" 2>/dev/null || {
        print_fatal "Failed to create directory: $SLOWDNS_DIR"
    }
    mkdir -p "$SLOWDNS_LOG_DIR" 2>/dev/null || true
    
    # Download binaries
    print_info "Downloading DNSTT server binary..."
    if ! download_with_retry \
        "$GITHUB_RAW/dnstt/dnstt-server-linux-${SLOWDNS_ARCH}" \
        "$SLOWDNS_DIR/sldns-server" \
        "server binary"; then
        print_fatal "Failed to download server binary after $MAX_RETRIES attempts"
    fi
    
    print_info "Downloading DNSTT client binary..."
    if ! download_with_retry \
        "$GITHUB_RAW/dnstt/dnstt-client-linux-${SLOWDNS_ARCH}" \
        "$SLOWDNS_DIR/sldns-client" \
        "client binary"; then
        print_warn "Failed to download client binary (optional for server)"
    fi
    
    # Make executable
    chmod +x "$SLOWDNS_DIR/sldns-server" 2>/dev/null || {
        print_fatal "Failed to make server binary executable"
    }
    chmod +x "$SLOWDNS_DIR/sldns-client" 2>/dev/null || true
    
    # Verify server binary
    if ! "$SLOWDNS_DIR/sldns-server" 2>&1 | grep -q "Usage\|privkey-file"; then
        print_error "Server binary verification failed!"
        print_info "Testing binary output:"
        "$SLOWDNS_DIR/sldns-server" --help 2>&1 || true
        print_fatal "Binary verification failed"
    fi
    
    print_success "DNSTT binaries installed"
}

# ============================================================
# GENERATE KEYS
# ============================================================
generate_keys() {
    print_step "Generating DNSTT keypair..."
    
    cd "$SLOWDNS_DIR" || print_fatal "Cannot change to $SLOWDNS_DIR"
    
    # Check if keys already exist
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        print_info "Keys already exist"
        if ! read -p "Regenerate? (y/n): " -n 1 -r; then
            print_info "Keeping existing keys"
            chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
            chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
            return 0
        fi
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
            chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
            return 0
        fi
    fi
    
    # Generate keys
    if ! ./sldns-server -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub" 2>/dev/null; then
        print_fatal "Key generation failed!"
    fi
    
    if [ -f "$SLOWDNS_DIR/server.key" ] && [ -f "$SLOWDNS_DIR/server.pub" ]; then
        chmod 600 "$SLOWDNS_DIR/server.key" 2>/dev/null || true
        chmod 644 "$SLOWDNS_DIR/server.pub" 2>/dev/null || true
        
        # Display public key
        PUBKEY=$(cat "$SLOWDNS_DIR/server.pub" 2>/dev/null || echo "ERROR")
        if [ "$PUBKEY" != "ERROR" ]; then
            print_success "Keypair generated successfully"
            print_info "Public Key: ${YELLOW}${PUBKEY}${NC}"
        else
            print_warn "Key generated but couldn't read public key"
        fi
    else
        print_fatal "Key generation failed - files not created"
    fi
}

# ============================================================
# CREATE SYSTEMD SERVICES
# ============================================================
create_services() {
    print_step "Creating systemd services..."
    
    # Check if NS_DOMAIN is set
    if [ -z "${NS_DOMAIN:-}" ]; then
        print_error "NS_DOMAIN is not set, reading from file"
        NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null || echo "unknown.domain")
        if [ "$NS_DOMAIN" = "unknown.domain" ]; then
            print_fatal "Cannot determine NS domain"
        fi
    fi
    
    # Server Service
    cat > /etc/systemd/system/server-sldns.service <<EOF
[Unit]
Description=MarcScript DNSTT Server (SlowDNS)
Documentation=https://github.com/Jhon-mark23/vpn
After=network.target nss-lookup.target
Wants=network.target

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
StandardOutput=append:$SLOWDNS_LOG_DIR/server.log
StandardError=append:$SLOWDNS_LOG_DIR/server-error.log

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
LimitNOFILE=65536
StandardOutput=append:$SLOWDNS_LOG_DIR/client.log
StandardError=append:$SLOWDNS_LOG_DIR/client-error.log

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod 644 /etc/systemd/system/server-sldns.service 2>/dev/null || true
    chmod 644 /etc/systemd/system/client-sldns.service 2>/dev/null || true
    
    print_success "Systemd services created"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting DNSTT services..."
    
    # Kill existing processes
    pkill -f sldns-server 2>/dev/null || true
    pkill -f sldns-client 2>/dev/null || true
    
    systemctl daemon-reload 2>/dev/null || true
    
    # Stop existing if running
    systemctl stop server-sldns 2>/dev/null || true
    systemctl stop client-sldns 2>/dev/null || true
    
    # Enable and start server
    if systemctl enable server-sldns 2>/dev/null; then
        print_info "Server service enabled"
    else
        print_warn "Failed to enable server service"
    fi
    
    if systemctl start server-sldns 2>/dev/null; then
        print_info "Server service started"
    else
        print_warn "Failed to start server service"
    fi
    
    # Enable and start client (optional)
    if systemctl enable client-sldns 2>/dev/null; then
        print_info "Client service enabled"
    else
        print_warn "Failed to enable client service (optional)"
    fi
    
    if systemctl start client-sldns 2>/dev/null; then
        print_info "Client service started"
    else
        print_warn "Failed to start client service (optional)"
    fi
    
    sleep 3
    
    # Verify
    if systemctl is-active --quiet server-sldns 2>/dev/null; then
        print_success "DNSTT Server running on UDP port $DNSTT_UDP_PORT"
        print_info "NS Domain: $NS_DOMAIN"
    else
        print_error "DNSTT Server failed to start!"
        print_info "Checking service status..."
        systemctl status server-sldns --no-pager --lines=5 2>/dev/null || true
        print_info "Recent logs:"
        journalctl -u server-sldns --no-pager -n 10 2>/dev/null || true
    fi
    
    if systemctl is-active --quiet client-sldns 2>/dev/null; then
        print_success "DNSTT Client running"
    else
        print_warn "DNSTT Client not running (may be normal on server only)"
    fi
}

# ============================================================
# CREATE CLIENT CONFIG
# ============================================================
create_client_config() {
    print_step "Creating client configuration..."
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "UNKNOWN")
    PUBKEY=$(cat "$SLOWDNS_DIR/server.pub" 2>/dev/null || echo "ERROR")
    
    # Client config file
    cat > "$SLOWDNS_DIR/client-config.txt" <<EOF
====================================
MarcScript DNSTT Client Config
====================================
Server IP    : $SERVER_IP
NS Domain    : $NS_DOMAIN
DNS Port     : $DNSTT_UDP_PORT (UDP)
SSH Port     : $SSH_PORT
Alt SSH      : $DNSTT_ALT_SSH
Public Key   : $PUBKEY

====================================
EOF

    print_success "Client config saved to $SLOWDNS_DIR/client-config.txt"
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================
display_summary() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "UNKNOWN")
    PUBKEY=$(cat "$SLOWDNS_DIR/server.pub" 2>/dev/null || echo "ERROR")
    
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         ✅ MARCSCRIPT DNSTT INSTALLED SUCCESSFULLY         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📡 SERVER INFORMATION:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server IP" "$SERVER_IP"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "NS Domain" "${NS_DOMAIN:-UNKNOWN}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "DNS Port" "$DNSTT_UDP_PORT (UDP)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "SSH Port" "$SSH_PORT"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Alt SSH" "$DNSTT_ALT_SSH"
    echo ""
    
    echo -e "${CYAN}🔑 PUBLIC KEY:${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}${PUBKEY}${NC}"
    echo ""
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}         🔒 MARCSCRIPT DNSTT INSTALLER v2.0                ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${WHITE}         DNS Tunnel with DoH/DoT/UDP Support                ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Ports:${NC}"
    echo -e "  DNS Tunnel: $DNSTT_UDP_PORT (UDP)"
    echo -e "  SSH: $SSH_PORT, $DNSTT_ALT_SSH"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if ! read -p "Continue? (y/n): " -n 1 -r; then
        echo
        print_info "Installation cancelled by user"
        exit 0
    fi
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
    
    # Run installation steps
    detect_os
    detect_arch || print_fatal "Architecture not supported"
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
    
    print_success "DNSTT installation completed!"
}

# ============================================================
# SCRIPT ENTRY
# ============================================================
main "$@"