#!/bin/bash
# ============================================================
# nginx-setup.sh – Simple Reverse Proxy for Xray WS/gRPC
# No stream multiplexing – SSH/SSL via Stunnel original ports
# ============================================================

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARNING${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}SUCCESS${NC} ] $1"; }

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${BLUE}          NGINX REVERSE PROXY FOR XRAY WS/GRPC           ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${GREEN}            Ports 80 & 443 – No SNI Multiplexing         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# CONFIGURATION
# ============================================================
BACKUP_DIR="/root/nginx-backup-$(date +%Y%m%d_%H%M%S)"
DOMAIN_FILE="/root/domain"

# ============================================================
# DETECT OS
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

# ============================================================
# BACKUP EXISTING CONFIG
# ============================================================
backup_config() {
    print_info "Backing up existing configuration to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    if [ -d /etc/nginx ]; then
        cp /etc/nginx/nginx.conf "$BACKUP_DIR/" 2>/dev/null || true
        [ -d /etc/nginx/conf.d ] && cp -r /etc/nginx/conf.d "$BACKUP_DIR/conf.d" 2>/dev/null || true
        print_success "Backup completed"
    else
        print_info "No existing Nginx config to backup"
    fi
}

# ============================================================
# INSTALL NGINX (clean removal, install nginx-full)
# ============================================================
install_nginx() {
    print_info "Removing any existing Nginx packages..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true

    apt remove --purge -y nginx nginx-common nginx-full nginx-extras nginx-mod-stream libnginx-mod-stream 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    rm -rf /etc/nginx /var/log/nginx /var/cache/nginx 2>/dev/null || true

    print_info "Installing nginx-full (and libnginx-mod-stream for future compatibility)..."
    apt update -y 2>/dev/null
    apt install -y nginx-full libnginx-mod-stream 2>/dev/null || {
        print_error "Failed to install required packages. Exiting."
        exit 1
    }

    mkdir -p /etc/nginx/conf.d /var/log/nginx /etc/nginx/modules-enabled

    # Create fallback mime.types if missing
    if [ ! -f /etc/nginx/mime.types ]; then
        print_warn "mime.types not found, creating fallback..."
        cat > /etc/nginx/mime.types <<'MIME'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/json                      json;
    text/plain                            txt;
    image/png                             png;
    image/svg+xml                         svg svgz;
    image/x-icon                          ico;
    application/zip                       zip;
    application/octet-stream              bin exe dll;
    audio/mpeg                            mp3;
    video/mp4                             mp4;
    application/pdf                       pdf;
    application/msword                    doc;
    application/vnd.ms-excel              xls;
    application/vnd.ms-powerpoint         ppt;
    application/xhtml+xml                 xhtml;
}
MIME
    fi

    print_success "nginx installed"
}

# ============================================================
# CREATE MAIN NGINX.CONF (no stream block)
# ============================================================
create_main_config() {
    print_info "Creating main nginx.conf..."
    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
    gzip on;
    client_max_body_size 32M;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    proxy_buffering off;
    include /etc/nginx/conf.d/*.conf;
}
EOF
    print_success "Main nginx.conf created"
}

# ============================================================
# CREATE REVERSE PROXY CONFIG (Xray WS/gRPC only)
# ============================================================
create_reverse_proxy_config() {
    print_info "Creating reverse proxy configuration for Xray..."
    mkdir -p /home/vps/public_html

    cat > /home/vps/public_html/index.html <<'EOF'
<!DOCTYPE html><html><head><title>VPN Server</title></head>
<body><h1>🚀 VPN Server Online</h1><p>All services operational.</p></body></html>
EOF

    cat > /etc/nginx/conf.d/reverse-proxy.conf <<'NGINX'
upstream xray_vless_ws { server 127.0.0.1:14016; }
upstream xray_vmess_ws { server 127.0.0.1:23456; }
upstream xray_trojan_ws { server 127.0.0.1:25432; }
upstream xray_ss_ws { server 127.0.0.1:30300; }
upstream xray_vless_grpc { server 127.0.0.1:24456; }
upstream xray_vmess_grpc { server 127.0.0.1:31234; }
upstream xray_trojan_grpc { server 127.0.0.1:33456; }
upstream xray_ss_grpc { server 127.0.0.1:30310; }

server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /home/vps/public_html;

    location = / {
        index index.html;
    }
    location /status {
        return 200 '{"status":"online"}';
        add_header Content-Type application/json;
    }

    location = /vmess {
        proxy_pass http://xray_vmess_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    location = /vless {
        proxy_pass http://xray_vless_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    location = /trojan-ws {
        proxy_pass http://xray_trojan_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    location = /ss-ws {
        proxy_pass http://xray_ss_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;
    root /home/vps/public_html;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location = / {
        index index.html;
    }
    location /status {
        return 200 '{"status":"online","ssl":true}';
        add_header Content-Type application/json;
    }

    location = /vmess {
        proxy_pass http://xray_vmess_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location = /vless {
        proxy_pass http://xray_vless_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location = /trojan-ws {
        proxy_pass http://xray_trojan_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location = /ss-ws {
        proxy_pass http://xray_ss_ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /vless-grpc { grpc_pass grpc://xray_vless_grpc; grpc_set_header X-Real-IP $remote_addr; }
    location /vmess-grpc { grpc_pass grpc://xray_vmess_grpc; grpc_set_header X-Real-IP $remote_addr; }
    location /trojan-grpc { grpc_pass grpc://xray_trojan_grpc; grpc_set_header X-Real-IP $remote_addr; }
    location /ss-grpc { grpc_pass grpc://xray_ss_grpc; grpc_set_header X-Real-IP $remote_addr; }

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX

    print_success "Reverse proxy configuration created"
}

# ============================================================
# REMOVE OLD CONFLICTING CONFIGS
# ============================================================
clean_old_configs() {
    print_info "Removing old configuration files..."
    rm -f /etc/nginx/conf.d/xray.conf /etc/nginx/conf.d/xray.conf.bak 2>/dev/null
    rm -f /etc/nginx/conf.d/reverse-proxy.conf.bak 2>/dev/null
    # Remove any stream.d directory left from previous attempts
    rm -rf /etc/nginx/stream.d 2>/dev/null
    print_success "Old configurations cleaned"
}

# ============================================================
# STOP CONFLICTING SERVICES
# ============================================================
stop_conflicting_services() {
    print_info "Stopping services that may conflict with ports 80/443..."
    systemctl stop apache2 2>/dev/null || true
    systemctl stop haproxy 2>/dev/null || true
    # Do NOT stop stunnel4 – it now uses its own ports (8443-8445)
    print_success "Conflicting services stopped"
}

# ============================================================
# TEST AND APPLY
# ============================================================
test_and_apply() {
    print_info "Testing Nginx configuration..."
    if nginx -t 2>&1; then
        print_success "Configuration test passed"
        systemctl restart nginx 2>/dev/null || systemctl start nginx 2>/dev/null
        sleep 2
        if systemctl is-active --quiet nginx; then
            print_success "Nginx is running"
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

rollback_config() {
    print_warn "Rolling back..."
    [ -f "$BACKUP_DIR/nginx.conf" ] && cp "$BACKUP_DIR/nginx.conf" /etc/nginx/nginx.conf
    [ -d "$BACKUP_DIR/conf.d" ] && rm -rf /etc/nginx/conf.d/* && cp -r "$BACKUP_DIR/conf.d/"* /etc/nginx/conf.d/ 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
    print_info "Rollback completed"
}

# ============================================================
# MANAGEMENT SCRIPT
# ============================================================
create_management_script() {
    cat > /usr/local/bin/nginx-proxy <<'NGINXMGMT'
#!/bin/bash
GREEN='\033[0;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
show_status() {
    echo "═══════════════════════════════════════════════"
    echo "  NGINX REVERSE PROXY STATUS"
    echo "═══════════════════════════════════════════════"
    systemctl is-active --quiet nginx && echo -e " Status: ${GREEN}● Running${NC}" || echo -e " Status: ${RED}● Not Running${NC}"
    echo ""
    echo " Active Listeners:"
    ss -tlnp 2>/dev/null | grep nginx | while read line; do
        port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
        echo -e "   ${YELLOW}→ Port $port${NC}"
    done
}
show_routes() {
    echo "═══════════════════════════════════════════════"
    echo "  ROUTING TABLE"
    echo "═══════════════════════════════════════════════"
    echo " Port 80 (HTTP):"
    echo "   ├── /vmess   → Xray VMess WS"
    echo "   ├── /vless   → Xray VLESS WS"
    echo "   ├── /trojan-ws → Xray Trojan WS"
    echo "   └── /ss-ws   → Xray Shadowsocks WS"
    echo " Port 443 (HTTPS):"
    echo "   ├── /vmess   → Xray VMess WS (TLS)"
    echo "   ├── /vless   → Xray VLESS WS (TLS)"
    echo "   ├── /vless-grpc → Xray VLESS gRPC"
    echo "   ├── /vmess-grpc → Xray VMess gRPC"
    echo "   ├── /trojan-grpc → Xray Trojan gRPC"
    echo "   └── /ss-grpc → Xray SS gRPC"
}
case "$1" in
    status) show_status ;;
    routes) show_routes ;;
    restart) nginx -t && systemctl restart nginx && echo "Done!" ;;
    reload) nginx -t && systemctl reload nginx && echo "Done!" ;;
    test) nginx -t ;;
    logs) tail -f /var/log/nginx/access.log ;;
    errors) tail -f /var/log/nginx/error.log ;;
    *) echo "Usage: nginx-proxy {status|routes|restart|reload|test|logs|errors}" ;;
esac
NGINXMGMT
    chmod +x /usr/local/bin/nginx-proxy
    print_success "Management script created: nginx-proxy"
}

# ============================================================
# CONNECTION GUIDE
# ============================================================
show_connection_guide() {
    local ip=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              XRAY CONNECTION GUIDE (Ports 80 & 443)        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   Xray VMess WS (NTLS) : $ip:80/vmess"
    echo -e "   Xray VMess WS (TLS)  : $ip:443/vmess"
    echo -e "   VLESS WS (NTLS)      : $ip:80/vless"
    echo -e "   VLESS WS (TLS)       : $ip:443/vless"
    echo -e "   Trojan WS (NTLS)     : $ip:80/trojan-ws"
    echo -e "   Trojan WS (TLS)      : $ip:443/trojan-ws"
    echo -e "   VLESS gRPC           : $ip:443/vless-grpc"
    echo -e "   VMess gRPC           : $ip:443/vmess-grpc"
    echo -e "   Trojan gRPC          : $ip:443/trojan-grpc"
    echo -e "   SS gRPC              : $ip:443/ss-grpc"
    echo ""
    echo -e "   SSH/Dropbear/Stunnel use their original ports (22, 109, 143, 8443-8445)"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    show_banner
    detect_os

    backup_config
    install_nginx
    clean_old_configs
    create_main_config
    create_reverse_proxy_config
    create_management_script

    stop_conflicting_services
    test_and_apply

    systemctl enable nginx 2>/dev/null || true
    show_connection_guide | tee /root/nginx-proxy-guide.txt

    echo ""
    print_success "Nginx reverse proxy setup complete!"
    print_info "Guide saved to /root/nginx-proxy-guide.txt"
    print_info "Management: nginx-proxy {status|routes|restart|reload|test|logs}"
}

main "$@"