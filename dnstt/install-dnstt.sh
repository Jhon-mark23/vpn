#!/bin/bash
# ============================================================
# DNSTT INSTALLER - Enhanced Version
# Auto Domain Detect | Clean Removal | Reinstall Support
# Private Repo Download | Background Service | Management Tools
# Version: 5.0
# ============================================================

set -e

# ---------- COLORS ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---------- FUNCTIONS ----------
print_step() {
    echo -e "${BLUE}➜${NC} $1"
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header() {
    echo -e "${PURPLE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════${NC}"
}

# ---------- CHECK ROOT ----------
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (sudo)"
    exit 1
fi

# ============================================================
# 1. GET DOMAIN - AUTO DETECT + MANUAL FALLBACK
# ============================================================
get_domain() {
    print_step "Detecting domain..."
    
    # Auto detect from common locations
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || \
             cat /root/domain.txt 2>/dev/null || \
             cat /root/domain 2>/dev/null || \
             echo "")
    
    # If domain found, confirm usage
   # if [[ -n "$DOMAIN" && "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
   #     print_info "Found domain: ${CYAN}${DOMAIN}${NC}"
   #     read -rp "Use this domain? (y/n) [y]: " confirm
   #     if [[ "$confirm" =~ ^[Nn]$ ]]; then
   #         DOMAIN=""
   #     fi
   # fi
    
    # If no valid domain, ask user
    if [[ -z "$DOMAIN" ]]; then
        echo ""
        print_info "Enter your domain manually"
        read -rp "Domain (e.g., example.com): " DOMAIN
        
        # Validate domain
        if [[ -z "$DOMAIN" || ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain format!"
            exit 1
        fi
    fi
    
    # Set subdomain prefix
   # echo ""
    #read -rp "Subdomain prefix [ns]: " SUB
    #SUB="${SUB:-ns}"
    SUB="ns"
    # Build NS domain
    NS_DOMAIN="${SUB}.${DOMAIN}"
    
    # Save to files
    echo "$DOMAIN" > /root/domain 2>/dev/null || echo "$DOMAIN" > /root/domain.txt
    echo "$NS_DOMAIN" > /root/nsdomain
    echo "$NS_DOMAIN" > /root/nsdomain.txt
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')
    echo "$SERVER_IP" > /root/server-ip 2>/dev/null
    
    print_info "Main Domain: ${CYAN}${DOMAIN}${NC}"
    print_info "NS Domain: ${CYAN}${NS_DOMAIN}${NC}"
    print_info "Server IP: ${CYAN}${SERVER_IP}${NC}"
}

# ============================================================
# 2. CLEAN REMOVE OLD DNSTT
# ============================================================
clean_remove() {
    print_step "Removing old DNSTT installation..."
    
    # List of services to clean
    SERVICES=(
        "dnstt"
        "dnstt-server"
        "dnstt-client"
        "server-sldns"
        "client-sldns"
        "sldns"
    )
    
    # Stop and disable services
    for service in "${SERVICES[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "${service}.service"; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/${service}.service" 2>/dev/null || true
            rm -f "/lib/systemd/system/${service}.service" 2>/dev/null || true
            print_info "Removed service: $service"
        fi
    done
    
    # Remove service files
    rm -f /etc/systemd/system/*dnstt*.service 2>/dev/null || true
    rm -f /etc/systemd/system/*sldns*.service 2>/dev/null || true
    
    # Kill processes
    pkill -f "dnstt-server" 2>/dev/null || true
    pkill -f "sldns-server" 2>/dev/null || true
    pkill -f "dnstt-client" 2>/dev/null || true
    
    # Free port 5300
    fuser -k 5300/udp 2>/dev/null || true
    fuser -k 5300/tcp 2>/dev/null || true
    
    # Remove screen sessions
    screen -S dnstt -X quit 2>/dev/null || true
    screen -S sldns -X quit 2>/dev/null || true
    
    # Remove iptables rules
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    iptables -t nat -D PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Save iptables
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    # Backup config before removal
    if [[ -d /etc/dnstt ]]; then
        BACKUP_DIR="/root/dnstt-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Backup only if files exist
        [[ -f /etc/dnstt/private.key ]] && cp /etc/dnstt/private.key "$BACKUP_DIR/"
        [[ -f /etc/dnstt/private.pub ]] && cp /etc/dnstt/private.pub "$BACKUP_DIR/"
        [[ -f /etc/dnstt/config.json ]] && cp /etc/dnstt/config.json "$BACKUP_DIR/"
        
        print_info "Backup saved to: $BACKUP_DIR"
    fi
    
    # Remove directories
    rm -rf /etc/dnstt 2>/dev/null || true
    rm -rf /etc/slowdns 2>/dev/null || true
    rm -rf /var/log/slowdns 2>/dev/null || true
    
    # Remove old files
    rm -f /usr/local/bin/dnstt-server 2>/dev/null || true
    rm -f /usr/local/bin/dnstt-client 2>/dev/null || true
    rm -f /usr/local/bin/dnstt-* 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true
    
    print_info "Cleanup completed"
    echo ""
}

# ============================================================
# 3. INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    apt update -y 2>/dev/null || true
    apt install -y curl wget screen iptables iptables-persistent \
                   net-tools dnsutils jq 2>/dev/null || true
    
    print_info "Packages installed"
}

# ============================================================
# 4. DOWNLOAD BINARY
# ============================================================
download_binary() {
    print_step "Downloading DNSTT binary..."
    
    BINARY="/usr/local/bin/dnstt-server"
    
    # Check GitHub token
    gtoken=$(cat /root/token 2>/dev/null || cat /root/token.txt 2>/dev/null)
    
    if [[ -z "$gtoken" ]]; then
        print_warning "GitHub token not found in /root/token"
        print_info "Trying public download..."
        
        # Fallback to public download
        ARCH=$(uname -m)
        case $ARCH in
            x86_64)  BIN_ARCH="amd64" ;;
            aarch64|arm64) BIN_ARCH="arm64" ;;
            *) BIN_ARCH="amd64" ;;
        esac
        
        curl -sL "https://github.com/mshafiee/dnstt/releases/latest/download/dnstt-server-linux-${BIN_ARCH}" \
            -o /tmp/dnstt-server 2>/dev/null || {
                print_error "Failed to download binary!"
                exit 1
            }
    else
        # Download from private repo
        curl -sS -H "Authorization: Bearer $gtoken" \
             -H "Accept: application/vnd.github.raw" \
             "https://api.github.com/repos/Jhon-mark23/vpn/contents/dnstt/dnstt-server?ref=main" \
             -o /tmp/dnstt-server 2>/dev/null || {
                print_error "Failed to download from private repo!"
                exit 1
            }
    fi
    
    # Verify download
    if [[ ! -s /tmp/dnstt-server ]]; then
        print_error "Downloaded file is empty!"
        exit 1
    fi
    
    # Install binary
    chmod +x /tmp/dnstt-server
    mv /tmp/dnstt-server "$BINARY"
    
    print_info "Binary installed: $BINARY"
    
    # Download client binary (optional)
    print_step "Downloading DNSTT client binary..."
    CLIENT_BINARY="/usr/local/bin/dnstt-client"
    
    if [[ -n "$gtoken" ]]; then
        curl -sS -H "Authorization: Bearer $gtoken" \
             -H "Accept: application/vnd.github.raw" \
             "https://api.github.com/repos/Jhon-mark23/vpn/contents/dnstt/dnstt-client?ref=main" \
             -o /tmp/dnstt-client 2>/dev/null || print_warning "Client binary not available"
    fi
    
    if [[ -s /tmp/dnstt-client ]]; then
        chmod +x /tmp/dnstt-client
        mv /tmp/dnstt-client "$CLIENT_BINARY"
        print_info "Client binary installed"
    else
        print_warning "Client binary not downloaded (optional)"
    fi
}

# ============================================================
# 5. GENERATE KEYS
# ============================================================
generate_keys() {
    print_step "Generating DNSTT keys..."
    
    BINARY="/usr/local/bin/dnstt-server"
    KEY_DIR="/etc/dnstt"
    
    mkdir -p "$KEY_DIR"
    cd "$KEY_DIR"
    
    # Generate private key (always fresh)
    rm -f private.key private.pub 2>/dev/null || true
    $BINARY -gen-key -privkey-file private.key -pubkey-file private.pub
    
    # Set permissions
    chmod 600 private.key
    chmod 644 private.pub
    
    # Verify keys
    if [[ ! -f private.key || ! -f private.pub ]]; then
        print_error "Key generation failed!"
        exit 1
    fi
    
    # Display public key
    PUBKEY=$(cat private.pub)
    print_info "Public Key: ${YELLOW}${PUBKEY}${NC}"
    
    # Save public key to separate file for clients
    echo "$PUBKEY" > "$KEY_DIR/public-key.txt"
    cp private.pub /root/dnstt-public.key 2>/dev/null || true
    
    print_info "Keys generated successfully"
}

# ============================================================
# 6. SETUP IPTABLES
# ============================================================
setup_iptables() {
    print_step "Setting up iptables rules..."
    
    # Remove existing rules
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    iptables -t nat -D PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    
    # Add new rules
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    iptables -t nat -I PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5300
    
    # Save rules
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
    elif command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    print_info "Iptables configured (port 53 -> 5300)"
}

# ============================================================
# 7. CREATE SYSTEMD SERVICE
# ============================================================
create_service() {
    print_step "Creating systemd service..."
    
    BINARY="/usr/local/bin/dnstt-server"
    KEY_DIR="/etc/dnstt"
    NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null || echo "")
    
    if [[ -z "$NS_DOMAIN" ]]; then
        print_error "NS Domain not found!"
        exit 1
    fi
    
    # Ask for NS Point (forwarding target)
   # echo ""
    #print_info "Configure forwarding target"
   # read -rp "Forward to (IP:Port) [127.0.0.1:22]: " NS_POINT
    NS_POINT="127.0.0.1:22"
    
    SERVICE_FILE="/etc/systemd/system/dnstt.service"
    
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=DNSTT Server - DNS Tunnel
Documentation=https://www.bamsoftware.com/software/dnstt/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/dnstt
ExecStartPre=/bin/mkdir -p /var/log/dnstt
ExecStart=/usr/local/bin/dnstt-server -mtu 512 -udp :5300 -privkey-file /etc/dnstt/private.key NS_DOMAIN_PLACEHOLDER NS_POINT_PLACEHOLDER
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/dnstt.log
StandardError=append:/var/log/dnstt-error.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Replace placeholders
    sed -i "s|NS_DOMAIN_PLACEHOLDER|${NS_DOMAIN}|g" "$SERVICE_FILE"
    sed -i "s|NS_POINT_PLACEHOLDER|${NS_POINT}|g" "$SERVICE_FILE"
    
    # Create log directory
    mkdir -p /var/log/dnstt
    touch /var/log/dnstt.log /var/log/dnstt-error.log
    chmod 644 /var/log/dnstt.log /var/log/dnstt-error.log
    
    # Reload systemd
    systemctl daemon-reload
    
    print_info "Service created: dnstt.service"
}

# ============================================================
# 8. START SERVICE
# ============================================================
start_service() {
    print_step "Starting DNSTT service..."
    
    # Kill any existing processes
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f sldns-server 2>/dev/null || true
    
    # Enable and start
    systemctl enable dnstt
    systemctl restart dnstt
    
    sleep 3
    
    # Check status
    if systemctl is-active --quiet dnstt; then
        print_info "DNSTT service is running"
    else
        print_error "DNSTT service failed to start!"
        echo ""
        echo "Error details:"
        systemctl status dnstt --no-pager
        echo ""
        echo "Logs:"
        journalctl -u dnstt --no-pager -n 20
        exit 1
    fi
}

# ============================================================
# 9. CREATE MANAGEMENT SCRIPTS
# ============================================================
create_management_scripts() {
    print_step "Creating management scripts..."
    
    # Status script
    cat > /usr/local/bin/dnstt-status <<'EOF'
#!/bin/bash
echo "=== DNSTT Status ==="
echo ""
if systemctl is-active --quiet dnstt; then
    echo -e "\033[32mStatus: Running\033[0m"
    echo ""
    echo "Process Info:"
    ps aux | grep dnstt-server | grep -v grep
else
    echo -e "\033[31mStatus: Stopped\033[0m"
fi
echo ""
echo "Service: dnstt"
echo "Config: /etc/dnstt"
echo "Logs: /var/log/dnstt.log"
echo ""
echo "NS Domain: $(cat /root/nsdomain 2>/dev/null)"
echo "Public Key:"
cat /etc/dnstt/private.pub 2>/dev/null
echo ""
echo "Commands:"
echo "  systemctl start|stop|restart dnstt"
echo "  tail -f /var/log/dnstt.log"
EOF
    chmod +x /usr/local/bin/dnstt-status
    
    # Client info script
    cat > /usr/local/bin/dnstt-client <<'EOF'
#!/bin/bash
NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null)
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
PUBKEY=$(cat /etc/dnstt/private.pub 2>/dev/null)

echo "===================================="
echo "DNSTT Client Configuration"
echo "===================================="
echo ""
echo "SERVER INFORMATION:"
echo "-------------------"
echo "Server IP     : $SERVER_IP"
echo "NS Domain     : $NS_DOMAIN"
echo "DNS Port      : 5300 (UDP)"
echo ""
echo "PUBLIC KEY (save as server.pub):"
echo "-----------"
echo "$PUBKEY"
echo ""
echo "===================================="
EOF
    chmod +x /usr/local/bin/dnstt-client
    
    # Restart script
    cat > /usr/local/bin/dnstt-restart <<'EOF'
#!/bin/bash
systemctl restart dnstt
sleep 2
systemctl status dnstt --no-pager
EOF
    chmod +x /usr/local/bin/dnstt-restart
    
    # Uninstall script
    cat > /usr/local/bin/dnstt-uninstall <<'EOF'
#!/bin/bash
echo "=== DNSTT Uninstall ==="
echo ""
read -p "Are you sure you want to uninstall DNSTT? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled"
    exit 0
fi

echo "Stopping service..."
systemctl stop dnstt 2>/dev/null
systemctl disable dnstt 2>/dev/null

echo "Removing service..."
rm -f /etc/systemd/system/dnstt.service
systemctl daemon-reload

echo "Removing iptables rules..."
iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
iptables-save > /etc/iptables/rules.v4 2>/dev/null

echo "Killing processes..."
pkill -f dnstt-server 2>/dev/null
fuser -k 5300/udp 2>/dev/null

read -p "Remove configuration files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    BACKUP_DIR="/root/dnstt-uninstall-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d /etc/dnstt ]]; then
        cp -r /etc/dnstt "$BACKUP_DIR/"
        echo "Config backed up to: $BACKUP_DIR"
    fi
    
    rm -rf /etc/dnstt
    rm -f /var/log/dnstt*.log
    rm -f /root/nsdomain /root/nsdomain.txt
    echo "Configuration removed"
fi

echo "Removing management scripts..."
rm -f /usr/local/bin/dnstt-{status,client,restart,uninstall}
rm -f /usr/local/bin/dnstt-server /usr/local/bin/dnstt-client

echo ""
echo -e "\033[32mDNSTT uninstalled successfully!\033[0m"
EOF
    chmod +x /usr/local/bin/dnstt-uninstall
    
    # Background runner script
    cat > /usr/local/bin/dnstt-bg <<'EOF'
#!/bin/bash
# Run DNSTT in background with nohup

NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null)

if [[ -z "$NS_DOMAIN" ]]; then
    echo "Error: DNSTT not configured"
    exit 1
fi

# Kill existing
pkill -f "dnstt-server" 2>/dev/null

# Run in background
cd /etc/dnstt
nohup /usr/local/bin/dnstt-server -mtu 512 -udp :5300 -privkey-file private.key ${NS_DOMAIN} 127.0.0.1:22 >> /var/log/dnstt.log 2>&1 &

echo "DNSTT started in background (PID: $!)"
echo "Logs: tail -f /var/log/dnstt.log"
EOF
    chmod +x /usr/local/bin/dnstt-bg
    
    print_info "Management scripts created"
}

# ============================================================
# 10. VERIFY DNS RECORDS
# ============================================================
verify_dns() {
    print_step "Verifying DNS records..."
    
    NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null)
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    
    echo ""
    print_info "Please add these DNS records at your registrar:"
    echo ""
    echo -e "  ${GREEN}A Record:${NC}    ${NS_DOMAIN} → ${SERVER_IP}"
    echo -e "  ${GREEN}NS Record:${NC}   ${NS_DOMAIN} → ${NS_DOMAIN}"
    echo ""
    
    # Check if DNS resolves
    print_step "Checking DNS resolution..."
    if nslookup "$NS_DOMAIN" 8.8.8.8 2>/dev/null | grep -q "Address:"; then
        NS_IP=$(nslookup "$NS_DOMAIN" 8.8.8.8 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        if [[ "$NS_IP" == "$SERVER_IP" ]]; then
            print_info "DNS records are correctly configured ✓"
        else
            print_warning "NS domain resolves to $NS_IP, but server IP is $SERVER_IP"
            print_warning "Please update your DNS records"
        fi
    else
        print_warning "DNS records not yet propagating (this is normal, wait a few minutes)"
        print_info "You can check later with: nslookup $NS_DOMAIN"
    fi
    
    echo ""
}

# ============================================================
# 11. DISPLAY SUMMARY
# ============================================================
display_summary() {
    NS_DOMAIN=$(cat /root/nsdomain 2>/dev/null)
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    PUBKEY=$(cat /etc/dnstt/private.pub 2>/dev/null)
    
    clear
    echo ""
    print_header "✅ DNSTT INSTALLATION COMPLETE"
    echo ""
    
    echo -e "${CYAN}📡 SERVER INFORMATION:${NC}"
    echo -e "${PURPLE}─────────────────────────────────────────────────${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server IP" "$SERVER_IP"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "NS Domain" "$NS_DOMAIN"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "DNS Port" "5300 (UDP)"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "MTU" "512"
    echo ""
    
    echo -e "${CYAN}🔑 PUBLIC KEY (Copy for clients):${NC}"
    echo -e "${PURPLE}─────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}${PUBKEY}${NC}"
    echo ""
    
    echo -e "${CYAN}📁 SERVICE INFORMATION:${NC}"
    echo -e "${PURPLE}─────────────────────────────────────────────────${NC}"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Service" "dnstt"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Config Dir" "/etc/dnstt"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Log File" "/var/log/dnstt.log"
    printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Status" "$(systemctl is-active dnstt)"
    echo ""
    
    echo -e "${CYAN}📋 COMMANDS:${NC}"
    echo -e "${PURPLE}─────────────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Check status:${NC}   dnstt-status"
    echo -e "  ${WHITE}Restart:${NC}        dnstt-restart"
    echo -e "  ${WHITE}View logs:${NC}      tail -f /var/log/dnstt.log"
    echo -e "  ${WHITE}Client info:${NC}    dnstt-client"
    echo -e "  ${WHITE}Background run:${NC} dnstt-bg"
    echo -e "  ${WHITE}Uninstall:${NC}      dnstt-uninstall"
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✨ Installation completed successfully!${NC}"
    echo ""
}

# ============================================================
# MAIN INSTALLATION
# ============================================================
main() {
    clear
    print_header "🔒 DNSTT SERVER INSTALLER"
    echo ""
    echo -e "${WHITE}Features:${NC}"
    echo -e "  • Auto domain detection"
    echo -e "  • Clean removal & reinstall support"
    echo -e "  • Private repo binary download"
    echo -e "  • Systemd service with auto-restart"
    echo -e "  • Management scripts"
    echo -e "  • Fail2ban compatible"
    echo ""
    
    # Run installation steps
    get_domain
    clean_remove
    install_packages
    download_binary
    generate_keys
    setup_iptables
    create_service
    start_service
    create_management_scripts
    verify_dns
    display_summary
}

# Run main
main "$@"