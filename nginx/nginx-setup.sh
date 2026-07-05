#!/bin/bash
# ============================================================
# nginx-reverse-proxy.sh – Unified Reverse Proxy with Stream Module
# Routes all traffic through ports 80 & 443 to backend services
# NO PORT CONFLICTS - Everything goes through Nginx
# ============================================================

set -e

# ============================================================
# COLOR DEFINITIONS
# ============================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARNING${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}SUCCESS${NC} ] $1"; }
print_header() { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"; }

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${BLUE}          UNIFIED NGINX REVERSE PROXY CONFIGURATOR        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${GREEN}        All Services Through Ports 80 & 443 Only          ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# CONFIGURATION VARIABLES
# ============================================================
BACKUP_DIR="/root/nginx-backup-$(date +%Y%m%d_%H%M%S)"
DOMAIN_FILE="/root/domain"

# Backend Ports (all internal, no public exposure)
declare -A BACKENDS=(
    # Xray Services
    ["xray_vless_ws"]="14016"
    ["xray_vmess_ws"]="23456"
    ["xray_trojan_ws"]="25432"
    ["xray_ss_ws"]="30300"
    ["xray_vless_grpc"]="24456"
    ["xray_vmess_grpc"]="31234"
    ["xray_trojan_grpc"]="33456"
    ["xray_ss_grpc"]="30310"
    ["xray_api"]="10085"
    
    # SSH Services
    ["ssh_direct"]="22"
    ["ssh_dropbear"]="109"
    ["ssh_dropbear_alt"]="143"
    ["ssh_ssl"]="8443"
    ["ssh_ssl_alt"]="8444"
    
    # WebSocket Services
    ["ws_ssh"]="8080"
    ["ws_ssl"]="700"
    ["ws_dropbear"]="2095"
    
    # Proxy Services
    ["squid_3128"]="3128"
    ["squid_8082"]="8082"
    ["squid_8888"]="8888"
    
    # VPN Services
    ["openvpn"]="1194"
    ["badvpn_7100"]="7100"
    ["badvpn_7200"]="7200"
    ["badvpn_7300"]="7300"
    ["badvpn_7400"]="7400"
)

# ============================================================
# DETECT OS & INSTALL NGINX
# ============================================================
detect_os() {
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

install_nginx_full() {
    print_header
    print_info "Installing Nginx with Stream module..."
    
    # Remove Apache if present
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
    apt remove --purge apache2 -y 2>/dev/null || true
    
    # Install Nginx with all modules
    apt update -y 2>/dev/null
    apt install -y nginx nginx-extras nginx-mod-stream 2>/dev/null || {
        # Fallback for older versions
        apt install -y nginx-full 2>/dev/null || apt install -y nginx 2>/dev/null
    }
    
    # Verify stream module is available
    if ! nginx -V 2>&1 | grep -q "stream"; then
        print_error "Nginx stream module not available. Installing nginx-full..."
        apt install -y nginx-full 2>/dev/null
    fi
    
    print_success "Nginx installed with Stream module"
}

# ============================================================
# BACKUP EXISTING CONFIG
# ============================================================
backup_config() {
    print_info "Backing up existing configuration to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    cp /etc/nginx/nginx.conf "$BACKUP_DIR/" 2>/dev/null || true
    [ -d /etc/nginx/conf.d ] && cp -r /etc/nginx/conf.d "$BACKUP_DIR/conf.d" 2>/dev/null || true
    [ -d /etc/nginx/stream.d ] && cp -r /etc/nginx/stream.d "$BACKUP_DIR/stream.d" 2>/dev/null || true
    [ -d /etc/nginx/sites-enabled ] && cp -r /etc/nginx/sites-enabled "$BACKUP_DIR/sites-enabled" 2>/dev/null || true
    
    print_success "Backup completed"
}

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    local domain=""
    domain=$(cat "$DOMAIN_FILE" 2>/dev/null || cat /root/domain.txt 2>/dev/null || echo "")
    domain=$(echo "$domain" | tr -d '[:space:]')
    
    if [[ -z "$domain" ]]; then
        if [ -f /etc/xray/xray.crt ]; then
            domain=$(openssl x509 -in /etc/xray/xray.crt -subject -noout 2>/dev/null | sed 's/.*CN = //' | sed 's/\/.*//')
        fi
    fi
    
    if [[ -z "$domain" ]]; then
        domain=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
        print_warn "No domain found. Using IP: $domain"
    fi
    
    echo "$domain"
}

# ============================================================
# CREATE STREAM CONFIGURATIONS (Layer 4 - TCP/UDP)
# ============================================================
create_stream_config() {
    local domain=$1
    print_header
    print_info "Creating Layer 4 Stream configurations..."
    
    mkdir -p /etc/nginx/stream.d
    
    # Main stream configuration for port 443
    # This handles SSL/TLS connections and routes based on SNI or protocol
    cat > /etc/nginx/stream.d/ssl-inbound.conf <<EOF
# ============================================================
# SSL/TLS Stream Proxy - Port 443
# Routes to different backends based on SNI or direct protocol
# ============================================================

# SNI-based routing map
map \$ssl_preread_server_name \$ssl_backend {
    hostnames;
    default                         127.0.0.1:8443;  # Default SSH SSL
    
    # Xray domains go to Xray WS
    $domain                          127.0.0.1:8443;  # Your domain → SSH SSL
    *.${domain}                      127.0.0.1:8443;  # Wildcard → SSH SSL
}

# SSL TCP Proxy Server
server {
    listen 443;
    listen [::]:443;
    
    ssl_preread on;
    proxy_pass \$ssl_backend;
    proxy_protocol on;
    
    # Connection settings
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
    
    # Logging
    access_log /var/log/nginx/stream-ssl-access.log;
    error_log  /var/log/nginx/stream-ssl-error.log;
}

# Alternative SSH SSL port
server {
    listen 8443;
    listen [::]:8443;
    
    proxy_pass 127.0.0.1:${BACKENDS[ssh_direct]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
    
    access_log off;
}
EOF

    # Non-SSL stream for port 80 (SSH direct, Dropbear, etc.)
    cat > /etc/nginx/stream.d/tcp-inbound.conf <<EOF
# ============================================================
# TCP Stream Proxy - Non-SSL Services
# ============================================================

# SSH Direct on port 22
server {
    listen 22;
    listen [::]:22;
    
    proxy_pass 127.0.0.1:${BACKENDS[ssh_direct]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
    
    access_log /var/log/nginx/stream-ssh.log;
}

# Dropbear on port 109
server {
    listen 109;
    listen [::]:109;
    
    proxy_pass 127.0.0.1:${BACKENDS[ssh_dropbear]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
}

# Dropbear on port 143
server {
    listen 143;
    listen [::]:143;
    
    proxy_pass 127.0.0.1:${BACKENDS[ssh_dropbear_alt]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
}
EOF

    # Proxy services (Squid)
    cat > /etc/nginx/stream.d/proxy-inbound.conf <<EOF
# ============================================================
# Proxy Services Stream
# ============================================================

# Squid Proxy on port 3128
server {
    listen 3128;
    listen [::]:3128;
    
    proxy_pass 127.0.0.1:${BACKENDS[squid_3128]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
}

# Squid Proxy on port 8082
server {
    listen 8082;
    listen [::]:8082;
    
    proxy_pass 127.0.0.1:${BACKENDS[squid_8082]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
}

# Squid Proxy on port 8888
server {
    listen 8888;
    listen [::]:8888;
    
    proxy_pass 127.0.0.1:${BACKENDS[squid_8888]};
    proxy_connect_timeout 30s;
    proxy_timeout 300s;
}
EOF

    print_success "Stream configurations created"
}

# ============================================================
# CREATE HTTP CONFIGURATIONS (Layer 7 - HTTP/HTTPS/WebSocket)
# ============================================================
create_http_config() {
    local domain=$1
    print_header
    print_info "Creating Layer 7 HTTP configurations..."
    
    mkdir -p /etc/nginx/conf.d /home/vps/public_html
    
    # Create index page
    cat > /home/vps/public_html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Server</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #0a0a1a 0%, #1a1a3e 50%, #0a0a1a 100%);
            color: #e0e0e0;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .container {
            background: rgba(255,255,255,0.05);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 90%;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.1);
        }
        h1 {
            text-align: center;
            color: #00b0ff;
            margin-bottom: 30px;
            font-size: 2em;
        }
        .status-badge {
            text-align: center;
            margin-bottom: 30px;
        }
        .online {
            display: inline-block;
            background: rgba(0,255,136,0.1);
            color: #00ff88;
            padding: 10px 25px;
            border-radius: 25px;
            border: 1px solid rgba(0,255,136,0.3);
        }
        .pulse {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #00ff88;
            border-radius: 50%;
            margin-right: 10px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.3; }
        }
        .service-list {
            display: grid;
            gap: 15px;
        }
        .service-item {
            background: rgba(255,255,255,0.03);
            padding: 15px;
            border-radius: 10px;
            border: 1px solid rgba(255,255,255,0.05);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .service-name { color: #b0b0ff; }
        .service-port { color: #ffd700; font-family: monospace; }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 VPN Server</h1>
        <div class="status-badge">
            <span class="online"><span class="pulse"></span>Server Online</span>
        </div>
        <div class="service-list">
            <div class="service-item">
                <span class="service-name">SSH Direct</span>
                <span class="service-port">Port 22, 80</span>
            </div>
            <div class="service-item">
                <span class="service-name">SSH + SSL</span>
                <span class="service-port">Port 443 (SNI)</span>
            </div>
            <div class="service-item">
                <span class="service-name">SSH + WebSocket</span>
                <span class="service-port">Port 80 (WS)</span>
            </div>
            <div class="service-item">
                <span class="service-name">SSH + WS + SSL</span>
                <span class="service-port">Port 443 (WSS)</span>
            </div>
            <div class="service-item">
                <span class="service-name">Dropbear</span>
                <span class="service-port">Port 109, 143</span>
            </div>
            <div class="service-item">
                <span class="service-name">Xray VMess/VLESS</span>
                <span class="service-port">Port 80, 443</span>
            </div>
            <div class="service-item">
                <span class="service-name">Squid Proxy</span>
                <span class="service-port">Port 3128, 8082, 8888</span>
            </div>
        </div>
        <div class="footer">
            <p>Powered by Nginx Reverse Proxy</p>
        </div>
    </div>
</body>
</html>
EOF

    # Main HTTP/HTTPS configuration
    cat > /etc/nginx/conf.d/reverse-proxy.conf <<'NGINX'
# ============================================================
# HTTP/HTTPS Reverse Proxy - Layer 7
# Handles WebSocket, gRPC, and HTTP traffic
# ============================================================

# Upstream definitions
upstream xray_vless_ws {
    server 127.0.0.1:BACKEND_XRAY_VLESS_WS;
}

upstream xray_vmess_ws {
    server 127.0.0.1:BACKEND_XRAY_VMESS_WS;
}

upstream xray_trojan_ws {
    server 127.0.0.1:BACKEND_XRAY_TROJAN_WS;
}

upstream xray_ss_ws {
    server 127.0.0.1:BACKEND_XRAY_SS_WS;
}

upstream xray_vless_grpc {
    server 127.0.0.1:BACKEND_XRAY_VLESS_GRPC;
}

upstream xray_vmess_grpc {
    server 127.0.0.1:BACKEND_XRAY_VMESS_GRPC;
}

upstream xray_trojan_grpc {
    server 127.0.0.1:BACKEND_XRAY_TROJAN_GRPC;
}

upstream xray_ss_grpc {
    server 127.0.0.1:BACKEND_XRAY_SS_GRPC;
}

upstream ws_ssh_backend {
    server 127.0.0.1:BACKEND_WS_SSH;
}

upstream ws_ssl_backend {
    server 127.0.0.1:BACKEND_WS_SSL;
}

upstream ws_dropbear_backend {
    server 127.0.0.1:BACKEND_WS_DROPBEAR;
}

# ============================================================
# HTTP Port 80 - WebSocket & Non-TLS Services
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /home/vps/public_html;
    
    # Increase timeouts for WebSocket
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    
    # Status page
    location = / {
        index index.html;
    }
    
    # API status endpoint
    location /status {
        return 200 '{"status":"online","timestamp":"$time_iso8601","connections":$connections_active}';
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
    }
    
    # ============================================================
    # Xray WebSocket Paths (Non-TLS)
    # ============================================================
    location = /vmess {
        proxy_pass http://xray_vmess_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location = /vless {
        proxy_pass http://xray_vless_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    location = /trojan-ws {
        proxy_pass http://xray_trojan_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    location = /ss-ws {
        proxy_pass http://xray_ss_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # ============================================================
    # SSH WebSocket Path
    # ============================================================
    location /ssh-ws {
        proxy_pass http://ws_ssh_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # ============================================================
    # Default - Dropbear WebSocket or Status
    # ============================================================
    location / {
        # Try WebSocket upgrade first
        if ($http_upgrade = "websocket") {
            proxy_pass http://ws_dropbear_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
        }
        # Fallback to static files
        try_files $uri $uri/ =404;
    }
}

# ============================================================
# HTTPS Port 443 - TLS WebSocket & gRPC Services
# ============================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;
    root /home/vps/public_html;
    
    # SSL Configuration
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Increase timeouts
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    
    # ============================================================
    # Xray WebSocket Paths (TLS)
    # ============================================================
    location = /vmess {
        proxy_pass http://xray_vmess_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    
    location = /vless {
        proxy_pass http://xray_vless_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    
    location = /trojan-ws {
        proxy_pass http://xray_trojan_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    
    location = /ss-ws {
        proxy_pass http://xray_ss_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    
    # ============================================================
    # Xray gRPC Paths
    # ============================================================
    location /vless-grpc {
        grpc_pass grpc://xray_vless_grpc;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
    }
    
    location /vmess-grpc {
        grpc_pass grpc://xray_vmess_grpc;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
    }
    
    location /trojan-grpc {
        grpc_pass grpc://xray_trojan_grpc;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
    }
    
    location /ss-grpc {
        grpc_pass grpc://xray_ss_grpc;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
    }
    
    # ============================================================
    # SSH WebSocket over SSL
    # ============================================================
    location /ssh-ws-ssl {
        proxy_pass http://ws_ssl_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    
    # ============================================================
    # Default SSL path
    # ============================================================
    location / {
        if ($http_upgrade = "websocket") {
            proxy_pass http://ws_ssl_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
        }
        try_files $uri $uri/ =404;
    }
}

# ============================================================
# Status Page on Port 81
# ============================================================
server {
    listen 127.0.0.1:81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
    
    location /nginx-status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
NGINX

    # Replace backend ports in config
    sed -i "s/BACKEND_XRAY_VLESS_WS/${BACKENDS[xray_vless_ws]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_VMESS_WS/${BACKENDS[xray_vmess_ws]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_TROJAN_WS/${BACKENDS[xray_trojan_ws]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_SS_WS/${BACKENDS[xray_ss_ws]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_VLESS_GRPC/${BACKENDS[xray_vless_grpc]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_VMESS_GRPC/${BACKENDS[xray_vmess_grpc]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_TROJAN_GRPC/${BACKENDS[xray_trojan_grpc]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_XRAY_SS_GRPC/${BACKENDS[xray_ss_grpc]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_WS_SSH/${BACKENDS[ws_ssh]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_WS_SSL/${BACKENDS[ws_ssl]}/g" /etc/nginx/conf.d/reverse-proxy.conf
    sed -i "s/BACKEND_WS_DROPBEAR/${BACKENDS[ws_dropbear]}/g" /etc/nginx/conf.d/reverse-proxy.conf

    print_success "HTTP reverse proxy configuration created"
}

# ============================================================
# CREATE MAIN NGINX.CONF
# ============================================================
create_main_config() {
    print_info "Creating main nginx.conf..."
    
    cat > /etc/nginx/nginx.conf <<'EOF'
# ============================================================
# Main Nginx Configuration
# Worker processes auto-detected
# ============================================================
user www-data;
worker_processes auto;
pid /run/nginx.pid;

# Load modules
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

# Stream module for TCP/UDP proxy (Layer 4)
stream {
    # Stream logging
    log_format proxy '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time "$upstream_addr" '
                     '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';
    
    access_log /var/log/nginx/stream-access.log proxy;
    error_log  /var/log/nginx/stream-error.log;
    
    # Include stream configurations
    include /etc/nginx/stream.d/*.conf;
}

# HTTP module for WebSocket and HTTP (Layer 7)
http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    server_names_hash_bucket_size 128;

    # MIME
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;

    # Security
    client_max_body_size 32M;
    client_body_buffer_size 128k;

    # Proxy Settings (Global)
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    proxy_buffering off;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 8k;

    # Include all HTTP configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    print_success "Main nginx.conf created"
}

# ============================================================
# CONFIGURE BACKEND SERVICES FOR INTERNAL-ONLY LISTENING
# ============================================================
configure_backend_services() {
    print_header
    print_info "Configuring backend services for internal listening..."
    
    # Move SSH from port 80 (if configured)
    if grep -q "Port 80" /etc/ssh/sshd_config 2>/dev/null; then
        print_warn "SSH is configured on port 80. Removing to avoid conflict..."
        sed -i '/^Port 80/d' /etc/ssh/sshd_config
        systemctl restart ssh 2>/dev/null || true
    fi
    
    # Configure Stunnel to listen internally
    if [ -f /etc/stunnel/stunnel.conf ]; then
        print_info "Configuring Stunnel for internal routing..."
        # Stunnel stays on its ports, Nginx will proxy to them
    fi
    
    # Configure Dropbear for internal only
    if [ -f /etc/default/dropbear ]; then
        print_info "Configuring Dropbear..."
        # Dropbear stays on 109, 143 - Nginx will proxy
    fi
    
    print_success "Backend services configured"
}

# ============================================================
# TEST AND APPLY CONFIGURATION
# ============================================================
test_and_apply() {
    print_header
    print_info "Testing Nginx configuration..."
    
    if nginx -t 2>&1; then
        print_success "Configuration test passed"
        
        print_info "Applying configuration..."
        systemctl restart nginx 2>/dev/null || systemctl start nginx 2>/dev/null
        
        sleep 3
        if systemctl is-active --quiet nginx; then
            print_success "Nginx is running with new configuration"
            
            # Show listening ports
            print_info "Listening ports:"
            ss -tlnp | grep nginx | awk '{print "   " $4}' | sort -u
        else
            print_error "Nginx failed to start. Rolling back..."
            rollback_config
            exit 1
        fi
    else
        print_error "Configuration test failed!"
        rollback_config
        exit 1
    fi
}

# ============================================================
# ROLLBACK FUNCTION
# ============================================================
rollback_config() {
    print_warn "Rolling back to previous configuration..."
    
    if [ -f "$BACKUP_DIR/nginx.conf" ]; then
        cp "$BACKUP_DIR/nginx.conf" /etc/nginx/nginx.conf
    fi
    
    if [ -d "$BACKUP_DIR/conf.d" ]; then
        rm -rf /etc/nginx/conf.d/*
        cp -r "$BACKUP_DIR/conf.d/"* /etc/nginx/conf.d/ 2>/dev/null || true
    fi
    
    if [ -d "$BACKUP_DIR/stream.d" ]; then
        rm -rf /etc/nginx/stream.d/*
        cp -r "$BACKUP_DIR/stream.d/"* /etc/nginx/stream.d/ 2>/dev/null || true
    fi
    
    systemctl restart nginx 2>/dev/null || true
    print_info "Rollback completed"
}

# ============================================================
# CREATE MANAGEMENT SCRIPT
# ============================================================
create_management_script() {
    cat > /usr/local/bin/nginx-proxy <<'NGINXMGMT'
#!/bin/bash
# Nginx Reverse Proxy Management Script

GREEN='\033[0;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_status() {
    echo "═══════════════════════════════════════════════════════════════"
    echo "   NGINX REVERSE PROXY STATUS"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if systemctl is-active --quiet nginx; then
        echo -e "   Status: ${GREEN}● Running${NC}"
    else
        echo -e "   Status: ${RED}● Not Running${NC}"
    fi
    
    echo ""
    echo "   Active Listeners:"
    ss -tlnp 2>/dev/null | grep nginx | while read line; do
        port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
        echo -e "   ${YELLOW}→ Port $port${NC}"
    done
    
    echo ""
    echo "   Active Connections:"
    ss -tnp 2>/dev/null | grep nginx | wc -l | xargs echo "   Total:"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

show_routes() {
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ROUTING TABLE"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "   Port 80 (HTTP):"
    echo "   ├── /vmess        → Xray VMess WS"
    echo "   ├── /vless        → Xray VLESS WS"
    echo "   ├── /trojan-ws    → Xray Trojan WS"
    echo "   ├── /ss-ws        → Xray Shadowsocks WS"
    echo "   ├── /ssh-ws       → SSH WebSocket"
    echo "   └── /             → Dropbear WS / Status Page"
    echo ""
    echo "   Port 443 (HTTPS):"
    echo "   ├── /vmess        → Xray VMess WS (TLS)"
    echo "   ├── /vless        → Xray VLESS WS (TLS)"
    echo "   ├── /trojan-ws    → Xray Trojan WS (TLS)"
    echo "   ├── /ss-ws        → Xray Shadowsocks WS (TLS)"
    echo "   ├── /vless-grpc   → Xray VLESS gRPC"
    echo "   ├── /vmess-grpc   → Xray VMess gRPC"
    echo "   ├── /trojan-grpc  → Xray Trojan gRPC"
    echo "   ├── /ss-grpc      → Xray Shadowsocks gRPC"
    echo "   ├── /ssh-ws-ssl   → SSH WebSocket SSL"
    echo "   └── /             → SSL WS Proxy"
    echo ""
    echo "   Stream (TCP):"
    echo "   ├── Port 22       → SSH Direct"
    echo "   ├── Port 109      → Dropbear"
    echo "   ├── Port 143      → Dropbear Alt"
    echo "   ├── Port 3128     → Squid Proxy"
    echo "   ├── Port 8082     → Squid Proxy"
    echo "   └── Port 8888     → Squid Proxy"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

case "$1" in
    status)
        show_status
        ;;
    routes)
        show_routes
        ;;
    restart)
        echo "Restarting Nginx..."
        nginx -t && systemctl restart nginx && echo "Done!"
        ;;
    reload)
        echo "Reloading Nginx..."
        nginx -t && systemctl reload nginx && echo "Done!"
        ;;
    test)
        nginx -t
        ;;
    logs)
        tail -f /var/log/nginx/access.log
        ;;
    errors)
        tail -f /var/log/nginx/error.log
        ;;
    stream-logs)
        tail -f /var/log/nginx/stream-access.log
        ;;
    *)
        echo "Usage: nginx-proxy {status|routes|restart|reload|test|logs|errors|stream-logs}"
        echo ""
        echo "  status       - Show proxy status and listeners"
        echo "  routes       - Show routing table"
        echo "  restart      - Restart Nginx (with config test)"
        echo "  reload       - Reload Nginx (graceful)"
        echo "  test         - Test configuration"
        echo "  logs         - View HTTP access logs"
        echo "  errors       - View error logs"
        echo "  stream-logs  - View TCP stream logs"
        exit 1
        ;;
esac
NGINXMGMT
    
    chmod +x /usr/local/bin/nginx-proxy
    print_success "Management script created: nginx-proxy"
}

# ============================================================
# SHOW CONNECTION GUIDE
# ============================================================
show_connection_guide() {
    local ip=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    
    print_header
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              CONNECTION GUIDE (ALL PORT 80 & 443)           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${YELLOW}Server IP:${NC} $ip"
    echo ""
    echo -e "   ${CYAN}SSH Connections:${NC}"
    echo -e "   ├── SSH Direct           : $ip:22"
    echo -e "   ├── SSH + SSL            : $ip:443 (SSL/TLS)"
    echo -e "   ├── SSH + WebSocket      : ws://$ip:80/ssh-ws"
    echo -e "   ├── SSH + WS + SSL       : wss://$ip:443/ssh-ws-ssl"
    echo -e "   ├── Dropbear             : $ip:109"
    echo -e "   └── Dropbear Alt         : $ip:143"
    echo ""
    echo -e "   ${CYAN}Xray/V2Ray Connections:${NC}"
    echo -e "   ├── VMess WS (NTLS)      : $ip:80/vmess"
    echo -e "   ├── VMess WS (TLS)       : $ip:443/vmess"
    echo -e "   ├── VLESS WS (NTLS)      : $ip:80/vless"
    echo -e "   ├── VLESS WS (TLS)       : $ip:443/vless"
    echo -e "   ├── Trojan WS (NTLS)     : $ip:80/trojan-ws"
    echo -e "   ├── Trojan WS (TLS)      : $ip:443/trojan-ws"
    echo -e "   ├── VLESS gRPC           : $ip:443/vless-grpc"
    echo -e "   ├── VMess gRPC           : $ip:443/vmess-grpc"
    echo -e "   ├── Trojan gRPC          : $ip:443/trojan-grpc"
    echo -e "   └── SS gRPC              : $ip:443/ss-grpc"
    echo ""
    echo -e "   ${CYAN}Proxy Connections:${NC}"
    echo -e "   ├── Squid HTTP           : $ip:3128"
    echo -e "   ├── Squid HTTP           : $ip:8082"
    echo -e "   └── Squid HTTP           : $ip:8888"
    echo ""
    echo -e "   ${GREEN}Management:${NC}"
    echo -e "   └── nginx-proxy status   : Check proxy status"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

# ============================================================
# MAIN
# ============================================================
main() {
    show_banner
    
    detect_os
    
    # Get domain
    local domain=$(get_domain)
    print_info "Domain/IP: $domain"
    
    # Install Nginx if needed
    if ! command -v nginx &>/dev/null; then
        install_nginx_full
    else
        print_info "Nginx already installed"
        
        # Check for stream module
        if ! nginx -V 2>&1 | grep -q "stream"; then
            print_warn "Stream module not found. Reinstalling..."
            apt install -y nginx-full 2>/dev/null || apt install --reinstall -y nginx-extras 2>/dev/null
        fi
    fi
    
    # Backup existing config
    backup_config
    
    # Create configurations
    configure_backend_services
    create_main_config
    create_stream_config "$domain"
    create_http_config "$domain"
    
    # Create management script
    create_management_script
    
    # Test and apply
    test_and_apply
    
    # Enable on boot
    systemctl enable nginx 2>/dev/null || true
    
    # Show connection guide
    show_connection_guide
    
    # Save guide to file
    show_connection_guide > /root/nginx-proxy-guide.txt
    
    echo ""
    print_success "Nginx reverse proxy setup complete!"
    print_info "Guide saved to: /root/nginx-proxy-guide.txt"
    print_info "Management: nginx-proxy {status|routes|restart|reload|test|logs}"
    echo ""
}

main "$@"