#!/bin/bash
# ==================================================
# Enhanced SSH-VPN Install Script - Compatible with Debian & Ubuntu
# Optimized for 1GB RAM / 1 CPU VPS
# Features:
#   - Better error handling
#   - Improved resource optimization
#   - Enhanced security
#   - Better OS compatibility
#   - Comprehensive logging
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
    
    # Set OS-specific variables
    if [[ "$OS" == "ubuntu" ]]; then
        PKG_MANAGER="apt-get"
    elif [[ "$OS" == "debian" ]]; then
        PKG_MANAGER="apt-get"
    fi
}

# ============================================================
# SETUP ENVIRONMENT
# ============================================================
setup_environment() {
    # Suppress interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    
    # Configure needrestart
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
    
    # Update system
    apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    
    # Remove conflicting packages
    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true
    
    # Essential packages
    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates"
    
    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt install -y $pkg -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || {
                print_warning "Failed to install $pkg, continuing..."
            }
        fi
    done
    
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
    
    # Disable IPv6
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
    if ! grep -q "disable_ipv6" /etc/rc.local; then
        sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
    fi
    
    check_success "rc.local configured"
}

# ============================================================
# CONFIGURE SSH
# ============================================================
configure_ssh() {
    print_info "Configuring SSH..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    
    # Configure SSH
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config
    sed -i '/^Port [0-9]/d' /etc/ssh/sshd_config
    sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config
    
    echo "Port 22" >> /etc/ssh/sshd_config
    echo "Port 9696" >> /etc/ssh/sshd_config
    
    # Restart SSH
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    check_success "SSH configured"
}

# ============================================================
# INSTALL DROPBEAR
# ============================================================
install_dropbear() {
    print_info "Installing Dropbear..."
    
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
# INSTALL BADVPN
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN..."
    
    cd /tmp
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/newudpgw"
    chmod +x /usr/bin/badvpn-udpgw
    check_success "BADVPN installed"
    
    # Add to rc.local
    for port in 7100 7200 7300 7400; do
        if ! grep -q "badvpn$((port/100))" /etc/rc.local; then
            sed -i "\$ i\screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50" /etc/rc.local
        fi
    done
    
    # Start BADVPN
    screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50 2>/dev/null || true
    screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50 2>/dev/null || true
    
    check_success "BADVPN started"
}

# ============================================================
# INSTALL & CONFIGURE NGINX
# ============================================================
install_nginx() {
    print_info "Installing Nginx..."
    
    apt install -y nginx 2>/dev/null
    check_success "Nginx installation"
    
    # Remove default sites
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    rm -f /etc/nginx/sites-available/default 2>/dev/null
    
    # Download optimized nginx config
    wget -q -O /etc/nginx/nginx.conf "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/nginx.conf"
    
    # Optimize for low memory
    sed -i 's/worker_processes\s*auto/worker_processes 1/' /etc/nginx/nginx.conf
    sed -i 's/worker_connections\s*[0-9]*/worker_connections 512/' /etc/nginx/nginx.conf
    
    mkdir -p /home/vps/public_html
    mkdir -p /etc/nginx/conf.d
    
    # Create temporary config
    cat > /etc/nginx/conf.d/xray.conf <<-NGINXTMP
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
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
NGINXTMP
    
    systemctl restart nginx 2>/dev/null || true
    check_success "Nginx configured"
}

# ============================================================
# INSTALL STUNNEL4
# ============================================================
install_stunnel() {
    print_info "Installing Stunnel4..."
    
    apt install -y stunnel4 2>/dev/null
    check_success "Stunnel4 installation"
    
    # Create directories
    mkdir -p /var/log/stunnel4
    mkdir -p /etc/stunnel
    mkdir -p /var/run/stunnel4
    
    # Create stunnel user if not exists
    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi
    
    # Set permissions
    chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4
    
    # Generate SSL certificate
    cd /tmp
    openssl genrsa -out /tmp/stunnel-key.pem 2048 2>/dev/null
    openssl req -new -x509 \
        -key /tmp/stunnel-key.pem \
        -out /tmp/stunnel-cert.pem \
        -days 3650 \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=VPN/CN=localhost" \
        2>/dev/null
    cat /tmp/stunnel-key.pem /tmp/stunnel-cert.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
    rm -f /tmp/stunnel-key.pem /tmp/stunnel-cert.pem
    cd
    
    # Stunnel config
    cat > /etc/stunnel/stunnel.conf <<-END
; Stunnel4 Config
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
pid = /var/run/stunnel4/stunnel4.pid

[ssh-ssl]
accept = 222
connect = 127.0.0.1:22

[dropbear-ssl]
accept = 777
connect = 127.0.0.1:109

[ws-stunnel]
accept = 2096
connect = 127.0.0.1:700
END
    
    # Stunnel defaults
    cat > /etc/default/stunnel4 <<-STUNNEL
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
BANNER="/etc/issue.net"
PPP_RESTART=0
OUTPUT=/var/log/stunnel4/stunnel.log
STUNNEL
    
    # Systemd override
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
    
    check_success "Stunnel4 configured"
}

# ============================================================
# INSTALL FAIL2BAN
# ============================================================
install_fail2ban() {
    print_info "Installing Fail2ban..."
    
    apt install -y fail2ban 2>/dev/null
    check_success "Fail2ban installation"
    
    mkdir -p /etc/fail2ban
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
    check_success "Fail2ban configured"
}

# ============================================================
# SYSTEM OPTIMIZATION
# ============================================================
optimize_system() {
    print_info "Optimizing system..."
    
    # Kernel optimization
    cat > /etc/sysctl.d/99-vpn-optimization.conf <<-SYSCTL
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
net.ipv4.tcp_fastopen = 3
SYSCTL
    
    sysctl -p /etc/sysctl.d/99-vpn-optimization.conf 2>/dev/null || true
    
    # Create swap if not exists
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
    
    # Increase file limits
    cat > /etc/security/limits.d/99-vpn.conf <<-LIMITS
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
    
    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    fi
    
    check_success "Torrent traffic blocked"
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."
    
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    
    scripts=(
        "menu:m${GHBASE}/menu/menu.sh"
        "m-vmess:${GHBASE}/menu/m-vmess.sh"
        "m-vless:${GHBASE}/menu/m-vless.sh"
        "running:${GHBASE}/menu/running.sh"
        "clearcache:${GHBASE}/menu/clearcache.sh"
        "m-ssws:${GHBASE}/menu/m-ssws.sh"
        "m-trojan:${GHBASE}/menu/m-trojan.sh"
        "m-sshovpn:${GHBASE}/menu/m-sshovpn.sh"
        "usernew:${GHBASE}/ssh/usernew.sh"
        "trial:${GHBASE}/ssh/trial.sh"
        "renew:${GHBASE}/ssh/renew.sh"
        "hapus:${GHBASE}/ssh/hapus.sh"
        "cek:${GHBASE}/ssh/cek.sh"
        "member:${GHBASE}/ssh/member.sh"
        "delete:${GHBASE}/ssh/delete.sh"
        "autokill:${GHBASE}/ssh/autokill.sh"
        "ceklim:${GHBASE}/ssh/ceklim.sh"
        "tendang:${GHBASE}/ssh/tendang.sh"
        "sshws:${GHBASE}/ssh/sshws.sh"
        "m-system:${GHBASE}/menu/m-system.sh"
        "m-domain:${GHBASE}/menu/m-domain.sh"
        "add-host:${GHBASE}/ssh/add-host.sh"
        "certv2ray:${GHBASE}/xray/certv2ray.sh"
        "speedtest:${GHBASE}/ssh/speedtest_cli.py"
        "auto-reboot:${GHBASE}/menu/auto-reboot.sh"
        "restart:${GHBASE}/menu/restart.sh"
        "bw:${GHBASE}/menu/bw.sh"
        "m-tcp:${GHBASE}/menu/tcp.sh"
        "xp:${GHBASE}/ssh/xp.sh"
        "m-dns:${GHBASE}/menu/m-dns.sh"
        "fix-cek:${GHBASE}/ssh/fix-cek.sh"
    )
    
    for script in "${scripts[@]}"; do
        name="${script%%:*}"
        url="${script##*:}"
        wget -q -O "$name" "$url" && chmod +x "$name"
        if [ $? -eq 0 ]; then
            print_info "Downloaded: $name"
        else
            print_warning "Failed to download: $name"
        fi
    done
    
    cd /
    check_success "Management scripts downloaded"
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
    
    # Remove unwanted services
    for pkg in unscd samba apache2 bind9 sendmail; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            apt-get -y --purge remove $pkg 2>/dev/null || true
        fi
    done
    
    chown -R www-data:www-data /home/vps/public_html 2>/dev/null || true
    
    # Clear history
    history -c
    echo "unset HISTFILE" >> /etc/profile
    
    # Remove installation files
    rm -f /root/key.pem 2>/dev/null
    rm -f /root/cert.pem 2>/dev/null
    rm -f /root/ssh-vpn.sh 2>/dev/null
    rm -f /root/bbr.sh 2>/dev/null
    
    check_success "Cleanup completed"
}

# ============================================================
# RESTART SERVICES
# ============================================================
restart_services() {
    print_info "Restarting all services..."
    
    services=(
        "nginx"
        "cron"
        "ssh"
        "dropbear"
        "fail2ban"
        "stunnel4"
        "vnstat"
        "rc-local"
    )
    
    for service in "${services[@]}"; do
        if systemctl restart $service 2>/dev/null; then
            print_success "Restarted $service"
        else
            print_warning "Failed to restart $service"
        fi
    done
    
    # Restart BADVPN
    for port in 7100 7200 7300 7400; do
        screen -dmS badvpn$((port/100)) badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
}

# ============================================================
# MAIN EXECUTION
# ============================================================
main() {
    print_info "Starting SSH-VPN installation..."
    
    # Run all functions
    detect_os
    setup_environment
    install_base_packages
    setup_rclocal
    configure_ssh
    install_dropbear
    install_badvpn
    install_nginx
    install_stunnel
    install_fail2ban
    optimize_system
    block_torrent
    download_scripts
    setup_cron
    restart_services
    cleanup
    
    print_success "SSH-VPN installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
}

# ============================================================
# RUN MAIN
# ============================================================
main "$@"
