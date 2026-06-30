#!/bin/bash
# ============================================================
# ENHANCED SSH WEBSOCKET + PROXY INSTALLER
# Compatible with Debian & Ubuntu
#
# Features:
#   - WebSocket SSH (ws-dropbear, ws-stunnel)
#   - Separate HTTP Proxy (Squid) for payload
#   - Independent service management
#   - No conflicts with Xray/V2Ray
#   - Full protocol support: SSH Direct, SSL, WS, WSS, Payload
# ============================================================

set -e

# ============================================================
# COLOR DEFINITIONS
# ============================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success(){ echo -e "${BLUE}[SUCCESS]${NC} $1"; }

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi
    log_info "Detected OS: $OS"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "This script only supports Ubuntu or Debian"
        exit 1
    fi
}

# ============================================================
# INSTALL WEBSOCKET SSH (ws-dropbear, ws-stunnel)
# ============================================================
install_websocket_ssh() {
    log_info "Installing WebSocket SSH (ws-dropbear, ws-stunnel)..."

    # Ensure Python is installed
    apt-get install -y python3 python3-pip 2>/dev/null || {
        log_warn "Python3 installation failed, continuing..."
    }

    # Create python symlink for Debian
    if [[ "$OS" == "debian" ]]; then
        if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
            ln -s /usr/bin/python3 /usr/bin/python
            log_info "Created python symlink for Debian"
        fi
    fi

    # Download binaries from your repository
    wget -q -O /usr/local/bin/ws-dropbear \
        "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/ws-dropbear"
    wget -q -O /usr/local/bin/ws-stunnel \
        "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/ws-stunnel"

    chmod +x /usr/local/bin/ws-dropbear
    chmod +x /usr/local/bin/ws-stunnel

    # Fix shebang for both OS - use /usr/bin/env python3
    sed -i '1{/^#!/d}' /usr/local/bin/ws-stunnel 2>/dev/null
    sed -i '1{/^#!/d}' /usr/local/bin/ws-dropbear 2>/dev/null
    sed -i '1i#!/usr/bin/env python3' /usr/local/bin/ws-stunnel
    sed -i '1i#!/usr/bin/env python3' /usr/local/bin/ws-dropbear

    # Systemd service for ws-dropbear (port 2095 - SSH over WebSocket)
    cat > /etc/systemd/system/ws-dropbear.service <<-END
[Unit]
Description=Websocket-Dropbear (SSH over WS)
Documentation=https://github.com/XTLS/Xray-install
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/env python3 /usr/local/bin/ws-dropbear 2095
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
END

    # Systemd service for ws-stunnel (port 700 - SSH over WSS)
    cat > /etc/systemd/system/ws-stunnel.service <<-END
[Unit]
Description=SSH Over Websocket-SSL (WSS)
Documentation=https://github.com/XTLS/Xray-install
After=network.target nss-lookup.target stunnel4.service

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/env python3 /usr/local/bin/ws-stunnel 700
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
END

    # Reload and enable services
    systemctl daemon-reload
    systemctl enable ws-dropbear.service
    systemctl enable ws-stunnel.service

    # Start services
    systemctl stop ws-dropbear.service 2>/dev/null; sleep 1
    systemctl start ws-dropbear.service
    systemctl stop ws-stunnel.service 2>/dev/null; sleep 1
    systemctl start ws-stunnel.service

    # Verify services
    echo ""
    log_info "Checking WebSocket services..."

    if systemctl is-active --quiet ws-dropbear.service; then
        log_success "ws-dropbear (port 2095) running"
    else
        log_warn "ws-dropbear failed to start - checking logs..."
        journalctl -u ws-dropbear.service -n 5 --no-pager
    fi

    if systemctl is-active --quiet ws-stunnel.service; then
        log_success "ws-stunnel (port 700) running"
    else
        log_warn "ws-stunnel failed to start - checking logs..."
        journalctl -u ws-stunnel.service -n 5 --no-pager
    fi
}

# ============================================================
# INSTALL SQUID PROXY (SEPARATE - FOR PAYLOAD)
# ============================================================
install_squid_proxy() {
    log_info "Installing Squid HTTP Proxy (for payload support)..."

    apt install -y squid 2>/dev/null || {
        log_warn "Squid installation failed"
        return 1
    }

    # Backup existing config
    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

    # Configure Squid with multiple ports
    cat > /etc/squid/squid.conf <<'EOF'
# ============================================================
# SQUID HTTP PROXY - FOR PAYLOAD / REMOTE PROXY
# ============================================================

# Multiple ports for flexibility
http_port 3128
http_port 8082
http_port 8888

# Allow all connections
acl all src 0.0.0.0/0
http_access allow all

# Cache settings
cache_dir ufs /var/spool/squid 100 16 256
cache_mem 64 MB
maximum_object_size_in_memory 32 KB
maximum_object_size 1024 MB

# Privacy settings (hide client IP)
forwarded_for off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all

# Performance
visible_hostname localhost
dns_nameservers 8.8.8.8 1.1.1.1
connect_timeout 30 seconds
read_timeout 15 minutes
request_timeout 5 minutes

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF

    # Create cache directory
    mkdir -p /var/spool/squid
    chown -R proxy:proxy /var/spool/squid 2>/dev/null || true
    squid -z >> /dev/null 2>&1 || true

    # Restart Squid
    systemctl stop squid >> /dev/null 2>&1
    systemctl start squid >> /dev/null 2>&1 || {
        log_error "Failed to start Squid"
        return 1
    }
    systemctl enable squid >> /dev/null 2>&1

    if systemctl is-active --quiet squid; then
        log_success "Squid proxy running on ports 3128, 8082, 8888"
    else
        log_error "Squid failed to start"
        journalctl -u squid -n 5 --no-pager
        return 1
    fi
}

# ============================================================
# CREATE MANAGEMENT SCRIPTS
# ============================================================
create_management_scripts() {
    log_info "Creating management scripts..."

    # WebSocket proxy management
    cat > /usr/local/bin/wsproxy <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status)
        systemctl $1 ws-dropbear
        systemctl $1 ws-stunnel
        ;;
    start-ws)
        systemctl start ws-dropbear
        ;;
    stop-ws)
        systemctl stop ws-dropbear
        ;;
    start-wss)
        systemctl start ws-stunnel
        ;;
    stop-wss)
        systemctl stop ws-stunnel
        ;;
    logs)
        journalctl -u ws-dropbear -f
        ;;
    logs-wss)
        journalctl -u ws-stunnel -f
        ;;
    kill)
        fuser -k 2095/tcp 2>/dev/null
        fuser -k 700/tcp 2>/dev/null
        echo "WebSocket ports (2095, 700) killed"
        ;;
    *)
        echo "Usage: wsproxy {start|stop|restart|status|logs|kill|start-ws|stop-ws|start-wss|stop-wss|logs-wss}"
        echo ""
        echo "  start     - Start both WebSocket services"
        echo "  stop      - Stop both WebSocket services"
        echo "  restart   - Restart both WebSocket services"
        echo "  status    - Check both WebSocket services"
        echo "  logs      - View ws-dropbear logs"
        echo "  logs-wss  - View ws-stunnel logs"
        echo "  kill      - Kill WebSocket ports"
        echo "  start-ws  - Start ws-dropbear only"
        echo "  stop-ws   - Stop ws-dropbear only"
        echo "  start-wss - Start ws-stunnel only"
        echo "  stop-wss  - Stop ws-stunnel only"
        ;;
esac
EOF
    chmod +x /usr/local/bin/wsproxy

    # Proxy management (Squid)
    cat > /usr/local/bin/proxy <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status)
        systemctl $1 squid
        ;;
    logs)
        tail -f /var/log/squid/access.log
        ;;
    reload)
        squid -k reconfigure
        echo "Squid reloaded"
        ;;
    ports)
        echo "Squid listening on: 3128, 8082, 8888"
        ss -tulpn | grep squid
        ;;
    *)
        echo "Usage: proxy {start|stop|restart|status|logs|reload|ports}"
        echo ""
        echo "  start   - Start Squid proxy"
        echo "  stop    - Stop Squid proxy"
        echo "  restart - Restart Squid proxy"
        echo "  status  - Check Squid status"
        echo "  logs    - View Squid access logs"
        echo "  reload  - Reload Squid config"
        echo "  ports   - Show listening ports"
        ;;
esac
EOF
    chmod +x /usr/local/bin/proxy

    # Complete VPN status (including proxy)
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   SSH VPN + PROXY SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "=== SSH Services ==="
echo "SSH Server      : $(systemctl is-active ssh)   (22, 2222)"
echo "Dropbear        : $(systemctl is-active dropbear)   (109, 143)"
echo "Stunnel4        : $(systemctl is-active stunnel4)   (222, 777)"
echo ""
echo "=== WebSocket Services ==="
echo "ws-dropbear     : $(systemctl is-active ws-dropbear)   (2095)"
echo "ws-stunnel      : $(systemctl is-active ws-stunnel)   (700)"
echo ""
echo "=== Proxy Services ==="
echo "Squid Proxy     : $(systemctl is-active squid)   (3128, 8082, 8888)"
echo ""
echo "=== Other Services ==="
echo "Fail2ban        : $(systemctl is-active fail2ban)"
echo "BADVPN          : $(pgrep -c badvpn-udpgw || echo 0) instances (7100-7400)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Commands:"
echo "  menu         - Original menu"
echo "  create       - Create SSH user"
echo "  wsproxy      - Manage WebSocket services"
echo "  proxy        - Manage Squid proxy"
echo "  vpn-status   - Show this status"
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/vpn-status

    log_success "Management scripts created"
}

# ============================================================
# CREATE CONNECTION GUIDE
# ============================================================
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")
    
    cat > /root/ssh-ws-proxy-guide.txt <<EOF
===========================================
   SSH VPN + PROXY CONNECTION GUIDE
===========================================

VPS IP: $VPS_IP

===========================================
1. SSH DIRECT
===========================================
   ssh -p 22 root@$VPS_IP
   ssh -p 2222 root@$VPS_IP

===========================================
2. SSH OVER SSL (Stunnel4)
===========================================
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:222 -quiet" root@$VPS_IP
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:777 -quiet" root@$VPS_IP

===========================================
3. SSH OVER WEBSOCKET (ws-dropbear)
===========================================
   ssh -o ProxyCommand="websocat ws://$VPS_IP:2095" root@$VPS_IP

===========================================
4. SSH OVER WEBSOCKET + SSL (ws-stunnel)
===========================================
   ssh -o ProxyCommand="websocat wss://$VPS_IP:700" root@$VPS_IP

===========================================
5. SSH + PAYLOAD + REMOTE PROXY (HTTP Injector / KPN)
===========================================
   Proxy: HTTP
   Proxy Host: $VPS_IP
   Proxy Port: 3128 (or 8082, 8888)
   SSH Host: $VPS_IP
   SSH Port: 22 (or 2222)
   Payload: custom (client-side)

===========================================
6. SSH + SSL + PAYLOAD + REMOTE PROXY
===========================================
   SSH Host: $VPS_IP
   SSH Port: 222 (or 777)
   SSL: ON
   Proxy: HTTP $VPS_IP:3128
   Payload: custom (client-side)

===========================================
MANAGEMENT
===========================================
   menu         - Original menu
   create       - Create SSH user
   wsproxy      - Manage WebSocket services
   proxy        - Manage Squid proxy
   vpn-status   - Check all services

===========================================
SERVICE PORTS
===========================================
   SSH Direct  : 22, 2222
   SSH SSL     : 222, 777 (Stunnel4)
   SSH WS      : 2095 (ws-dropbear)
   SSH WSS     : 700 (ws-stunnel)
   HTTP Proxy  : 3128, 8082, 8888 (Squid)
   Dropbear    : 109, 143
   BADVPN      : 7100-7400
===========================================
EOF

    log_success "Connection guide saved to /root/ssh-ws-proxy-guide.txt"
}

# ============================================================
# SETUP FIREWALL (Allow all SSH + Proxy ports)
# ============================================================
setup_firewall() {
    log_info "Configuring firewall..."

    if command -v ufw &>/dev/null; then
        # SSH ports
        for port in 22 2222 109 143 222 777; do
            ufw allow ${port}/tcp >> /dev/null 2>&1
        done

        # WebSocket ports
        for port in 2095 700; do
            ufw allow ${port}/tcp >> /dev/null 2>&1
        done

        # Proxy ports
        for port in 3128 8082 8888; do
            ufw allow ${port}/tcp >> /dev/null 2>&1
        done

        # BADVPN ports
        for port in 7100 7200 7300 7400; do
            ufw allow ${port}/tcp >> /dev/null 2>&1
        done

        # Xray ports (if installed, preserve them)
        for port in 80 443 81 10085; do
            if ss -tuln | grep -q ":$port "; then
                ufw allow ${port}/tcp >> /dev/null 2>&1
            fi
        done

        ufw --force enable >> /dev/null 2>&1
        log_success "UFW configured"
    else
        log_warn "UFW not installed, skipping firewall configuration"
    fi
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo ""
    echo "==========================================="
    echo "   SSH WEBSOCKET + PROXY INSTALLER"
    echo "   (Xray/V2Ray Compatible)"
    echo "==========================================="
    echo ""
    echo "This will install:"
    echo "  ✅ SSH WebSocket (ws-dropbear)   - port 2095"
    echo "  ✅ SSH WebSocket SSL (ws-stunnel) - port 700"
    echo "  ✅ HTTP Proxy (Squid)            - port 3128, 8082, 8888"
    echo ""
    echo "All ports are non-conflicting with Xray/V2Ray"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    log_info "Starting SSH WebSocket + Proxy installation..."

    detect_os
    install_websocket_ssh
    install_squid_proxy
    create_management_scripts
    create_guide
    setup_firewall

    echo ""
    echo "==========================================="
    echo "   ✅ INSTALLATION COMPLETE!"
    echo "==========================================="
    echo ""
    echo "📡 Services installed:"
    echo "   SSH WebSocket    : 2095 (ws-dropbear)"
    echo "   SSH WSS          : 700 (ws-stunnel)"
    echo "   HTTP Proxy       : 3128, 8082, 8888 (Squid)"
    echo ""
    echo "🔧 Management commands:"
    echo "   wsproxy   - Manage WebSocket services"
    echo "   proxy     - Manage Squid proxy"
    echo "   vpn-status - Check all services"
    echo ""
    echo "📖 Full guide: /root/ssh-ws-proxy-guide.txt"
    echo "==========================================="
    echo ""

    log_success "SSH WebSocket + Proxy installation completed successfully!"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"