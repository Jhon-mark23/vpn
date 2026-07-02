#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER - XRAY COMPATIBLE
# (Using centralised certificate from create-cert.sh)
# Protocols:
#   - SSH Direct (22, 2222) - Xray safe
#   - SSH+SSL (8443, 8444) - Xray uses 443
#   - SSH+WS (8080, 8082) - Xray safe
#   - SSH+WSS (8445) - Xray safe
#   - SSH+Payload+Proxy (3128, 8082, 8888) - Xray safe
#   - SSH+SSL+Payload+Proxy (8443 + 3128)
# ============================================================

# Suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# ============================================================
# COLOR DEFINITIONS
# ============================================================
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
NC='\e[0m'

print_info()  { echo -e "[ ${green}INFO${NC} ] $1"; }
print_error() { echo -e "[ ${red}ERROR${NC} ] $1"; }
print_warning(){ echo -e "[ ${yell}WARNING${NC} ] $1"; }
print_success(){ echo -e "[ ${blue}SUCCESS${NC} ] $1"; }

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
# SETUP ENVIRONMENT
# ============================================================
setup_environment() {
    ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
    timedatectl set-timezone Asia/Manila 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
}

# ============================================================
# INSTALL BASE PACKAGES
# ============================================================
install_base_packages() {
    print_info "Installing base packages..."

    apt update -y || true
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true

    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true

    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates nginx stunnel4 dropbear squid fail2ban"

    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt install -y $pkg -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || {
                print_warning "Failed to install $pkg, continuing..."
            }
        fi
    done

    # Install Node.js for WebSocket proxy
    if ! command -v node &>/dev/null; then
        print_info "Installing Node.js 20 LTS..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> /dev/null 2>&1
        apt install -y nodejs >> /dev/null 2>&1 || true
    fi

    print_success "Base packages installed"
}

# ============================================================
# SETUP RC.LOCAL
# ============================================================
setup_rclocal() {
    print_info "Setting up rc.local..."

    cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
END

    cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
# By default this script does nothing.
exit 0
END

    chmod +x /etc/rc.local
    systemctl enable rc-local 2>/dev/null || true
    systemctl start rc-local.service 2>/dev/null || true

    if ! grep -q "disable_ipv6" /etc/rc.local; then
        sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
    fi

    print_success "rc.local configured"
}

# ============================================================
# PROTOCOL 1: SSH DIRECT (Ports 22, 2222)
# ============================================================
configure_ssh() {
    print_info "Configuring SSH Direct (ports 22, 2222 - Xray safe)..."

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
    if ! grep -q "^Port 2222" /etc/ssh/sshd_config; then
        echo "Port 2222" >> /etc/ssh/sshd_config
    fi

    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

    echo "MarcScript SSH VPN Server (Xray Compatible)" > /etc/ssh/ssh_banner
    if ! grep -q "Banner" /etc/ssh/sshd_config; then
        echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
    fi

    sshd -t >> /dev/null 2>&1 || {
        print_error "SSH config test failed"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        exit 1
    }

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl enable ssh 2>/dev/null || true

    print_success "SSH Direct on ports 22, 2222"
}

# ============================================================
# PROTOCOL 2: SSH+SSL (Stunnel4 on Ports 8443, 8444)
# ============================================================
configure_stunnel() {
    print_info "Configuring SSH+SSL (ports 8443, 8444 - Xray safe)..."

    # Ensure the certificate has been created by the central script
    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        print_warning "Unified certificate not found in /etc/stunnel/stunnel.pem"
        if [ -f /usr/local/bin/create-cert.sh ]; then
            print_info "Running create-cert.sh to generate the certificate..."
            /usr/local/bin/create-cert.sh
        else
            print_error "create-cert.sh not found. Please run create-cert.sh first."
            exit 1
        fi
    fi

    apt install -y stunnel4 2>/dev/null

    mkdir -p /var/log/stunnel4
    mkdir -p /etc/stunnel
    mkdir -p /var/run/stunnel4

    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi

    chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4

    # The unified PEM (cert + key) already exists from create-cert.sh
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true

    cat > /etc/stunnel/stunnel.conf <<'EOF'
; Stunnel4 Config - Xray Compatible
; Xray uses 443, so we use 8443 and 8444
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
pid = /var/run/stunnel4/stunnel4.pid
debug = 3
sslVersion = TLSv1.2

[ssh-ssl]
accept = 8443
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ssh-ssl-alt]
accept = 8444
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ws-ssl]
accept = 8445
connect = 127.0.0.1:8080
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
EOF

    echo 'ENABLED=1' > /etc/default/stunnel4

    mkdir -p /etc/systemd/system/stunnel4.service.d/
    cat > /etc/systemd/system/stunnel4.service.d/override.conf <<-EOF
[Service]
RuntimeDirectory=stunnel4
RuntimeDirectoryMode=0755
ExecStartPre=/bin/mkdir -p /var/run/stunnel4
ExecStartPre=/bin/chown stunnel4:stunnel4 /var/run/stunnel4
EOF

    systemctl daemon-reload
    systemctl enable stunnel4 2>/dev/null || true
    systemctl stop stunnel4 2>/dev/null; sleep 1
    systemctl start stunnel4 2>/dev/null || true

    print_success "SSH+SSL on ports 8443, 8444"
}

# ============================================================
# PROTOCOL 3: SSH+WS (WebSocket on Ports 8080, 8082)
# ============================================================
configure_websocket() {
    print_info "Configuring SSH+WS (ports 8080, 8082 - Xray safe)..."

    fuser -k 8080/tcp 2>/dev/null || true
    mkdir -p /opt/ws-proxy

    cat > /opt/ws-proxy/ws-proxy.js <<'EOF'
#!/usr/bin/env node
const net = require('net');
const http = require('http');
const fs = require('fs');

const SSH_HOST = '127.0.0.1';
const SSH_PORT = 22;
const WS_PORT = 8080;
const LOG_FILE = '/var/log/ws-proxy.log';

function log(msg) {
    const ts = new Date().toISOString();
    const line = `[${ts}] ${msg}\n`;
    console.log(line.trim());
    fs.appendFileSync(LOG_FILE, line, { flag: 'a' });
}

log('Starting SSH WebSocket Proxy...');
const server = http.createServer();

server.on('connect', (req, socket) => {
    log(`CONNECT: ${req.url}`);
    const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
        socket.write('HTTP/1.1 200 Connection Established\r\nProxy-Agent: MarcScript\r\n\r\n');
        ssh.pipe(socket);
        socket.pipe(ssh);
    });
    ssh.on('error', (e) => { log(`SSH error: ${e.message}`); socket.destroy(); });
    socket.on('error', (e) => { log(`Socket error: ${e.message}`); ssh.destroy(); });
});

server.on('upgrade', (req, socket) => {
    log(`WebSocket upgrade: ${req.headers.host}`);
    const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
        socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n');
        ssh.pipe(socket);
        socket.pipe(ssh);
    });
    ssh.on('error', (e) => { log(`WS SSH error: ${e.message}`); socket.destroy(); });
});

server.on('request', (req, res) => {
    if (req.url === '/' || req.url === '/status') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<html><head><title>SSH WebSocket Proxy</title></head>
            <body><h1>🚀 SSH WebSocket Proxy</h1><p>Status: Running</p>
            <p>Uptime: ${Math.floor(process.uptime())} s</p>
            <p>SSH: ${SSH_HOST}:${SSH_PORT}</p>
            <hr><small>MarcScript SSH VPN Proxy</small></body></html>`);
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen(WS_PORT, '0.0.0.0', () => log(`✅ WebSocket proxy on port ${WS_PORT}`));

process.on('SIGTERM', () => { log('SIGTERM, shutting down...'); server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { log('SIGINT, shutting down...');  server.close(() => process.exit(0)); });
process.on('uncaughtException', (e) => log(`Uncaught: ${e.message}`));
EOF

    chmod +x /opt/ws-proxy/ws-proxy.js

    cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node /opt/ws-proxy/ws-proxy.js
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ws-proxy 2>/dev/null || true
    systemctl start ws-proxy 2>/dev/null || true

    sleep 3
    if systemctl is-active --quiet ws-proxy; then
        print_success "SSH+WS on port 8080"
    else
        print_warning "WebSocket proxy failed on port 8080, trying 8082..."
        sed -i 's/WS_PORT = 8080;/WS_PORT = 8082;/' /opt/ws-proxy/ws-proxy.js
        systemctl restart ws-proxy
        if systemctl is-active --quiet ws-proxy; then
            print_success "SSH+WS on port 8082"
        else
            print_error "WebSocket proxy failed on all ports"
        fi
    fi
}

# ============================================================
# PROTOCOL 4: SSH+WSS (Port 8445 via Stunnel)
# ============================================================
# Already configured in Stunnel config above ([ws-ssl] on 8445)

# ============================================================
# PROTOCOL 5 & 6: SSH+Payload+Proxy (Squid on 3128, 8082, 8888)
# ============================================================
configure_squid() {
    print_info "Configuring SSH+Payload+Proxy (ports 3128, 8082, 8888 - Xray safe)..."

    apt install -y squid 2>/dev/null

    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

    cat > /etc/squid/squid.conf <<'EOF'
http_port 3128
http_port 8082
http_port 8888

acl all src 0.0.0.0/0
http_access allow all

cache_dir ufs /var/spool/squid 100 16 256
cache_mem 64 MB
maximum_object_size_in_memory 32 KB
maximum_object_size 1024 MB

forwarded_for off
request_header_access X-Forwarded-For deny all
visible_hostname localhost
dns_nameservers 8.8.8.8 1.1.1.1
EOF

    mkdir -p /var/spool/squid
    chown -R proxy:proxy /var/spool/squid 2>/dev/null || true
    squid -z >> /dev/null 2>&1 || true

    systemctl stop squid >> /dev/null 2>&1
    systemctl start squid >> /dev/null 2>&1 || {
        print_error "Failed to start Squid"
    }
    systemctl enable squid >> /dev/null 2>&1

    print_success "SSH+Payload+Proxy on ports 3128, 8082, 8888"
}

# ============================================================
# INSTALL DROPBEAR (Alternative SSH on 109, 143)
# ============================================================
install_dropbear() {
    print_info "Installing Dropbear (ports 109, 143 - Xray safe)..."

    apt install -y dropbear 2>/dev/null

    cat > /etc/default/dropbear <<-DROPBEAR
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR

    echo "/bin/false" >> /etc/shells 2>/dev/null || true
    echo "/usr/sbin/nologin" >> /etc/shells 2>/dev/null || true

    systemctl enable dropbear 2>/dev/null || true
    systemctl restart dropbear 2>/dev/null || true

    print_success "Dropbear on ports 109, 143"
}

# ============================================================
# INSTALL BADVPN (UDP Gateway on 7100-7400)
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN UDP gateway (7100-7400 - Xray safe)..."

    cd /tmp
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/newudpgw"
    chmod +x /usr/bin/badvpn-udpgw

    for port in 7100 7200 7300 7400; do
        if ! grep -q "badvpn$((port/100))" /etc/rc.local; then
            sed -i "\$ i\screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50" /etc/rc.local
        fi
    done

    screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50 2>/dev/null || true

    print_success "BADVPN on ports 7100-7400"
}

# ============================================================
# INSTALL FAIL2BAN
# ============================================================
install_fail2ban() {
    print_info "Installing Fail2ban..."

    apt install -y fail2ban 2>/dev/null

    cat > /etc/fail2ban/jail.local <<-F2B
[DEFAULT]
findtime  = 600
bantime   = 3600
maxretry  = 5
backend   = polling

[sshd]
enabled   = true
port      = ssh,2222,8443,8444,8445,8080,8082
logpath   = %(sshd_log)s
maxretry  = 5
F2B

    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true

    print_success "Fail2ban configured"
}

# ============================================================
# SYSTEM OPTIMIZATION
# ============================================================
optimize_system() {
    print_info "Optimizing system..."

    cat >> /etc/sysctl.conf <<-SYSCTL

# === MARCSCRIPT VPS OPTIMIZATION ===
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 51200
SYSCTL
    sysctl -p >/dev/null 2>&1

    if [ ! -f /swapfile ]; then
        print_info "Creating 512MB swap..."
        fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Swap created"
    fi

    print_success "System optimized"
}

# ============================================================
# BLOCK TORRENT
# ============================================================
block_torrent() {
    print_info "Blocking torrent traffic..."

    iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "torrent" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "announce" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP 2>/dev/null || true

    iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    fi

    print_success "Torrent traffic blocked"
}

# ============================================================
# CONFIGURE NGINX (Minimal - no conflict with Xray)
# ============================================================
configure_nginx() {
    print_info "Configuring Nginx (minimal - Xray compatible)..."

    apt install -y nginx 2>/dev/null

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes 1;
pid /var/run/nginx.pid;

events {
    multi_accept on;
    worker_connections 1024;
}

http {
    gzip on;
    gzip_vary on;
    gzip_comp_level 5;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    client_max_body_size 32M;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

    mkdir -p /home/vps/public_html
    mkdir -p /etc/nginx/conf.d

    # Status page on port 81 (Xray uses 80/443)
    cat > /etc/nginx/conf.d/status.conf <<'EOF'
server {
    listen 81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
}

server {
    listen 8081;
    server_name _;
    root /home/vps/public_html;
    
    location / {
        return 200 "MarcScript SSH VPN Server (Xray Compatible)\nPorts: 22, 2222, 8443, 8444, 8445, 8080, 8082, 3128, 8082, 8888\n";
        add_header Content-Type text/plain;
    }
}
EOF

    nginx -t >> /dev/null 2>&1 || {
        print_error "Nginx config test failed"
    }

    systemctl restart nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true

    print_success "Nginx configured on ports 81, 8081"
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."

    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin

    # Menu scripts
    wget -q -O menu "$GHBASE/menu/menu.sh" && chmod +x menu
    wget -q -O m-sshovpn "$GHBASE/menu/m-sshovpn.sh" && chmod +x m-sshovpn
    wget -q -O m-vmess "$GHBASE/menu/m-vmess.sh" && chmod +x m-vmess
    wget -q -O m-vless "$GHBASE/menu/m-vless.sh" && chmod +x m-vless
    wget -q -O m-trojan "$GHBASE/menu/m-trojan.sh" && chmod +x m-trojan
    wget -q -O m-ssws "$GHBASE/menu/m-ssws.sh" && chmod +x m-ssws
    wget -q -O m-system "$GHBASE/menu/m-system.sh" && chmod +x m-system
    wget -q -O running "$GHBASE/menu/running.sh" && chmod +x running
    wget -q -O clearcache "$GHBASE/menu/clearcache.sh" && chmod +x clearcache

    # SSH scripts
    wget -q -O usernew "$GHBASE/ssh/usernew.sh" && chmod +x usernew
    wget -q -O trial "$GHBASE/ssh/trial.sh" && chmod +x trial
    wget -q -O renew "$GHBASE/ssh/renew.sh" && chmod +x renew
    wget -q -O hapus "$GHBASE/ssh/hapus.sh" && chmod +x hapus
    wget -q -O cek "$GHBASE/ssh/cek.sh" && chmod +x cek
    wget -q -O member "$GHBASE/ssh/member.sh" && chmod +x member
    wget -q -O delete "$GHBASE/ssh/delete.sh" && chmod +x delete
    wget -q -O autokill "$GHBASE/ssh/autokill.sh" && chmod +x autokill
    wget -q -O ceklim "$GHBASE/ssh/ceklim.sh" && chmod +x ceklim
    wget -q -O tendang "$GHBASE/ssh/tendang.sh" && chmod +x tendang
    wget -q -O sshws "$GHBASE/ssh/sshws.sh" && chmod +x sshws
    wget -q -O add-host "$GHBASE/ssh/add-host.sh" && chmod +x add-host
    wget -q -O xp "$GHBASE/ssh/xp.sh" && chmod +x xp
    wget -q -O speedtest "$GHBASE/ssh/speedtest_cli.py" && chmod +x speedtest

    cd /
    print_success "Management scripts downloaded"
}

# ============================================================
# CREATE VPN STATUS
# ============================================================
create_vpn_status() {
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT SSH VPN SERVICE STATUS (Xray Compatible)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "━━━ SSH DIRECT ━━━"
echo "SSH Server      : $(systemctl is-active ssh)   (22, 2222)"
echo ""
echo "━━━ SSH+SSL ━━━"
echo "Stunnel4        : $(systemctl is-active stunnel4)   (8443, 8444, 8445)"
echo ""
echo "━━━ SSH+WS ━━━"
echo "WebSocket Proxy : $(systemctl is-active ws-proxy)   (8080/8082)"
echo ""
echo "━━━ SSH+WSS ━━━"
echo "Stunnel4 + WS   : 8445 (via Stunnel → ws-proxy:8080)"
echo ""
echo "━━━ SSH+Payload+Proxy ━━━"
echo "Squid Proxy     : $(systemctl is-active squid)   (3128, 8082, 8888)"
echo ""
echo "━━━ OTHER SERVICES ━━━"
echo "Dropbear        : $(systemctl is-active dropbear)   (109, 143)"
echo "Nginx           : $(systemctl is-active nginx)   (81, 8081)"
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
echo "  vpn-status   - Show this status"
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/vpn-status
    print_success "vpn-status created"
}

# ============================================================
# CREATE CONNECTION GUIDE
# ============================================================
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")

    cat > /root/ssh-connection-guide.txt <<EOF
===========================================
   MARCSCRIPT SSH VPN CONNECTION GUIDE
   (Xray/V2Ray Compatible)
===========================================

VPS IP: $VPS_IP

===========================================
PROTOCOL 1: SSH DIRECT
===========================================
   Port 22 or 2222
   ssh -p 22 root@$VPS_IP
   ssh -p 2222 root@$VPS_IP

===========================================
PROTOCOL 2: SSH+SSL (Stunnel4)
===========================================
   Port 8443 or 8444
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8443 -quiet" root@$VPS_IP
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8444 -quiet" root@$VPS_IP

===========================================
PROTOCOL 3: SSH+WS (WebSocket)
===========================================
   Port 8080 or 8082
   ssh -o ProxyCommand="websocat ws://$VPS_IP:8080" root@$VPS_IP
   ssh -o ProxyCommand="websocat ws://$VPS_IP:8082" root@$VPS_IP

===========================================
PROTOCOL 4: SSH+WSS (WebSocket + SSL)
===========================================
   Port 8445
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8445 -quiet" root@$VPS_IP

===========================================
PROTOCOL 5: SSH+Payload+Remote Proxy
===========================================
   SSH Host: $VPS_IP
   SSH Port: 22 or 2222
   Proxy: HTTP $VPS_IP:3128 (or 8082, 8888)
   Payload: custom headers (client-side)

===========================================
PROTOCOL 6: SSH+SSL+Payload+Remote Proxy
===========================================
   SSH Host: $VPS_IP
   SSH Port: 8443 or 8444
   SSL: ON
   Proxy: HTTP $VPS_IP:3128 (or 8082, 8888)
   Payload: custom headers (client-side)

===========================================
MANAGEMENT
===========================================
   menu         - Original menu
   create       - Create SSH user
   vpn-status   - Check service status

===========================================
XRAY COMPATIBILITY
===========================================
   ✅ No port conflicts with Xray/V2Ray
   ✅ Xray uses 80, 443, 81
   ✅ SSH uses 22, 2222, 8443, 8444, 8445, 8080, 8082
===========================================
EOF

    print_success "Connection guide saved to /root/ssh-connection-guide.txt"
}

# ============================================================
# SETUP CRON
# ============================================================
setup_cron() {
    print_info "Setting up cron jobs..."

    cat > /etc/cron.d/re_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
END

    echo "7" > /home/re_otm
    systemctl restart cron 2>/dev/null || true

    print_success "Cron jobs configured"
}

# ============================================================
# RESTART SERVICES
# ============================================================
restart_services() {
    print_info "Restarting all services..."

    for service in nginx cron ssh dropbear stunnel4 ws-proxy squid fail2ban rc-local; do
        systemctl restart $service 2>/dev/null && print_success "Restarted $service"
    done

    for port in 7100 7200 7300 7400; do
        screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    print_info "Cleaning up..."
    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    history -c
    echo "unset HISTFILE" >> /etc/profile
    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null
    print_success "Cleanup completed"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo ""
    echo "==========================================="
    echo "   MARCSCRIPT SSH VPN INSTALLER"
    echo "   Xray/V2Ray Compatible"
    echo "   (Uses centralised certificate)"
    echo "==========================================="
    echo ""
    echo "Protocols to be installed:"
    echo "  ✅ SSH Direct       : 22, 2222"
    echo "  ✅ SSH+SSL          : 8443, 8444"
    echo "  ✅ SSH+WS           : 8080, 8082"
    echo "  ✅ SSH+WSS          : 8445"
    echo "  ✅ SSH+Payload+Proxy: 3128, 8082, 8888"
    echo "  ✅ SSH+SSL+Payload  : 8443 + 3128"
    echo ""
    echo "⚠️  Xray uses: 80, 443, 81 - NO CONFLICT!"
    echo "⚠️  Certificate handled by create-cert.sh"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    detect_os
    setup_environment
    install_base_packages
    setup_rclocal
    configure_ssh
    configure_stunnel        # Now uses create-cert.sh automatically
    configure_websocket
    configure_squid
    install_dropbear
    install_badvpn
    configure_nginx
    install_fail2ban
    optimize_system
    block_torrent
    download_scripts
    create_vpn_status
    create_guide
    setup_cron
    restart_services
    cleanup

    clear
    echo ""
    echo "==========================================="
    echo "   ✅ SSH-VPN INSTALLATION COMPLETE!"
    echo "   (Xray/V2Ray Compatible)"
    echo "==========================================="
    echo ""
    echo "📡 CONNECTION METHODS:"
    echo "   SSH Direct     : 22, 2222"
    echo "   SSH+SSL        : 8443, 8444"
    echo "   SSH+WS         : 8080, 8082"
    echo "   SSH+WSS        : 8445"
    echo "   SSH+Payload    : 3128, 8082, 8888"
    echo "   Dropbear       : 109, 143"
    echo "   BADVPN         : 7100-7400"
    echo ""
    echo "📖 Full guide: /root/ssh-connection-guide.txt"
    echo ""
    echo "🔧 Management:"
    echo "   menu         - Original menu"
    echo "   create       - Create SSH user"
    echo "   vpn-status   - Check services"
    echo ""
    echo "⚠️  Xray uses: 80, 443, 81 (unchanged)"
    echo "✅  No port conflicts!"
    echo "==========================================="
    echo ""

    print_success "SSH-VPN installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"