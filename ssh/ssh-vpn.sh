#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER 
# SSH: 22, 2222 | SSL: 8443-8445 | WS: 8080 | Dropbear: 109,143
# DNSTT compatible (SSH 2222)
# ============================================================

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

BACKUP_DIR="/root/ssh-vpn-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-vpn-install.log"

green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
NC='\e[0m'

print_info()  { echo -e "[ ${green}INFO${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"; }
print_error() { echo -e "[ ${red}ERROR${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; }
print_warning(){ echo -e "[ ${yell}WARNING${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"; }
print_success(){ echo -e "[ ${blue}SUCCESS${NC} ] $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"; }

log_info()    { print_info "$1"; }
log_error()   { print_error "$1"; }
log_success() { print_success "$1"; }

update_json() { :; }
add_error_to_json() { :; }
rollback_on_error() { print_error "Fatal error encountered during $1. Exiting."; exit 1; }

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
    print_info "Running safety checks and backup..."

    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi

    local used_ports=$(ss -tuln | grep -E ':(22|2222|8443|8444|8445|8080|109|143)\s' || true)
    if [ -n "$used_ports" ]; then
        print_warning "Some ports already in use:"
        echo -e "${yell}$used_ports${NC}"
        echo ""
        read -p "Proceed anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Installation aborted."
            exit 1
        fi
    fi

    mkdir -p "$BACKUP_DIR"
    cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/default/dropbear "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/stunnel/stunnel.conf "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/default/stunnel4 "$BACKUP_DIR/" 2>/dev/null || true
    cp /opt/ws-proxy/ws-proxy.js "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/rc.local "$BACKUP_DIR/" 2>/dev/null || true
    iptables-save > "$BACKUP_DIR/iptables.backup" 2>/dev/null || true

    cat > /root/vpn-rollback.sh <<EOF
#!/bin/bash
echo "=== Rollback in progress ==="
[ -f "$BACKUP_DIR/sshd_config" ] && cp "$BACKUP_DIR/sshd_config" /etc/ssh/sshd_config && systemctl restart ssh
[ -f "$BACKUP_DIR/dropbear" ] && cp "$BACKUP_DIR/dropbear" /etc/default/dropbear && systemctl restart dropbear
[ -f "$BACKUP_DIR/stunnel.conf" ] && cp "$BACKUP_DIR/stunnel.conf" /etc/stunnel/stunnel.conf
[ -f "$BACKUP_DIR/stunnel4" ] && cp "$BACKUP_DIR/stunnel4" /etc/default/stunnel4 && systemctl restart stunnel4
[ -f "$BACKUP_DIR/ws-proxy.js" ] && cp "$BACKUP_DIR/ws-proxy.js" /opt/ws-proxy/ws-proxy.js && systemctl restart ws-proxy
[ -f "$BACKUP_DIR/iptables.backup" ] && iptables-restore < "$BACKUP_DIR/iptables.backup"
systemctl daemon-reload
echo "Rollback complete"
EOF
    chmod +x /root/vpn-rollback.sh
    print_success "Backup saved. Rollback: /root/vpn-rollback.sh"
}

install_base_packages() {
    print_info "Installing base packages..."
    apt update -y
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true

    local packages="screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential net-tools wget gnupg gnupg2 iptables-persistent netfilter-persistent openssl ca-certificates stunnel4 dropbear fail2ban"
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
# PROTOCOL 1: SSH (ports 22, 2222)
# ============================================================
configure_ssh() {
    log_info "Configuring SSH server..."
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.pre_change"

    sed -i '/^Port /d' /etc/ssh/sshd_config
    sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
    sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
    sed -i '/^Banner /d' /etc/ssh/sshd_config

    echo "Port 22" >> /etc/ssh/sshd_config
    echo "Port 2222" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

    # Banner (simplified)
    cat > /etc/ssh/ssh_banner <<'EOF'
        <center>
        
        <h1>
        🚀
        <font color="#00b0ff">M</font><font color="#29b6f6">A</font><font color="#4fc3f7">R</font><font color="#81d4fa">C</font><font color="#b3e5fc">S</font><font color="#4dd0e1">C</font><font color="#26c6da">R</font><font color="#00acc1">I</font><font color="#0097a7">P</font><font color="#00838f">T</font>
        🚀
        </h1>
        
        <font color="#00e5ff">
        ███████╗███████╗██╗  ██╗
        </font><br>
        <font color="#4dd0e1">
        ██╔════╝██╔════╝██║  ██║
        </font><br>
        <font color="#80deea">
        ███████╗███████╗███████║
        </font><br>
        <font color="#b2ebf2">
        ╚════██║╚════██║██╔══██║
        </font><br>
        <font color="#e0f7fa">
        ███████║███████║██║  ██║
        </font><br>
        <font color="#ffffff">
        ╚══════╝╚══════╝╚═╝  ╚═╝
        </font>
        
        <br><br>
        
        <font color="#ffff00"><b>CONNECTING...</b></font>
        
        <br>
        
        <font color="#ffff00">██████░░░░ 20%</font><br>
        <font color="#bfff00">██████████░░ 40%</font><br>
        <font color="#76ff03">██████████████░░ 60%</font><br>
        <font color="#00e676">██████████████████░░ 80%</font><br>
        <font color="#00e5ff">████████████████████ 100%</font>
        
        <br><br>
        
        <font color="#2962ff">🅒</font>
        <font color="#2979ff">🅞</font>
        <font color="#448aff">🅝</font>
        <font color="#64b5f6">🅝</font>
        <font color="#82b1ff">🅔</font>
        <font color="#80deea">🅒</font>
        <font color="#26c6da">🅣</font>
        <font color="#00acc1">🅔</font>
        <font color="#00e5ff">🅓</font>
        
        <br><br>
        
        <h2>
        📡 <font color="#00b0ff">MARCSCRIPT SSH  XRAY VPN SERVER</font>
        </h2>
        
        ━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        <font color="#00ff66"><b>📡 AVAILABLE PROTOCOLS</b></font>
        <br><br>
        
        <font color="#ffffff">🔹 SSH DIRECT</font><br>
        <font color="#00e5ff">➜ Port : 22 </font>
        <br>
        <font color="#00e5ff">NOTE: If you using HTTP CUSTOM and has error in Port 22 direct use HTTP INJECTOR</font>
        
        <br><br>
        
        <font color="#ffffff">🔹 SSH + SSL (Stunnel)</font><br>
        <font color="#00e5ff">➜ Port : 8443 </font>
        
        <br><br>
        
        <font color="#ffffff">🔹 SSH + WebSocket</font><br>
        <font color="#00e5ff">➜ Port : 8080 </font>
        
        <br><br>
        
        <font color="#ffffff">🔹 SSH + WS + SSL</font><br>
        <font color="#00e5ff">➜ Port : 8445</font>
        
        <br><br>
        
        <font color="#ffffff">🔹 Xray / V2Ray TLS</font><br>
        <font color="#00ff80">➜ Port : 443</font>
        
        <br><br>
        
        <font color="#ffffff">🔹 Xray / V2Ray None TLS</font><br>
        <font color="#ffeb3b">➜ Port : 80</font>
        
        <br><br>
        
        
        <font color="#00ffcc">
                    🚀 FAST • STABLE • SECURE
        </font>
        
        <br>
        
        <font color="#80ff00">
                ⚡ MARCSCRIPT VPN ⚡
        </font>
        
        </center>
EOF
    echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    cat << 'EOF' >> /etc/ssh/sshd_config

# --- MARCSCRIPT PROTOCOL COMPATIBILITY ---
KexAlgorithms +diffie-hellman-group-exchange-sha256
Ciphers +aes128-ctr,aes192-ctr,aes256-ctr
HostKeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
EOF

    sshd -t >> "$LOG_FILE" 2>&1 || {
        log_error "SSH config test failed"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        rollback_on_error "SSH configuration"
    }

    systemctl restart ssh >> "$LOG_FILE" 2>&1 || {
        log_error "Failed to restart SSH"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        systemctl restart ssh
        rollback_on_error "SSH restart"
    }

    sleep 3
    if ! systemctl is-active --quiet ssh; then
        log_error "SSH not running"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        systemctl restart ssh
        rollback_on_error "SSH verification"
    fi

    systemctl enable ssh >> "$LOG_FILE" 2>&1
    log_success "SSH on ports 22, 2222"
}

# ============================================================
# PROTOCOL 2: SSH+SSL (Stunnel direct – 8443, 8444, 8445)
# ============================================================
configure_stunnel() {
    print_info "Configuring SSH+SSL (direct ports 8443, 8444, 8445)..."

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

[ssh-ssl-alt]
accept = 8444
connect = 127.0.0.1:22

[ws-ssl]
accept = 8445
connect = 127.0.0.1:8080
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
        print_success "Stunnel on 8443, 8444, 8445"
    else
        print_warning "Stunnel failed – check logs: journalctl -u stunnel4"
    fi
}

# ============================================================
# PROTOCOL 3: SSH+WS (Node.js, port 8080)
# ============================================================
configure_websocket() {
    print_info "Configuring SSH+WS (port 8080)..."
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
    fs.appendFileSync(LOG_FILE, `[${ts}] ${msg}\n`);
}

log('Starting SSH WebSocket Proxy...');
const server = http.createServer();

server.on('connect', (req, socket) => {
    log(`CONNECT: ${req.url}`);
    const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
        socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
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

server.listen(WS_PORT, '0.0.0.0', () => log(`WebSocket proxy on port ${WS_PORT}`));
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
        print_warning "WS proxy failed on 8080, trying 8088..."
        sed -i 's/8080/8088/' /opt/ws-proxy/ws-proxy.js
        systemctl restart ws-proxy
        systemctl is-active --quiet ws-proxy && print_success "SSH+WS on port 8088" || print_error "WS proxy failed"
    fi
}

# ============================================================
# PROTOCOL 4: Dropbear (109, 143)
# ============================================================
install_dropbear() {
    print_info "Installing Dropbear..."
    apt install --reinstall -y dropbear 2>/dev/null || apt install -y dropbear
    if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null
        dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key 2>/dev/null
        dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null
    fi
    cat > /etc/default/dropbear <<-DROPBEAR
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143"
DROPBEAR_BANNER="/etc/ssh/ssh_banner"
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR
    systemctl enable dropbear 2>/dev/null || true
    systemctl restart dropbear 2>/dev/null || true
    sleep 2
    systemctl is-active --quiet dropbear && print_success "Dropbear on 109, 143" || print_error "Dropbear failed!"
}

# ============================================================
# FAIL2BAN
# ============================================================
install_fail2ban() {
    print_info "Installing Fail2ban..."
    apt install -y fail2ban 2>/dev/null
    cat > /etc/fail2ban/jail.local <<-F2B
[DEFAULT]
findtime = 600
bantime  = 3600
maxretry = 5
backend  = polling
[sshd]
enabled  = true
port     = ssh,2222,8443,8444,8445,8080
logpath  = %(sshd_log)s
F2B
    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true
    print_success "Fail2ban configured"
}

# ============================================================
# SYSTEM OPTIMIZATION & TORRENT BLOCK
# ============================================================
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
        fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Swap created"
    fi
}

block_torrent() {
    print_info "Blocking torrent..."
    iptables -A FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --string "announce" --algo bm -j DROP 2>/dev/null || true
    iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
}

# ============================================================
# DOWNLOAD SCRIPTS, STATUS, GUIDE, CRON
# (same as before)
# ============================================================
download_scripts() {
    print_info "Downloading management scripts..."
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    dl() { wget -q -O "$1" "$GHBASE/$2" && chmod +x "$1" && sed -i 's/\r$//' "$1"; }
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
    print_success "Management scripts downloaded"
}

create_vpn_status() {
    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
svc() { systemctl is-active --quiet "$1" && echo -e "\033[1;32m● Running\033[0m" || echo -e "\033[1;31m● Not Running\033[0m"; }
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
printf "%-28s : %s\n" "SSH (22, 2222)" "$(svc ssh)"
printf "%-28s : %s\n" "Dropbear (109,143)" "$(svc dropbear)"
printf "%-28s : %s\n" "Stunnel4 (8443-8445)" "$(svc stunnel4)"
printf "%-28s : %s\n" "WS-Proxy (8080)" "$(svc ws-proxy)"
printf "%-28s : %s\n" "Fail2Ban" "$(svc fail2ban)"
echo "═══════════════════════════════════════════════════════════════"
echo "  IP: $(curl -s ifconfig.me 2>/dev/null || echo 'unknown')"
EOF
    chmod +x /usr/local/bin/vpn-status
}

create_guide() {
    VPS_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_VPS_IP")
    cat > /root/ssh-connection-guide.txt <<EOF
=====================================
MARCSCRIPT SSH VPN GUIDE
=====================================
Server IP: $VPS_IP

PROTOCOLS:
  SSH Direct    : $VPS_IP:22, 2222
  SSH + SSL     : $VPS_IP:8443, 8444
  SSH + WS      : ws://$VPS_IP:8080
  SSH + WS + SSL: wss://$VPS_IP:8445
  Dropbear      : $VPS_IP:109, 143

XRAY (via Nginx):
  VMess WS      : $VPS_IP:80/vmess
  VMess WS TLS  : $VPS_IP:443/vmess
  VLESS WS TLS  : $VPS_IP:443/vless
  gRPC          : $VPS_IP:443 (vless-grpc, etc.)

PROXY (run insshws.sh):
  Squid         : $VPS_IP:3128, 8082, 8888
  BADVPN UDP    : 127.0.0.1:7100-7400

DNSTT:
  DNS Tunnel    : UDP 5300 → SSH 2222
=====================================
EOF
    print_success "Guide saved to /root/ssh-connection-guide.txt"
}

setup_cron() {
    cat > /etc/cron.d/re_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
END
    echo "7" > /home/re_otm
    systemctl restart cron 2>/dev/null || true
}

restart_services() {
    print_info "Restarting all services..."
    for svc in ssh dropbear stunnel4 ws-proxy fail2ban; do
        systemctl restart $svc 2>/dev/null && print_success "Restarted $svc"
    done
}

cleanup() {
    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    history -c
    echo "unset HISTFILE" >> /etc/profile
    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null
}

display_final_status() {
    VPS_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_VPS_IP")
    clear
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ✅ MARCSCRIPT SSH-VPN INSTALLED (OLD PORTS)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "📡 PROTOCOLS:"
    echo "   SSH Direct      : $VPS_IP:22, 2222"
    echo "   SSH + SSL       : $VPS_IP:8443, 8444"
    echo "   SSH + WS        : ws://$VPS_IP:8080"
    echo "   SSH + WS + SSL  : wss://$VPS_IP:8445"
    echo "   Dropbear        : $VPS_IP:109, 143"
    echo ""
    echo "📌 Nginx (run nginx-setup.sh) handles Xray on 80/443"
    echo "📌 DNSTT (run install-dnstt.sh) uses SSH port 2222"
    echo ""
    echo "🔧 Commands: menu, vpn-status, usernew, trial, cek"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Rollback: /root/vpn-rollback.sh"
    echo "  Guide:   /root/ssh-connection-guide.txt"
    echo "═══════════════════════════════════════════════════════════════"
}

main() {
    clear
    echo "==========================================="
    echo "   MARCSCRIPT SSH VPN INSTALLER"
    echo "   (Old Direct Ports – DNSTT Ready)"
    echo "==========================================="
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

    detect_os
    setup_environment
    run_safety_and_backup
    install_base_packages
    setup_rclocal
    configure_ssh
    configure_stunnel
    configure_websocket
    install_dropbear
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

    print_success "Installation complete!"
    print_info "Next: nginx-setup.sh → insshws.sh → ins-xray.sh → install-dnstt.sh"
}

main "$@"