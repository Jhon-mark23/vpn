#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER - XRAY COMPATIBLE
# (Clean Install: Remove old → Install fresh)
# Version: 3.0 (Remove & Reinstall)
# ============================================================

# ---------- GITHUB TOKEN ----------
gtoken=$(cat /root/token 2>/dev/null || cat /root/token.txt 2>/dev/null)

if [[ -z "$gtoken" ]]; then
    echo -e "\e[1;31mERROR: GitHub token not found in /root/token\e[0m"
    exit 1
fi

GITHUB_TOKEN="$gtoken"
REPO_API="https://api.github.com/repos/Jhon-mark23/vpn/contents"
REPO_REF="ref=main"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
RAW_HEADER="Accept: application/vnd.github.raw"

download_private() {
    local remote_path="$1"
    local output_file="$2"
    curl -sS -H "$AUTH_HEADER" -H "$RAW_HEADER" \
        "${REPO_API}/${remote_path}?${REPO_REF}" -o "$output_file"
}

export DEBIAN_FRONTEND=noninteractive

LOG_FILE="/var/log/marcscript-ssh-install.log"
ERROR_LOG="/var/log/marcscript-ssh-error.log"
> "$LOG_FILE"
> "$ERROR_LOG"

green='\e[0;32m'; yell='\e[1;33m'; red='\e[1;31m'; blue='\e[0;34m'; NC='\e[0m'

print_info()  { echo -e "[ ${green}INFO${NC} ] $1"; echo "[$(date '+%H:%M:%S')] [INFO] $1" >> "$LOG_FILE"; }
print_error() { echo -e "[ ${red}ERROR${NC} ] $1"; echo "[$(date '+%H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; echo "[ERROR] $1" >> "$ERROR_LOG"; }
print_ok()    { echo -e "[ ${blue}OK${NC} ] $1"; echo "[$(date '+%H:%M:%S')] [OK] $1" >> "$LOG_FILE"; }

# ============================================================
# REMOVE OLD SERVICES (Clean Slate)
# ============================================================
remove_old_services() {
    print_info "Removing old SSH-related services..."
    
    local services=(
        "dropbear" "squid" "ws-proxy" "ws-proxy-alt"
        "ws-dropbear" "ws-stunnel" "ws-8080" "ws-9445" "ws-9443"
        "stunnel4" "nginx" "fail2ban"
    )
    
    for svc in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            rm -f "/etc/systemd/system/${svc}.service"
            print_info "Removed: $svc"
        fi
    done
    
    # Kill processes
    pkill -f dropbear 2>/dev/null || true
    pkill -f squid 2>/dev/null || true
    pkill -f stunnel4 2>/dev/null || true
    pkill -f nginx 2>/dev/null || true
    pkill -f badvpn 2>/dev/null || true
    pkill -f ws- 2>/dev/null || true
    
    # Remove old configs
    rm -rf /etc/stunnel 2>/dev/null
    rm -rf /etc/squid 2>/dev/null
    rm -rf /etc/dropbear 2>/dev/null
    rm -rf /opt/ws-proxy 2>/dev/null
    rm -f /etc/nginx/conf.d/status.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/xray.conf 2>/dev/null
    
    # Purge packages
    apt remove --purge -y dropbear squid stunnel4 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    systemctl daemon-reload
    print_ok "Old services removed"
}

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID; VER=$VERSION_ID
    else
        print_error "Cannot detect OS"; exit 1
    fi
    print_info "OS: $OS $VER"
    [[ "$OS" != "ubuntu" && "$OS" != "debian" ]] && { print_error "Ubuntu/Debian only"; exit 1; }
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_info "Installing required packages..."
    apt update -y 2>/dev/null
    
    local packages="screen curl jq bzip2 gzip coreutils net-tools wget
        openssl ca-certificates nginx stunnel4 fail2ban
        iptables-persistent netfilter-persistent git"
    
    for pkg in $packages; do
        apt install -y "$pkg" 2>/dev/null || print_info "Skip: $pkg"
    done
    
    # Remove firewall
    apt remove --purge ufw firewalld exim4 -y 2>/dev/null || true
    
    print_ok "Packages installed"
}

# ============================================================
# CONFIGURE SSH (No duplicate algorithms)
# ============================================================
configure_ssh() {
    print_info "Configuring SSH..."
    
    # Clean existing config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
    
    cat > /etc/ssh/sshd_config <<'EOF'
# MARCSCRIPT SSH CONFIG
Port 22
Port 80
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication yes
UsePAM yes
MaxAuthTries 5
MaxSessions 10
ClientAliveInterval 60
ClientAliveCountMax 3
UseDNS no
PrintMotd no
Banner /etc/ssh/ssh_banner
Subsystem sftp /usr/lib/openssh/sftp-server

# Legacy + Modern Algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,aes256-cbc,aes192-cbc,aes128-cbc,3des-cbc
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,hmac-sha1
HostKeyAlgorithms ssh-ed25519,ssh-rsa,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521
PubkeyAcceptedAlgorithms ssh-ed25519,ssh-rsa,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521
EOF

    # Banner
    cat > /etc/ssh/ssh_banner <<'BEOF'
===========================================
   MARCSCRIPT VPN SERVER
   FAST • STABLE • SECURE
===========================================
   SSH Direct     : Port 22, 80
   SSH + SSL      : Port 8443, 8444
   SSH + WS       : Port 8080
   SSH + WS + SSL : Port 8445, 9443
===========================================
BEOF

    # Test config
    if ! sshd -t 2>/dev/null; then
        print_error "SSH config test failed!"
        sshd -t 2>&1 | tee -a "$ERROR_LOG"
        # Restore backup
        local latest_backup=$(ls -t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
        [[ -f "$latest_backup" ]] && cp "$latest_backup" /etc/ssh/sshd_config
        return 1
    fi
    
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    sleep 2
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        print_ok "SSH running on ports 22, 80"
    else
        print_error "SSH failed to start!"
        return 1
    fi
}

# ============================================================
# CONFIGURE STUNNEL
# ============================================================
configure_stunnel() {
    print_info "Configuring Stunnel4..."
    
    # Remove old
    apt remove --purge -y stunnel4 2>/dev/null || true
    apt install -y stunnel4 2>/dev/null
    
    mkdir -p /etc/stunnel /var/log/stunnel4 /var/run/stunnel4
    
    # Generate cert if missing
    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/stunnel/stunnel.pem \
            -out /etc/stunnel/stunnel.pem \
            -subj "/C=PH/ST=Manila/L=Manila/O=MarcScript/CN=$(hostname -I | awk '{print $1}')" 2>/dev/null
        chmod 600 /etc/stunnel/stunnel.pem
    fi
    
    cat > /etc/stunnel/stunnel.conf <<'EOF'
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3
ciphers = DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4

[ssh-ssl]
accept = 8443
connect = 127.0.0.1:22

[ssh-ssl-alt]
accept = 8444
connect = 127.0.0.1:22

[ws-ssl]
accept = 8445
connect = 127.0.0.1:8080
EOF

    echo 'ENABLED=1' > /etc/default/stunnel4
    
    systemctl daemon-reload
    systemctl enable stunnel4 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    sleep 2
    
    if systemctl is-active --quiet stunnel4; then
        print_ok "Stunnel4 running on 8443, 8444, 8445"
    else
        print_error "Stunnel4 failed!"
    fi
}

# ============================================================
# CONFIGURE NGINX
# ============================================================
configure_nginx() {
    print_info "Configuring Nginx..."
    
    apt install -y nginx 2>/dev/null
    rm -f /etc/nginx/sites-enabled/default
    
    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes 1;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    server_tokens off;
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
    location / { return 200 "MarcScript VPN"; }
}
EOF

    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
    systemctl enable nginx 2>/dev/null
    print_ok "Nginx on ports 81, 8081"
}

# ============================================================
# BADVPN
# ============================================================
install_badvpn() {
    print_info "Installing BADVPN..."
    download_private "ssh/newudpgw" "/usr/bin/badvpn-udpgw"
    chmod +x /usr/bin/badvpn-udpgw
    
    # Kill old
    pkill -f badvpn-udpgw 2>/dev/null || true
    
    for port in 7100 7200 7300 7400; do
        screen -dmS "badvpn$port" /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null
    done
    
    print_ok "BADVPN on 7100-7400"
}

# ============================================================
# FAIL2BAN
# ============================================================
install_fail2ban() {
    print_info "Installing Fail2Ban..."
    apt install -y fail2ban 2>/dev/null
    
    cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22,80,8443,8444,8445
EOF

    systemctl enable fail2ban 2>/dev/null
    systemctl restart fail2ban 2>/dev/null
    print_ok "Fail2Ban active"
}

# ============================================================
# DOWNLOAD SCRIPTS
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."
    cd /usr/bin
    
    dl() { download_private "$2" "$1" && chmod +x "$1" && sed -i 's/\r$//' "$1"; }
    
    dl menu        "menu/menu.sh"
    dl m-sshovpn   "menu/m-sshovpn.sh"
    dl m-xray      "menu/m-xray.sh"
    dl m-system    "menu/m-system.sh"
    dl running     "menu/running.sh"
    dl clearcache  "menu/clearcache.sh"
    
    dl usernew  "ssh/usernew.sh"
    dl trial    "ssh/trial.sh"
    dl renew    "ssh/renew.sh"
    dl hapus    "ssh/hapus.sh"
    dl cek      "ssh/cek.sh"
    dl member   "ssh/member.sh"
    dl delete   "ssh/delete.sh"
    dl autokill "ssh/autokill.sh"
    dl ceklim   "ssh/ceklim.sh"
    dl tendang  "ssh/tendang.sh"
    
    cd /
    print_ok "Scripts downloaded"
}

# ============================================================
# OPTIMIZE
# ============================================================
optimize_system() {
    print_info "Optimizing system..."
    
    # Sysctl tweaks
    cat >> /etc/sysctl.conf <<'EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 51200
EOF
    sysctl -p >/dev/null 2>&1
    
    # Swap
    if [ ! -f /swapfile ]; then
        fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Cron reboot
    echo "0 2 * * * root /sbin/reboot" > /etc/cron.d/vpn-reboot
    systemctl restart cron 2>/dev/null
    
    # Timezone
    timedatectl set-timezone Asia/Manila 2>/dev/null
    
    print_ok "System optimized"
}

# ============================================================
# DISPLAY RESULT
# ============================================================
display_result() {
    local IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
    
    clear
    echo ""
    echo "═══════════════════════════════════════════"
    echo "   ✅ SSH-VPN INSTALLATION COMPLETE!"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "  🔹 SSH Direct     : $IP:22, 80"
    echo "  🔹 SSH + SSL      : $IP:8443, 8444"
    echo "  🔹 SSH + WS + SSL : $IP:8445"
    echo "  🔹 BADVPN UDP     : 127.0.0.1:7100-7400"
    echo ""
    echo "  Commands:"
    echo "    menu         - Main menu"
    echo "    usernew      - Create SSH user"
    echo "    trial        - Create trial user"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Log: $LOG_FILE"
    echo "  Errors: $ERROR_LOG"
    echo "═══════════════════════════════════════════"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo "======================================="
    echo " MARCSCRIPT SSH-VPN INSTALLER v3.0"
    echo " (Remove Old → Install Fresh)"
    echo "======================================="
    echo ""
    
    [[ "$EUID" -ne 0 ]] && { echo "Run as root!"; exit 1; }
    
    detect_os
    
    # STEP 1: Remove old
    remove_old_services
    
    # STEP 2: Install fresh
    install_packages
    configure_ssh || { print_error "SSH config failed!"; exit 1; }
    configure_stunnel
    configure_nginx
    install_badvpn
    install_fail2ban
    optimize_system
    download_scripts
    display_result
    
    # Cleanup
    rm -f /root/ssh-vpn.sh 2>/dev/null
    print_ok "Done! Type 'menu' to start."
}

main "$@"