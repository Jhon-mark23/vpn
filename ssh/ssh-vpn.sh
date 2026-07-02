#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER - XRAY COMPATIBLE
# (Centralised certificate + max client compatibility)
# ============================================================

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

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

setup_environment() {
    ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
    timedatectl set-timezone Asia/Manila 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
}

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

    if ! command -v node &>/dev/null; then
        print_info "Installing Node.js 20 LTS..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> /dev/null 2>&1
        apt install -y nodejs >> /dev/null 2>&1 || true
    fi
    print_success "Base packages installed"
}

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
# PROTOCOL 1: SSH with legacy algorithm support
# ============================================================
configure_ssh() {
    print_info "Configuring SSH (ports 22, 2222) with legacy algorithm support..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

    # Write a complete, safe config
    cat > /etc/ssh/sshd_config <<EOF
Port 22
Port 2222
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
PermitEmptyPasswords no
MaxAuthTries 5
MaxSessions 10
LoginGraceTime 60
ClientAliveInterval 60
ClientAliveCountMax 3
UseDNS no
PrintMotd no
X11Forwarding no
Banner /etc/ssh/ssh_banner
Subsystem sftp /usr/lib/openssh/sftp-server

# Allow older algorithms for maximum client compatibility
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
Ciphers +aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc
EOF

    echo "MarcScript SSH VPN Server (Xray Compatible)" > /etc/ssh/ssh_banner

    sshd -t >> /dev/null 2>&1 || {
        print_error "SSH config test failed"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        exit 1
    }

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl enable ssh 2>/dev/null || true
    print_success "SSH Direct on ports 22, 2222 (legacy algorithms enabled)"
}

# ============================================================
# PROTOCOL 2: SSH+SSL with maximum TLS compatibility
# ============================================================
configure_stunnel() {
    print_info "Configuring SSH+SSL (ports 8443, 8444, 8445) with broad TLS support..."

    # Ensure certificate exists
    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        if [ -f /usr/local/bin/create-cert.sh ]; then
            print_info "Running create-cert.sh..."
            /usr/local/bin/create-cert.sh
        else
            print_warning "create-cert.sh not found – generating self-signed fallback"
            mkdir -p /etc/ssl/vpn
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout /etc/ssl/vpn/privkey.pem \
                -out /etc/ssl/vpn/fullchain.pem \
                -subj "/C=PH/ST=Metro Manila/L=Manila/O=MarcScript/CN=$(hostname -I | awk '{print $1}')" 2>/dev/null
            cat /etc/ssl/vpn/fullchain.pem /etc/ssl/vpn/privkey.pem > /etc/stunnel/stunnel.pem
        fi
    fi

    apt install -y stunnel4 2>/dev/null
    mkdir -p /var/log/stunnel4 /etc/stunnel /var/run/stunnel4

    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi
    chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true

    # Stunnel config with maximum compatibility
    cat > /etc/stunnel/stunnel.conf <<'EOF'
; Stunnel4 Config – maximum client compatibility
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
pid = /var/run/stunnel4/stunnel4.pid
debug = 3

; Allow all TLS versions except SSLv2/SSLv3
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3

; Very broad cipher list for old Android and VPN apps
ciphers = DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4

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

    print_success "SSH+SSL on ports 8443, 8444, 8445 (TLS 1.0–1.3, broad ciphers)"
}

# ============================================================
# PROTOCOL 3: SSH+WS (Node.js WebSocket proxy)
# ============================================================
configure_websocket() {
    print_info "Configuring SSH+WS (ports 8080, 8082)..."
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
# PROTOCOL 4,5,6: Squid, Dropbear, BADVPN (unchanged)
# ============================================================
configure_squid() {
    print_info "Configuring Squid proxy (3128, 8082, 8888)..."
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
    systemctl start squid >> /dev/null 2>&1 || print_error "Failed to start Squid"
    systemctl enable squid >> /dev/null 2>&1
    print_success "Squid on ports 3128, 8082, 8888"
}

install_dropbear() {
    print_info "Installing Dropbear (109, 143)..."
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

install_badvpn() {
    print_info "Installing BADVPN UDP gateway (7100-7400)..."
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

optimize_system() {
    print_info "Optimizing system..."
    cat >> /etc/sysctl.conf <<-SYSCTL
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

configure_nginx() {
    print_info "Configuring Nginx (status pages)..."
    apt install -y nginx 2>/dev/null
    rm -f /etc/nginx/sites-enabled/default
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
    mkdir -p /home/vps/public_html /etc/nginx/conf.d
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
        return 200 "MarcScript SSH VPN Server (Xray Compatible)";
        add_header Content-Type text/plain;
    }
}
EOF
    nginx -t >> /dev/null 2>&1 || print_error "Nginx config test failed"
    systemctl restart nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    print_success "Nginx configured on ports 81, 8081"
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS (with CRLF fix)
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin

    # Helper to download and fix
    dl() {
        wget -q -O "$1" "$GHBASE/$2" && chmod +x "$1" && sed -i 's/\r$//' "$1"
    }

    dl menu menu/menu.sh
    dl m-sshovpn menu/m-sshovpn.sh
    dl m-vmess menu/m-vmess.sh
    dl m-vless menu/m-vless.sh
    dl m-trojan menu/m-trojan.sh
    dl m-ssws menu/m-ssws.sh
    dl m-system menu/m-system.sh
    dl running menu/running.sh
    dl clearcache menu/clearcache.sh

    dl usernew ssh/usernew.sh
    dl trial ssh/trial.sh
    dl renew ssh/renew.sh
    dl hapus ssh/hapus.sh
    dl cek ssh/cek.sh
    dl member ssh/member.sh
    dl delete ssh/delete.sh
    dl autokill ssh/autokill.sh
    dl ceklim ssh/ceklim.sh
    dl tendang ssh/tendang.sh
    dl sshws ssh/sshws.sh
    dl add-host ssh/add-host.sh
    dl xp ssh/xp.sh
    dl speedtest ssh/speedtest_cli.py

    cd /
    print_success "Management scripts downloaded (line endings fixed)"
}

# ============================================================
# VPN STATUS (dynamic WS detection)
# ============================================================
create_vpn_status() {
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
svc() { systemctl is-active --quiet "$1" && echo -e "\033[1;32m● Running\033[0m" || echo -e "\033[1;31m● Not Running\033[0m"; }
printf "%-28s : %s\n" "SSH (22, 2222)" "$(svc ssh)"
printf "%-28s : %s\n" "Dropbear (109, 143)" "$(svc dropbear)"
printf "%-28s : %s\n" "Stunnel4 (8443,8444,8445)" "$(svc stunnel4)"
printf "%-28s : %s\n" "Nginx (81, 8081)" "$(svc nginx)"
printf "%-28s : %s\n" "Squid Proxy (3128)" "$(svc squid)"
printf "%-28s : %s\n" "Fail2Ban" "$(svc fail2ban)"
[ -f /etc/systemd/system/ws-proxy.service ] && printf "%-28s : %s\n" "WS-Proxy (Node.js)" "$(svc ws-proxy)"
[ -f /etc/systemd/system/ws-dropbear.service ] && printf "%-28s : %s\n" "WS-Dropbear (2095)" "$(svc ws-dropbear)"
[ -f /etc/systemd/system/ws-stunnel.service ] && printf "%-28s : %s\n" "WS-Stunnel (700)" "$(svc ws-stunnel)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/vpn-status
    print_success "vpn-status created"
}

create_guide() {
    VPS_IP=$(curl -s ifconfig.me || echo "unknown")
    cat > /root/ssh-connection-guide.txt <<EOF
...
EOF
    print_success "Guide saved"
}

setup_cron() {
    print_info "Setting up cron (daily reboot)..."
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
# RESTART ALL SERVICES (including all possible WS)
# ============================================================
restart_services() {
    print_info "Restarting all services..."
    for svc in nginx cron ssh dropbear stunnel4 ws-proxy ws-dropbear ws-stunnel squid fail2ban; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            systemctl restart $svc 2>/dev/null && print_success "Restarted $svc"
        fi
    done
    for port in 7100 7200 7300 7400; do
        screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
}

cleanup() {
    print_info "Cleaning up..."
    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    history -c
    echo "unset HISTFILE" >> /etc/profile
    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null
    print_success "Cleanup completed"
}

main() {
    clear
    echo "==========================================="
    echo "   MARCSCRIPT SSH VPN INSTALLER"
    echo "   (Max client TLS compatibility)"
    echo "==========================================="
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 0; fi

    detect_os
    setup_environment
    install_base_packages
    setup_rclocal
    configure_ssh
    configure_stunnel
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
    echo "✅ SSH-VPN INSTALLATION COMPLETE!"
    echo "All protocols now accept legacy TLS/SSH clients."
    print_info "Type 'menu' to access the management panel"
}

main "$@"