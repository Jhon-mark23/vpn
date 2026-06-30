#!/bin/bash
# ==================================================
# SSH VPN MULTI-PROTOCOL INSTALLER
# Compatible with Debian & Ubuntu
# Optimized for 1GB RAM / 1 CPU VPS
#
# Protocols supported:
#   - SSH DIRECT (22, 2222)
#   - SSH+SSL (8443 via Stunnel)
#   - SSH+WEBSOCKET (8080 via Node.js)
#   - SSH+WEBSOCKET+SSL (8443 via Stunnel + WebSocket)
#   - SSH+PAYLOAD+REMOTE PROXY (Squid 3128)
#   - SSH+SSL+PAYLOAD+REMOTE PROXY (Stunnel + Squid)
#
# No conflicts with Xray/V2Ray (uses non-standard ports)
# ==================================================

# ============================================================
# COLOR DEFINITIONS
# ============================================================
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
NC='\e[0m'

# ============================================================
# FUNCTIONS
# ============================================================
print_info() {
    echo -e "[ ${green}INFO${NC} ] $1"
}

print_error() {
    echo -e "[ ${red}ERROR${NC} ] $1"
}

print_warning() {
    echo -e "[ ${yell}WARNING${NC} ] $1"
}

print_success() {
    echo -e "[ ${green}✓${NC} ] $1"
}

check_success() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$1"
        return 1
    fi
}

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
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    if [ -f /etc/needrestart/needrestart.conf ]; then
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
        sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi

    ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime
    timedatectl set-timezone Asia/Manila 2>/dev/null || true
}

# ============================================================
# INSTALL BASE PACKAGES
# ============================================================
install_base_packages() {
    print_info "Installing base packages..."

    apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true

    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true

    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates stunnel4 dropbear squid fail2ban"

    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt install -y $pkg -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || {
                print_warning "Failed to install $pkg, continuing..."
            }
        fi
    done

    # Install Node.js for WebSocket proxy
    if ! command -v node &>/dev/null; then
        print_info "Installing Node.js 20 LTS for WebSocket proxy..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> /dev/null 2>&1
        apt install -y nodejs >> /dev/null 2>&1 || true
    fi

    check_success "Base packages installed"
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

    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
    if ! grep -q "disable_ipv6" /etc/rc.local; then
        sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
    fi

    check_success "rc.local configured"
}

# ============================================================
# CONFIGURE SSH (DIRECT PORTS: 22, 2222)
# ============================================================
configure_ssh() {
    print_info "Configuring SSH (ports 22, 2222)..."

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

    # Ensure port 22 is enabled
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
    if ! grep -q "^Port 2222" /etc/ssh/sshd_config; then
        echo "Port 2222" >> /etc/ssh/sshd_config
    fi

    # Basic settings
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

    echo "SSH VPN Server - Multi Protocol" > /etc/ssh/ssh_banner
    if ! grep -q "Banner" /etc/ssh/sshd_config; then
        echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
    fi

    # Validate
    sshd -t >> /dev/null 2>&1 || {
        print_error "SSH config test failed"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        exit 1
    }

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    systemctl enable ssh 2>/dev/null || true

    check_success "SSH configured on ports 22, 2222"
}

# ============================================================
# INSTALL DROPBEAR (OPTIONAL)
# ============================================================
install_dropbear() {
    print_info "Installing Dropbear (alternative SSH)..."
    apt install -y dropbear 2>/dev/null
    check_success "Dropbear installation"

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
    check_success "Dropbear configured"
}

# ============================================================
# INSTALL BADVPN (UDP GATEWAY)
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN UDP gateway..."
    cd /tmp
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/newudpgw"
    chmod +x /usr/bin/badvpn-udpgw
    check_success "BADVPN installed"

    for port in 7100 7200 7300 7400; do
        if ! grep -q "badvpn$((port/100))" /etc/rc.local; then
            sed -i "\$ i\screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50" /etc/rc.local
        fi
    done

    screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50 2>/dev/null || true

    check_success "BADVPN started"
}

# ============================================================
# CONFIGURE SQUID (HTTP PROXY FOR PAYLOAD / REMOTE PROXY)
# ============================================================
configure_squid() {
    print_info "Configuring Squid HTTP proxy on port 3128..."
    apt install -y squid 2>/dev/null

    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

    cat > /etc/squid/squid.conf <<EOF
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
cache_dir ufs /var/spool/squid 100 16 256
cache_mem 64 MB
forwarded_for off
request_header_access X-Forwarded-For deny all
visible_hostname localhost
dns_nameservers 8.8.8.8 1.1.1.1
EOF

    mkdir -p /var/spool/squid
    chown -R proxy:proxy /var/spool/squid 2>/dev/null || true
    squid -z >> /dev/null 2>&1 || true

    systemctl enable squid
    systemctl restart squid
    check_success "Squid proxy on port 3128"
}

# ============================================================
# CONFIGURE STUNNEL4 (SSH+SSL ON PORT 8443)
# ============================================================
configure_stunnel() {
    print_info "Configuring Stunnel4 (SSH over SSL) on port 8443..."
    apt install -y stunnel4 2>/dev/null

    mkdir -p /var/log/stunnel4 /etc/stunnel /var/run/stunnel4

    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi

    chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4

    # Generate self-signed cert
    cd /tmp
    openssl genrsa -out /tmp/stunnel-key.pem 2048 2>/dev/null
    openssl req -new -x509 \
        -key /tmp/stunnel-key.pem \
        -out /tmp/stunnel-cert.pem \
        -days 3650 \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=SSH-VPN/CN=localhost" \
        2>/dev/null
    cat /tmp/stunnel-key.pem /tmp/stunnel-cert.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
    rm -f /tmp/stunnel-key.pem /tmp/stunnel-cert.pem
    cd

    cat > /etc/stunnel/stunnel.conf <<END
pid = /var/run/stunnel.pid
client = no
output = /var/log/stunnel.log
foreground = no
debug = 3
sslVersion = TLSv1.2
options = NO_SSLv2
options = NO_SSLv3
options = NO_TLSv1
options = NO_TLSv1.1

[ssh-ssl]
accept = 8443
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ws-ssl]
accept = 8444
connect = 127.0.0.1:8080
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
END

    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4

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
    systemctl restart stunnel4 2>/dev/null || {
        print_error "Failed to start Stunnel4"
        exit 1
    }

    check_success "Stunnel4 configured on ports 8443 (SSH+SSL) and 8444 (WS+SSL)"
}

# ============================================================
# CONFIGURE WEBSOCKET PROXY (ws-proxy.js) - PORT 8080
# ============================================================
configure_websocket() {
    print_info "Configuring WebSocket proxy (ws-proxy.js) on port 8080..."

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

log('Starting SSH WebSocket Proxy on port ' + WS_PORT);

const server = http.createServer();

// Handle HTTP CONNECT method (for proxy)
server.on('connect', (req, clientSocket) => {
    log('CONNECT: ' + req.url);
    const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
        clientSocket.write('HTTP/1.1 200 Connection Established\r\nProxy-Agent: SSH-WS-Proxy\r\n\r\n');
        ssh.pipe(clientSocket);
        clientSocket.pipe(ssh);
    });
    ssh.on('error', (e) => { log('SSH error: ' + e.message); clientSocket.destroy(); });
    clientSocket.on('error', (e) => { log('Socket error: ' + e.message); ssh.destroy(); });
});

// Handle WebSocket upgrade
server.on('upgrade', (req, socket) => {
    log('WebSocket upgrade from ' + req.headers.host);
    const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
        socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n');
        ssh.pipe(socket);
        socket.pipe(ssh);
    });
    ssh.on('error', (e) => { log('WS SSH error: ' + e.message); socket.destroy(); });
    socket.on('error', (e) => { log('Socket error: ' + e.message); ssh.destroy(); });
});

// HTTP status page
server.on('request', (req, res) => {
    if (req.url === '/' || req.url === '/status') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(
            '<html><head><title>SSH WebSocket Proxy</title></head>' +
            '<body><h1>🚀 SSH WebSocket Proxy</h1>' +
            '<p>Status: Running</p>' +
            '<p>Uptime: ' + Math.floor(process.uptime()) + 's</p>' +
            '<p>SSH Host: ' + SSH_HOST + ':' + SSH_PORT + '</p>' +
            '<hr><small>Multi-Protocol SSH VPN</small></body></html>'
        );
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen(WS_PORT, '0.0.0.0', () => {
    log('✅ WebSocket proxy listening on port ' + WS_PORT);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    log('SIGTERM received, shutting down...');
    server.close(() => process.exit(0));
});

process.on('SIGINT', () => {
    log('SIGINT received, shutting down...');
    server.close(() => process.exit(0));
});

process.on('uncaughtException', (e) => {
    log('Uncaught exception: ' + e.message);
});
EOF

    chmod +x /opt/ws-proxy/ws-proxy.js

    # Create systemd service
    cat > /etc/systemd/system/ws-proxy.service <<EOF
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
    systemctl start ws-proxy 2>/dev/null || {
        print_error "Failed to start WebSocket proxy"
        exit 1
    }

    sleep 2
    if systemctl is-active --quiet ws-proxy; then
        check_success "WebSocket proxy running on port 8080"
    else
        print_error "WebSocket proxy failed to start"
        journalctl -u ws-proxy -n 10
        exit 1
    fi
}

# ============================================================
# INSTALL FAIL2BAN
# ============================================================
install_fail2ban() {
    print_info "Installing Fail2ban..."
    apt install -y fail2ban 2>/dev/null
    check_success "Fail2ban installation"

    cat > /etc/fail2ban/jail.local <<F2B
[DEFAULT]
findtime  = 600
bantime   = 3600
maxretry  = 5
backend   = polling

[sshd]
enabled   = true
port      = ssh,2222,8443,8444,8080
logpath   = %(sshd_log)s
maxretry  = 5
F2B

    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true
    check_success "Fail2ban configured"
}

# ============================================================
# SYSTEM OPTIMIZATION
# ============================================================
optimize_system() {
    print_info "Optimizing system..."
    cat > /etc/sysctl.d/99-vpn-optimization.conf <<SYSCTL
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 51200
net.ipv4.tcp_fastopen = 3
SYSCTL

    sysctl -p /etc/sysctl.d/99-vpn-optimization.conf 2>/dev/null || true

    if [ ! -f /swapfile ]; then
        print_info "Creating 512MB swap..."
        if command -v fallocate &> /dev/null; then
            fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 status=progress 2>/dev/null
        else
            dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
        fi
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Swap created"
    fi

    cat > /etc/security/limits.d/99-vpn.conf <<LIMITS
* soft nofile 51200
* hard nofile 51200
root soft nofile 51200
root hard nofile 51200
LIMITS

    check_success "System optimized"
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

    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    fi
    check_success "Torrent traffic blocked"
}

# ============================================================
# DOWNLOAD ORIGINAL MENU SCRIPTS
# ============================================================
download_scripts() {
    print_info "Downloading original menu scripts..."
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin

    declare -A scripts=(
        ["menu"]="$GHBASE/menu/menu.sh"
        ["m-vmess"]="$GHBASE/menu/m-vmess.sh"
        ["m-vless"]="$GHBASE/menu/m-vless.sh"
        ["running"]="$GHBASE/menu/running.sh"
        ["clearcache"]="$GHBASE/menu/clearcache.sh"
        ["m-ssws"]="$GHBASE/menu/m-ssws.sh"
        ["m-trojan"]="$GHBASE/menu/m-trojan.sh"
        ["m-sshovpn"]="$GHBASE/menu/m-sshovpn.sh"
        ["usernew"]="$GHBASE/ssh/usernew.sh"
        ["trial"]="$GHBASE/ssh/trial.sh"
        ["renew"]="$GHBASE/ssh/renew.sh"
        ["hapus"]="$GHBASE/ssh/hapus.sh"
        ["cek"]="$GHBASE/ssh/cek.sh"
        ["member"]="$GHBASE/ssh/member.sh"
        ["delete"]="$GHBASE/ssh/delete.sh"
        ["autokill"]="$GHBASE/ssh/autokill.sh"
        ["ceklim"]="$GHBASE/ssh/ceklim.sh"
        ["tendang"]="$GHBASE/ssh/tendang.sh"
        ["sshws"]="$GHBASE/ssh/sshws.sh"
        ["m-system"]="$GHBASE/menu/m-system.sh"
        ["m-domain"]="$GHBASE/menu/m-domain.sh"
        ["add-host"]="$GHBASE/ssh/add-host.sh"
        ["certv2ray"]="$GHBASE/xray/certv2ray.sh"
        ["speedtest"]="$GHBASE/ssh/speedtest_cli.py"
        ["auto-reboot"]="$GHBASE/menu/auto-reboot.sh"
        ["restart"]="$GHBASE/menu/restart.sh"
        ["bw"]="$GHBASE/menu/bw.sh"
        ["m-tcp"]="$GHBASE/menu/tcp.sh"
        ["xp"]="$GHBASE/ssh/xp.sh"
        ["m-dns"]="$GHBASE/menu/m-dns.sh"
        ["fix-cek"]="$GHBASE/ssh/fix-cek.sh"
    )

    for script in "${!scripts[@]}"; do
        url="${scripts[$script]}"
        if wget --timeout=10 --tries=3 -q -O "$script" "$url" 2>/dev/null; then
            chmod +x "$script"
            print_success "Downloaded: $script"
        else
            alt_url="https://raw.githubusercontent.com/Jhon-mark23/vpn/main/${url#*$GHBASE/}"
            if wget --timeout=10 --tries=2 -q -O "$script" "$alt_url" 2>/dev/null; then
                chmod +x "$script"
                print_success "Downloaded: $script (alt)"
            else
                print_warning "Failed to download: $script"
                echo "#!/bin/bash" > "$script"
                echo "echo 'Script $script not available'" >> "$script"
                chmod +x "$script"
            fi
        fi
    done

    cd /
    print_success "Management scripts downloaded"
}

# ============================================================
# SETUP CRON
# ============================================================
setup_cron() {
    print_info "Setting up cron jobs..."
    cat > /etc/cron.d/re_otm <<END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
END

    echo "7" > /home/re_otm
    systemctl restart cron 2>/dev/null || systemctl restart cronie 2>/dev/null || true
    check_success "Cron jobs configured"
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    print_info "Cleaning up..."
    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    for pkg in unscd samba apache2 bind9 sendmail; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            apt-get -y --purge remove $pkg 2>/dev/null || true
        fi
    done

    history -c
    echo "unset HISTFILE" >> /etc/profile

    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null
    check_success "Cleanup completed"
}

# ============================================================
# RESTART SERVICES
# ============================================================
restart_services() {
    print_info "Restarting all services..."
    for service in ssh dropbear stunnel4 ws-proxy squid fail2ban vnstat rc-local cron; do
        if systemctl restart $service 2>/dev/null; then
            print_success "Restarted $service"
        else
            print_warning "Failed to restart $service"
        fi
    done

    for port in 7100 7200 7300 7400; do
        screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
}

# ============================================================
# CREATE CONNECTION GUIDE
# ============================================================
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")
    cat > /root/ssh-vpn-guide.txt <<EOF
===========================================
   SSH VPN CONNECTION GUIDE
   (Xray/V2Ray Compatible)
===========================================

VPS IP: $VPS_IP

===========================================
1. SSH DIRECT
===========================================
   Port 22 or 2222
   ssh -p 22 root@$VPS_IP
   ssh -p 2222 root@$VPS_IP

===========================================
2. SSH OVER SSL (Stunnel)
===========================================
   Port 8443
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8443 -quiet" root@$VPS_IP

===========================================
3. SSH OVER WEBSOCKET (WS)
===========================================
   Port 8080
   ssh -o ProxyCommand="websocat ws://$VPS_IP:8080" root@$VPS_IP

===========================================
4. SSH OVER WEBSOCKET + SSL (WSS)
===========================================
   Port 8444 (Stunnel on top of WebSocket)
   ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8444 -quiet" root@$VPS_IP
   or use websocat wss://$VPS_IP:8444

===========================================
5. SSH + PAYLOAD + REMOTE PROXY (HTTP Injector / KPN)
===========================================
   Proxy: HTTP
   Proxy Host: $VPS_IP
   Proxy Port: 3128
   SSH Host: $VPS_IP
   SSH Port: 22 or 2222
   Payload: custom (client-side)

===========================================
6. SSH + SSL + PAYLOAD + REMOTE PROXY
===========================================
   SSH Host: $VPS_IP
   SSH Port: 8443 (SSL)
   Proxy: HTTP $VPS_IP:3128
   SSL enabled

===========================================
MANAGEMENT
===========================================
   menu         - Original menu
   create       - Create SSH user
   vpn-status   - Check services
   wsproxy      - Manage WebSocket proxy (start|stop|restart|status|logs)

===========================================
SERVICE MANAGEMENT
===========================================
   systemctl status ssh        - SSH status
   systemctl status stunnel4   - SSL status
   systemctl status ws-proxy   - WebSocket status
   systemctl status squid      - HTTP proxy status

   # WebSocket proxy commands
   wsproxy start|stop|restart|status|logs

===========================================
EOF
    print_success "Connection guide saved to /root/ssh-vpn-guide.txt"
}

# ============================================================
# CREATE WS-PROXY MANAGEMENT SCRIPT
# ============================================================
create_wsproxy_script() {
    cat > /usr/local/bin/wsproxy <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status)
        systemctl $1 ws-proxy
        ;;
    logs)
        journalctl -u ws-proxy -f
        ;;
    kill)
        fuser -k 8080/tcp 2>/dev/null
        echo "WebSocket proxy killed on port 8080"
        ;;
    *)
        echo "Usage: wsproxy {start|stop|restart|status|logs|kill}"
        echo ""
        echo "  start   - Start WebSocket proxy"
        echo "  stop    - Stop WebSocket proxy"
        echo "  restart - Restart WebSocket proxy"
        echo "  status  - Check WebSocket proxy status"
        echo "  logs    - View WebSocket proxy logs"
        echo "  kill    - Force kill on port 8080"
        ;;
esac
EOF
    chmod +x /usr/local/bin/wsproxy
    print_success "WebSocket proxy management script created (wsproxy)"
}

# ============================================================
# CREATE VPN-STATUS SCRIPT
# ============================================================
create_vpn_status() {
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   SSH VPN SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "SSH Server      : $(systemctl is-active ssh)   (22, 2222)"
echo "Stunnel4        : $(systemctl is-active stunnel4)   (8443, 8444)"
echo "WebSocket Proxy : $(systemctl is-active ws-proxy)   (8080)"
echo "Squid Proxy     : $(systemctl is-active squid)   (3128)"
echo "Fail2ban        : $(systemctl is-active fail2ban)"
echo "Dropbear        : $(systemctl is-active dropbear)   (109, 143)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Commands:"
echo "  menu         - Original menu"
echo "  create       - Create SSH user"
echo "  wsproxy      - Manage WebSocket proxy"
echo "  vpn-status   - Show this status"
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/vpn-status
    print_success "VPN status script created (vpn-status)"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo ""
    echo "==========================================="
    echo "   SSH VPN MULTI-PROTOCOL INSTALLER"
    echo "   (Xray/V2Ray Compatible)"
    echo "==========================================="
    echo ""
    echo "Protocols to be installed:"
    echo "  ✅ SSH Direct       : 22, 2222"
    echo "  ✅ SSH Over SSL     : 8443 (Stunnel)"
    echo "  ✅ SSH Over WebSocket: 8080 (ws-proxy.js)"
    echo "  ✅ SSH WebSocket SSL: 8444 (Stunnel + WS)"
    echo "  ✅ HTTP Proxy       : 3128 (Squid) – for Payload + Remote Proxy"
    echo "  ✅ SSH + SSL + Proxy: client-side chaining"
    echo ""
    echo "⚠️  No conflicts with Xray (Xray uses 80, 443, 81, etc.)"
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
    install_dropbear
    install_badvpn
    configure_squid
    configure_stunnel
    configure_websocket
    install_fail2ban
    optimize_system
    block_torrent
    download_scripts
    setup_cron
    create_wsproxy_script
    create_vpn_status
    restart_services
    create_guide
    cleanup

    clear
    echo ""
    echo "==========================================="
    echo "   ✅ SSH-VPN INSTALLATION COMPLETE!"
    echo "   (Xray Compatible)"
    echo "==========================================="
    echo ""
    echo "📡 CONNECTION METHODS:"
    echo "   SSH Direct     : 22, 2222"
    echo "   SSH SSL        : 8443"
    echo "   SSH WebSocket  : 8080"
    echo "   SSH WSS        : 8444"
    echo "   HTTP Proxy     : 3128 (Squid)"
    echo ""
    echo "📖 Full guide: /root/ssh-vpn-guide.txt"
    echo ""
    echo "🔧 Management:"
    echo "   menu         - Original menu"
    echo "   create       - Create SSH user"
    echo "   wsproxy      - Manage WebSocket proxy"
    echo "   vpn-status   - Check services"
    echo ""
    echo "==========================================="
    echo ""
    print_success "SSH-VPN installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"