#!/bin/bash
# ==================================================
# SSH-VPN Install Script - XRAY COMPATIBLE
# Optimized for 1GB RAM / 1 CPU VPS
# Supports: SSH Direct, SSH+SSL, SSH+WS
# Compatible with Xray (port 80/443 shared via Nginx)
# ==================================================

set -e

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
print_warning() { echo -e "[ ${yell}WARNING${NC} ] $1"; }
print_success() { echo -e "[ ${green}✓${NC} ] $1"; }

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

    # Set timezone
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

    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates nginx stunnel4 dropbear fail2ban"

    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt install -y $pkg -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || {
                print_warning "Failed to install $pkg, continuing..."
            }
        fi
    done

    # Python for WebSocket
    if ! command -v python3 &>/dev/null; then
        apt install -y python3 python3-pip >> /dev/null 2>&1 || true
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

    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
    if ! grep -q "disable_ipv6" /etc/rc.local; then
        sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
    fi

    print_success "rc.local configured"
}

# ============================================================
# CONFIGURE SSH
# ============================================================
configure_ssh() {
    print_info "Configuring SSH (ports 22, 9696)..."

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config
    sed -i '/^Port [0-9]/d' /etc/ssh/sshd_config
    sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config

    echo "Port 22" >> /etc/ssh/sshd_config
    echo "Port 9696" >> /etc/ssh/sshd_config

    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    print_success "SSH configured on ports 22, 9696"
}

# ============================================================
# INSTALL DROPBEAR
# ============================================================
install_dropbear() {
    print_info "Installing Dropbear (ports 109, 143)..."

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
    print_success "Dropbear configured"
}

# ============================================================
# INSTALL BADVPN
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN (ports 7100-7400)..."

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

    print_success "BADVPN started"
}

# ============================================================
# CONFIGURE NGINX - XRAY COMPATIBLE
# ============================================================
configure_nginx() {
    print_info "Configuring Nginx (Xray compatible)..."

    # Create optimized nginx.conf
    cat > /etc/nginx/nginx.conf <<'NGINXCONF'
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
    gzip_types text/plain application/x-javascript text/xml text/css;
    autoindex on;
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
    client_header_buffer_size 8m;
    large_client_header_buffers 8 8m;
    fastcgi_buffer_size 8m;
    fastcgi_buffers 8 8m;
    fastcgi_read_timeout 600;

    set_real_ip_from 199.27.128.0/21;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/12;
    set_real_ip_from 199.83.128.0/21;
    set_real_ip_from 198.143.32.0/19;
    set_real_ip_from 149.126.72.0/21;
    set_real_ip_from 103.28.248.0/22;
    set_real_ip_from 45.64.64.0/22;
    set_real_ip_from 185.11.124.0/22;
    set_real_ip_from 192.230.64.0/18;
    real_ip_header CF-Connecting-IP;

    include /etc/nginx/conf.d/*.conf;
}
NGINXCONF

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    # SSH WebSocket config (port 2095)
    cat > /etc/nginx/conf.d/ssh-ws.conf <<'SSHCONF'
# ============================================================
# SSH WEBSOCKET CONFIG (ws-dropbear on 2095)
# ============================================================
server {
    listen 81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
}

server {
    listen 80 default_server;
    server_name _;
    root /home/vps/public_html;

    location / {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_redirect off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
SSHCONF

    # Placeholder for Xray (will be overwritten by ins-xray.sh)
    cat > /etc/nginx/conf.d/xray.conf <<'XRAYPLACEHOLDER'
# ============================================================
# XRAY CONFIG - Managed by ins-xray.sh
# ============================================================
XRAYPLACEHOLDER

    mkdir -p /home/vps/public_html

    nginx -t 2>/dev/null || {
        print_error "Nginx config test failed"
        exit 1
    }

    systemctl restart nginx
    print_success "Nginx configured (SSH on 2095, Xray on 80/443)"
}

# ============================================================
# INSTALL STUNNEL4 - SSH OVER SSL (XRAY COMPATIBLE)
# ============================================================
install_stunnel() {
    print_info "Installing Stunnel4 (SSH SSL on ports 222, 777)..."

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

    # Generate certificate
    cd /tmp
    openssl genrsa -out /tmp/stunnel-key.pem 2048 2>/dev/null
    openssl req -new -x509 \
        -key /tmp/stunnel-key.pem \
        -out /tmp/stunnel-cert.pem \
        -days 3650 \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=SSH/CN=localhost" \
        2>/dev/null
    cat /tmp/stunnel-key.pem /tmp/stunnel-cert.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
    rm -f /tmp/stunnel-key.pem /tmp/stunnel-cert.pem
    cd

    cat > /etc/stunnel/stunnel.conf <<'STUNNELCONF'
pid = /var/run/stunnel.pid
client = no
output = /var/log/stunnel.log
foreground = no
debug = 3
sslVersion = TLSv1.2

[ssh-ssl]
accept = 222
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[dropbear-ssl]
accept = 777
connect = 127.0.0.1:109
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0

[ws-stunnel]
accept = 2096
connect = 127.0.0.1:700
cert = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
STUNNELCONF

    echo 'ENABLED=1' > /etc/default/stunnel4
    systemctl daemon-reload
    systemctl enable stunnel4 2>/dev/null || true
    systemctl stop stunnel4 2>/dev/null; sleep 1
    systemctl start stunnel4 2>/dev/null || true

    print_success "Stunnel4 configured on ports 222, 777"
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
port      = ssh,9696,222,777
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

# === VPS 1GB RAM OPTIMIZATION ===
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
# DOWNLOAD MENU SCRIPTS
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."

    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin

    scripts=(
        "menu:$GHBASE/menu/menu.sh"
        "m-vmess:$GHBASE/menu/m-vmess.sh"
        "m-vless:$GHBASE/menu/m-vless.sh"
        "running:$GHBASE/menu/running.sh"
        "clearcache:$GHBASE/menu/clearcache.sh"
        "m-ssws:$GHBASE/menu/m-ssws.sh"
        "m-trojan:$GHBASE/menu/m-trojan.sh"
        "m-sshovpn:$GHBASE/menu/m-sshovpn.sh"
        "usernew:$GHBASE/ssh/usernew.sh"
        "trial:$GHBASE/ssh/trial.sh"
        "renew:$GHBASE/ssh/renew.sh"
        "hapus:$GHBASE/ssh/hapus.sh"
        "cek:$GHBASE/ssh/cek.sh"
        "member:$GHBASE/ssh/member.sh"
        "delete:$GHBASE/ssh/delete.sh"
        "autokill:$GHBASE/ssh/autokill.sh"
        "ceklim:$GHBASE/ssh/ceklim.sh"
        "tendang:$GHBASE/ssh/tendang.sh"
        "sshws:$GHBASE/ssh/sshws.sh"
        "m-system:$GHBASE/menu/m-system.sh"
        "m-domain:$GHBASE/menu/m-domain.sh"
        "add-host:$GHBASE/ssh/add-host.sh"
        "certv2ray:$GHBASE/xray/certv2ray.sh"
        "speedtest:$GHBASE/ssh/speedtest_cli.py"
        "auto-reboot:$GHBASE/menu/auto-reboot.sh"
        "restart:$GHBASE/menu/restart.sh"
        "bw:$GHBASE/menu/bw.sh"
        "m-tcp:$GHBASE/menu/tcp.sh"
        "xp:$GHBASE/ssh/xp.sh"
        "m-dns:$GHBASE/menu/m-dns.sh"
        "fix-cek:$GHBASE/ssh/fix-cek.sh"
    )

    for item in "${scripts[@]}"; do
        name="${item%%:*}"
        url="${item##*:}"
        wget -q -O "$name" "$url" 2>/dev/null && chmod +x "$name"
    done

    cd /
    print_success "Management scripts downloaded"
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

    cat > /etc/cron.d/xp_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
END

    echo "7" > /home/re_otm
    systemctl restart cron 2>/dev/null || true
    print_success "Cron jobs configured"
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    print_info "Cleaning up..."

    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    for pkg in unscd samba apache2 bind9 sendmail; do
        dpkg -l | grep -q "^ii  $pkg " && apt-get -y --purge remove $pkg 2>/dev/null || true
    done

    chown -R www-data:www-data /home/vps/public_html 2>/dev/null || true

    history -c
    echo "unset HISTFILE" >> /etc/profile

    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null
    print_success "Cleanup completed"
}

# ============================================================
# RESTART SERVICES
# ============================================================
restart_services() {
    print_info "Restarting all services..."

    for service in nginx cron ssh dropbear fail2ban stunnel4 vnstat rc-local; do
        systemctl restart $service 2>/dev/null && print_success "Restarted $service"
    done

    screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50 2>/dev/null || true
}

# ============================================================
# CREATE CONNECTION GUIDE
# ============================================================
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")

    cat > /root/ssh-connection-guide.txt <<EOF
===========================================
   SSH VPN CONNECTION GUIDE
   (Xray Compatible)
===========================================

VPS IP: $VPS_IP

===========================================
1. SSH DIRECT
===========================================
ssh -p 22 root@$VPS_IP
ssh -p 9696 root@$VPS_IP

===========================================
2. SSH OVER SSL (Stunnel4)
===========================================
ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:222 -quiet" root@$VPS_IP
ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:777 -quiet" root@$VPS_IP

===========================================
3. SSH OVER WEBSOCKET (ws-dropbear)
===========================================
Port 2095 (HTTP)
ssh -o ProxyCommand="websocat ws://$VPS_IP:2095" root@$VPS_IP

===========================================
4. SSH OVER WEBSOCKET + SSL (ws-stunnel)
===========================================
Port 700 (WSS)
ssh -o ProxyCommand="websocat wss://$VPS_IP:700" root@$VPS_IP

===========================================
5. HTTP PROXY (Squid) - for Payload
===========================================
HTTP Proxy: $VPS_IP:3128

===========================================
MANAGEMENT
===========================================
menu         - Original menu
create       - Create SSH user
vpn-status   - Check services
===========================================
EOF

    print_success "Connection guide saved to /root/ssh-connection-guide.txt"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo ""
    echo "==========================================="
    echo "   SSH VPN INSTALLER (Xray Compatible)"
    echo "==========================================="
    echo ""
    echo "This will install:"
    echo "  ✅ SSH Direct (22, 9696)"
    echo "  ✅ SSH over SSL (222, 777)"
    echo "  ✅ SSH over WebSocket (2095)"
    echo "  ✅ SSH over WSS (700)"
    echo "  ✅ HTTP Proxy (3128) - for payload"
    echo "  ✅ BADVPN (7100-7400)"
    echo ""
    echo "⚠️  Xray compatible - no port conflicts"
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
    configure_nginx
    install_stunnel
    install_fail2ban
    optimize_system
    block_torrent
    download_scripts
    setup_cron
    restart_services
    create_guide
    cleanup

    clear
    echo ""
    echo "==========================================="
    echo "   ✅ SSH-VPN INSTALLATION COMPLETE!"
    echo "==========================================="
    echo ""
    echo "📡 CONNECTION METHODS:"
    echo "   SSH Direct     : 22, 9696"
    echo "   SSH SSL        : 222, 777"
    echo "   SSH WS         : 2095"
    echo "   SSH WSS        : 700"
    echo "   HTTP Proxy     : 3128"
    echo "   BADVPN         : 7100-7400"
    echo ""
    echo "🔧 Management:"
    echo "   menu         - Original menu"
    echo "   create       - Create SSH user"
    echo ""
    echo "⚠️  Now run ins-xray.sh to install Xray"
    echo "   (Xray will use ports 80/443 via Nginx)"
    echo "==========================================="
    echo ""

    print_success "SSH-VPN installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"
