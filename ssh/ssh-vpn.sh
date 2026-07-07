#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER - XRAY COMPATIBLE
# (Centralised certificate + max client compatibility)
# ALL PROTOCOLS FIXED & WORKING WITH ENHANCED BACKUP & ROLLBACK
# 
# REMOVED: Squid Proxy, Dropbear, Node.js WebSocket (moved to insshws.sh)
# ============================================================

# ---------- GITHUB TOKEN ----------
gtoken=$(cat /root/token 2>/dev/null || cat /root/token.txt 2>/dev/null)

echo "SSH install ${gtoken}"
GITHUB_TOKEN="$gtoken"
REPO_API="https://api.github.com/repos/Jhon-mark23/vpn/contents"
REPO_REF="ref=main"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
RAW_HEADER="Accept: application/vnd.github.raw"

# Helper function to download from private repo
download_private() {
    local remote_path="$1"
    local output_file="$2"
    curl -sS \
        -H "$AUTH_HEADER" \
        -H "$RAW_HEADER" \
        "${REPO_API}/${remote_path}?${REPO_REF}" \
        -o "$output_file"
}

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Global variables for safety and backup tracking
BACKUP_DIR="/root/ssh-vpn-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-vpn-install.log"

green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
NC='\e[0m'

# Map original logging functions to match your desired aio.sh style aliases
print_info()  { echo -e "[ ${green}INFO${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"; }
print_error() { echo -e "[ ${red}ERROR${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; }
print_warning(){ echo -e "[ ${yell}WARNING${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"; }
print_success(){ echo -e "[ ${blue}SUCCESS${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"; }

log_info()    { print_info "$1"; }
log_error()   { print_error "$1"; }
log_success() { print_success "$1"; }

# Dummy helpers to maintain structure seamlessly without missing functions
update_json() { :; }
add_error_to_json() { :; }
rollback_on_error() { print_error "Fatal error encountered during $1. Exiting."; exit 1; }

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

run_safety_and_backup() {
    print_info "Running safety checks and analyzing script port availability..."

    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi

    # Target Ports: 22, 80, 8443, 8444, 8445 (removed dropbear & squid ports)
    local used_ports=$(ss -tuln | grep -E ':(22|80|8443|8444|8445|81|8081)\s' || true)
    if [ -n "$used_ports" ]; then
        print_warning "Some required application ports are already active on this host:"
        echo -e "${yell}$used_ports${NC}"
        echo ""
    fi

    print_info "Creating systemic backup in $BACKUP_DIR ..."
    mkdir -p "$BACKUP_DIR"
    
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup" 2>/dev/null || true
    cp /etc/stunnel/stunnel.conf "$BACKUP_DIR/stunnel.conf.backup" 2>/dev/null || true
    cp /etc/default/stunnel4 "$BACKUP_DIR/stunnel4.backup" 2>/dev/null || true
    cp /etc/nginx/nginx.conf "$BACKUP_DIR/nginx.conf.backup" 2>/dev/null || true
    cp /etc/nginx/conf.d/status.conf "$BACKUP_DIR/nginx_status.backup" 2>/dev/null || true
    cp /etc/rc.local "$BACKUP_DIR/rc.local.backup" 2>/dev/null || true
    
    if command -v iptables-save &>/dev/null; then
        iptables-save > "$BACKUP_DIR/iptables.backup"
    fi

    cat > /root/vpn-rollback.sh <<EOF
#!/bin/bash
echo "=== System rollback in progress ==="

[ -f "$BACKUP_DIR/sshd_config.backup" ] && cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config && systemctl restart ssh 2>/dev/null
[ -f "$BACKUP_DIR/stunnel.conf.backup" ] && cp "$BACKUP_DIR/stunnel.conf.backup" /etc/stunnel/stunnel.conf
[ -f "$BACKUP_DIR/stunnel4.backup" ] && cp "$BACKUP_DIR/stunnel4.backup" /etc/default/stunnel4 && systemctl restart stunnel4 2>/dev/null
[ -f "$BACKUP_DIR/nginx.conf.backup" ] && cp "$BACKUP_DIR/nginx.conf.backup" /etc/nginx/nginx.conf
[ -f "$BACKUP_DIR/nginx_status.backup" ] && cp "$BACKUP_DIR/nginx_status.backup" /etc/nginx/conf.d/status.conf && systemctl restart nginx 2>/dev/null
[ -f "$BACKUP_DIR/rc.local.backup" ] && cp "$BACKUP_DIR/rc.local.backup" /etc/rc.local && chmod +x /etc/rc.local

# Stop and remove old services
systemctl stop dropbear 2>/dev/null
systemctl disable dropbear 2>/dev/null
systemctl stop squid 2>/dev/null
systemctl disable squid 2>/dev/null
systemctl stop ws-proxy 2>/dev/null
systemctl disable ws-proxy 2>/dev/null
rm -f /etc/systemd/system/ws-proxy.service
rm -rf /opt/ws-proxy

if [ -f "$BACKUP_DIR/iptables.backup" ]; then
    iptables-restore < "$BACKUP_DIR/iptables.backup"
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null
    fi
fi

systemctl daemon-reload
echo "=== System restored to original installation baseline ==="
EOF
    chmod +x /root/vpn-rollback.sh
    print_success "Backup preserved. Rollback script available at: /root/vpn-rollback.sh"
}

install_base_packages() {
    print_info "Installing base packages..."
    apt update -y || true
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true

    # REMOVED: dropbear, squid from packages list
    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates nginx stunnel4 fail2ban"
    for pkg in $packages; do
        if ! dpkg -l | grep -qE "^ii|^hi" "$pkg"; then
            print_info "Installing $pkg..."
            apt install -y $pkg -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || {
                print_warning "Failed to install $pkg, continuing..."
            }
        else
            print_info "$pkg already installed"
        fi
    done

    # REMOVED: Node.js installation (moved to insshws.sh)
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
# PROTOCOL 1: SSH (No Legacy Algorithms, Pure aio.sh Logic)
# ============================================================
configure_ssh() {
    log_info "Configuring SSH server..."
    update_json "ssh.status" "configuring"

    # Make the precise pre-change backup targeted by the validation block
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.pre_change"

    # Clean out any old custom configuration setups to avoid duplicates
    sed -i '/^Port /d' /etc/ssh/sshd_config
    sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
    sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
    sed -i '/^Banner /d' /etc/ssh/sshd_config

    # Apply standard dynamic baseline configurations via the request pattern
    echo "Port 22" >> /etc/ssh/sshd_config
    echo "Port 80" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    
    cat << 'EOF' >> /etc/ssh/sshd_config

    # --- MARCSCRIPT PROTOCOL COMPATIBILITY ENGINE ---
    # Key Exchange Algorithms (Legacy + Modern)
    KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
    
    # Ciphers (Legacy + Modern)
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc
    
    # MACs (Message Authentication Codes)
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,hmac-sha1,hmac-md5
    
    # Host Key Algorithms
    HostKeyAlgorithms ssh-ed25519,ssh-rsa,ssh-dss,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521
    
    # Public Key Algorithms
    PubkeyAcceptedAlgorithms ssh-ed25519,ssh-rsa,ssh-dss,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521
    EOF
    
    cat > /etc/ssh/ssh_banner <<'EOF'
<p style="text-align:center;">
<span style="color:#00E5FF;"><big><b>🚀 MARCSCRIPT SSH XRAY VPN 🚀</b></big></span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">
<big><b>FAST • STABLE • SECURE</b></big>
</span>
</p>

<p style="text-align:center;">
<span style="color:#00FF66;"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></span>
</p>

<p style="text-align:center;">
<span style="color:#00FFFF;"><b>📡 AVAILABLE PROTOCOLS</b></span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🔐 SSH DIRECT</span><br>
<span style="color:#00E5FF;">Port : 22</span><br>
<span style="color:#FFD600;">HTTP Custom users: If Port 22 fails, use HTTP Injector.</span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🔒 SSH + SSL (Stunnel)</span><br>
<span style="color:#00FF66;">Port : 8443</span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🌐 SSH + WebSocket</span><br>
<span style="color:#29B6F6;">Port : 8080</span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🔐 SSH + WS + SSL</span><br>
<span style="color:#00BCD4;">Port : 8445</span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🚀 XRAY TLS</span><br>
<span style="color:#00FF80;">Port : 443</span>
</p>

<p style="text-align:center;">
<span style="color:#FFFFFF;">🚀 XRAY NONE TLS</span><br>
<span style="color:#FFD54F;">Port : 80</span>
</p>

<p style="text-align:center;">
<span style="color:#00FF66;"><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></span>
</p>

<p style="text-align:center;">
<span style="color:#00FFFF;">
<big><b>⚡ MARCSCRIPT VPN ⚡</b></big>
</span>
</p>

<p style="text-align:center;">
<span style="color:#FFD54F;">
Facebook • Telegram • Fast Support
</span>
</p>
EOF
    
    echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
    # Backup first
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Append clean, compatible algorithms safely
    cat << 'EOF' >> /etc/ssh/sshd_config

# --- MARCSCRIPT PROTOCOL COMPATIBILITY ENGINE ---
KexAlgorithms +diffie-hellman-group-exchange-sha256
Ciphers +aes128-ctr,aes192-ctr,aes256-ctr
HostKeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
EOF

    # Validate configuration syntax cleanly
    sshd -t >> "$LOG_FILE" 2>&1 || {
        log_error "SSH config test failed"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        add_error_to_json "SSH config test failed"
        rollback_on_error "SSH configuration"
    }

    # Apply changes
    systemctl restart ssh >> "$LOG_FILE" 2>&1 || {
        log_error "Failed to restart SSH"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        systemctl restart ssh
        add_error_to_json "SSH restart failed"
        rollback_on_error "SSH restart"
    }

    # Verify run time status active validation block
    sleep 3
    if ! systemctl is-active --quiet ssh; then
        log_error "SSH not running after restart"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        systemctl restart ssh
        add_error_to_json "SSH not active"
        rollback_on_error "SSH verification"
    fi

    systemctl enable ssh >> "$LOG_FILE" 2>&1
    update_json "ssh.status" "running"
    log_success "SSH configured on ports 22 and 80"
}

# ============================================================
# PROTOCOL 2: SSH+SSL with maximum TLS compatibility
# ============================================================
configure_stunnel() {
    print_info "Configuring SSH+SSL (ports 8443, 8444, 8445) with broad TLS support..."

    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        print_info "Generating SSL certificate..."
        mkdir -p /etc/ssl/vpn /etc/stunnel
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/ssl/vpn/privkey.pem \
            -out /etc/ssl/vpn/fullchain.pem \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=MarcScript/CN=$(hostname -I | awk '{print $1}')" 2>/dev/null
        cat /etc/ssl/vpn/fullchain.pem /etc/ssl/vpn/privkey.pem > /etc/stunnel/stunnel.pem
    fi

    apt install -y stunnel4 2>/dev/null
    mkdir -p /var/log/stunnel4 /etc/stunnel /var/run/stunnel4

    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi
    chown -R stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown -R root:root /var/log/stunnel4
    chown -R stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown -R root:root /var/run/stunnel4
    chmod 755 /var/run/stunnel4
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true

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

sslVersion = all
options = NO_SSLv2
options = NO_SSLv3
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
    
    sleep 2
    if systemctl is-active --quiet stunnel4; then
        print_success "SSH+SSL on ports 8443, 8444, 8445 (TLS 1.0-1.3, broad ciphers)"
    else
        print_warning "Stunnel4 failed to start, checking logs..."
        journalctl -u stunnel4 --no-pager -n 5
    fi
}

# ============================================================
# REMOVED: configure_websocket() - Moved to insshws.sh
# REMOVED: configure_squid() - Squid Proxy removed
# REMOVED: configure_python_fallback() - No longer needed
# REMOVED: fix_squid() - No longer needed
# REMOVED: install_dropbear() - Dropbear removed
# ============================================================

# ============================================================
# PROTOCOL 6: BADVPN UDP Gateway
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN UDP gateway (7100-7400)..."
    cd /tmp
    # Download from private repo
    download_private "ssh/newudpgw" "/usr/bin/badvpn-udpgw"
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
port      = ssh,8443,8444,8445
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

download_scripts() {
    print_info "Downloading management scripts from private repo..."
    cd /usr/bin

    dl() {
        download_private "$2" "$1"
        chmod +x "$1"
        sed -i 's/\r$//' "$1"
    }

    dl menu menu/menu.sh
    dl m-xray menu/m-xray.sh
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

create_vpn_status() {
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
svc() { systemctl is-active --quiet "$1" && echo -e "\033[1;32m● Running\033[0m" || echo -e "\033[1;31m● Not Running\033[0m"; }
printf "%-28s : %s\n" "SSH (22, 80)" "$(svc ssh)"
printf "%-28s : %s\n" "Stunnel4 (8443,8444,8445)" "$(svc stunnel4)"
printf "%-28s : %s\n" "Nginx (81, 8081)" "$(svc nginx)"
printf "%-28s : %s\n" "Fail2Ban" "$(svc fail2ban)"
[ -f /etc/systemd/system/ws-proxy.service ] && printf "%-28s : %s\n" "WS-Proxy (8080)" "$(svc ws-proxy)"
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
===========================================
MARCSCRIPT SSH VPN CONNECTION GUIDE
===========================================
Server IP: $VPS_IP

PROTOCOLS:
1. SSH Direct: Port 22, 80
2. SSH+SSL (Stunnel): Port 8443, 8444
3. SSH+WS+SSL: Port 8445
4. BADVPN UDP: Port 7100-7400 (local)

MANAGEMENT:
- Type 'menu' to access management panel
- Type 'vpn-status' to check services
===========================================
EOF
    print_success "Guide saved to /root/ssh-connection-guide.txt"
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

restart_services() {
    print_info "Restarting all services..."
    for svc in nginx cron ssh stunnel4 fail2ban; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            systemctl restart $svc 2>/dev/null && print_success "Restarted $svc"
        fi
    done
    # Restart ws-proxy if exists (from insshws.sh)
    if systemctl list-unit-files | grep -q "^ws-proxy.service"; then
        systemctl restart ws-proxy 2>/dev/null && print_success "Restarted ws-proxy"
    fi
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

display_final_status() {
    VPS_IP=$(curl -s ifconfig.me || echo "unknown")
    clear
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ✅ MARCSCRIPT SSH-VPN INSTALLATION COMPLETE!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "📡 ALL PROTOCOLS ACTIVE:"
    echo ""
    echo "   🔹 SSH Direct      : $VPS_IP:22"
    echo "   🔹 SSH Direct 2    : $VPS_IP:80"
    echo "   🔹 SSH + SSL       : $VPS_IP:8443, 8444"
    echo "   🔹 SSH + WS + SSL  : wss://$VPS_IP:8445"
    echo "   🔹 BADVPN UDP      : 127.0.0.1:7100-7400"
    echo ""
    echo "🔧 MANAGEMENT COMMANDS:"
    echo "   menu              - Main management panel"
    echo "   vpn-status        - Check all services"
    echo "   usernew           - Create SSH user"
    echo "   trial             - Create trial user"
    echo "   cek               - Check user accounts"
    echo ""
    echo "📁 CONFIGURATION FILES:"
    echo "   SSH Config       : /etc/ssh/sshd_config"
    echo "   Stunnel Config   : /etc/stunnel/stunnel.conf"
    echo "   Nginx Config     : /etc/nginx/nginx.conf"
    echo ""
    echo "📋 LOG FILES:"
    echo "   SSH Logs         : journalctl -u ssh"
    echo "   Stunnel Logs     : /var/log/stunnel4/stunnel.log"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  💡 VPS IP: $VPS_IP"
    echo "  💡 Guide saved: /root/ssh-connection-guide.txt"
    echo "  💡 Rollback System: /root/vpn-rollback.sh"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

main() {
    clear
    echo "==========================================="
    echo "   MARCSCRIPT SSH VPN INSTALLER"
    echo "   (SSH + Stunnel + BADVPN - Lightweight)"
    echo "==========================================="

    detect_os
    setup_environment
    run_safety_and_backup
    install_base_packages
    setup_rclocal
    configure_ssh
    configure_stunnel
    # REMOVED: configure_websocket (moved to insshws.sh)
    # REMOVED: configure_squid
    # REMOVED: install_dropbear
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
    display_final_status

    print_success "Installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
}

main "$@"