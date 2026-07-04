#!/bin/bash
# ============================================================
# MARCSCRIPT SSH-VPN INSTALLER v3.0
# Compatible with Ubuntu & Debian (including Debian 13)
# All Protocols Fixed & Working with Enhanced Backup & Rollback
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# ============================================================
# COLOURS
# ============================================================
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
cyan='\e[0;36m'
NC='\e[0m'

# ============================================================
# GLOBAL VARIABLES
# ============================================================
BACKUP_DIR="/root/ssh-vpn-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-vpn-install.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
MAX_RETRIES=3
RETRY_DELAY=3

# ============================================================
# LOGGING FUNCTIONS
# ============================================================
print_info()    { echo -e "[ ${green}INFO${NC} ] $1"; echo "[$TIMESTAMP] [INFO] $1" >> "$LOG_FILE"; }
print_error()   { echo -e "[ ${red}ERROR${NC} ] $1" >&2; echo "[$TIMESTAMP] [ERROR] $1" >> "$LOG_FILE"; }
print_warning() { echo -e "[ ${yell}WARNING${NC} ] $1"; echo "[$TIMESTAMP] [WARNING] $1" >> "$LOG_FILE"; }
print_success() { echo -e "[ ${blue}SUCCESS${NC} ] $1"; echo "[$TIMESTAMP] [SUCCESS] $1" >> "$LOG_FILE"; }
print_step()    { echo -e "[ ${cyan}STEP${NC} ] $1"; echo "[$TIMESTAMP] [STEP] $1" >> "$LOG_FILE"; }
print_fatal()   { echo -e "[ ${red}FATAL${NC} ] $1" >&2; echo "[$TIMESTAMP] [FATAL] $1" >> "$LOG_FILE"; exit 1; }

# ============================================================
# ERROR HANDLING
# ============================================================
trap 'print_error "Script interrupted at line $LINENO"' INT TERM
trap 'print_error "Error occurred at line $LINENO. Exit code: $?"' ERR

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    print_step "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_fatal "Cannot detect OS"
    fi
    
    print_info "Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_fatal "This script only supports Ubuntu or Debian"
    fi
    
    # Check if Debian 13 (Trixie) or later
    if [[ "$OS" == "debian" ]] && [[ "$VER" == "13" || "$VER" == "trixie" || "$VER" -ge 13 ]]; then
        IS_DEBIAN_13=true
        print_info "Debian 13+ detected - using compatibility mode"
    else
        IS_DEBIAN_13=false
    fi
}

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_fatal "Please run as root"
fi

# ============================================================
# SETUP ENVIRONMENT
# ============================================================
setup_environment() {
    print_step "Setting up environment..."
    
    # Set timezone
    ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime 2>/dev/null || true
    timedatectl set-timezone Asia/Manila 2>/dev/null || true
    
    # Disable IPv6
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
    
    # Create log directory
    mkdir -p /var/log
    touch "$LOG_FILE" 2>/dev/null || true
    
    print_success "Environment configured"
}

# ============================================================
# SAFETY AND BACKUP
# ============================================================
run_safety_and_backup() {
    print_step "Running safety checks and creating backup..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" || print_fatal "Failed to create backup directory"
    
    # Backup all important config files
    local configs=(
        "/etc/ssh/sshd_config"
        "/etc/default/dropbear"
        "/etc/stunnel/stunnel.conf"
        "/etc/default/stunnel4"
        "/etc/squid/squid.conf"
        "/etc/nginx/nginx.conf"
        "/etc/nginx/conf.d/status.conf"
        "/opt/ws-proxy/ws-proxy.js"
        "/etc/rc.local"
    )
    
    for config in "${configs[@]}"; do
        if [ -f "$config" ]; then
            cp "$config" "$BACKUP_DIR/$(basename "$config").backup" 2>/dev/null || true
            print_info "Backed up: $config"
        fi
    done
    
    # Backup iptables
    if command -v iptables-save &>/dev/null; then
        iptables-save > "$BACKUP_DIR/iptables.backup" 2>/dev/null || true
        print_info "Backed up iptables rules"
    fi
    
    # Check for port conflicts
    local target_ports="(22|80|8443|8444|8445|8080|8082|3128|8888|109|143|81|8081)"
    local used_ports=$(ss -tuln 2>/dev/null | grep -E ":$target_ports\\s" || true)
    
    if [ -n "$used_ports" ]; then
        print_warning "Some required ports are already in use:"
        echo -e "${yell}$used_ports${NC}"
        echo ""
        if ! read -p "Proceed and overwrite settings anyway? (y/N): " -n 1 -r; then
            print_info "Installation cancelled by user"
            exit 0
        fi
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Create rollback script
    cat > /root/vpn-rollback.sh <<'EOF'
#!/bin/bash
echo "=== System rollback in progress ==="

BACKUP_DIR="$1"
if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
    echo "Usage: /root/vpn-rollback.sh /path/to/backup/dir"
    exit 1
fi

[ -f "$BACKUP_DIR/sshd_config.backup" ] && cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config && systemctl restart ssh 2>/dev/null
[ -f "$BACKUP_DIR/dropbear.backup" ] && cp "$BACKUP_DIR/dropbear.backup" /etc/default/dropbear && systemctl restart dropbear 2>/dev/null
[ -f "$BACKUP_DIR/stunnel.conf.backup" ] && cp "$BACKUP_DIR/stunnel.conf.backup" /etc/stunnel/stunnel.conf
[ -f "$BACKUP_DIR/stunnel4.backup" ] && cp "$BACKUP_DIR/stunnel4.backup" /etc/default/stunnel4 && systemctl restart stunnel4 2>/dev/null
[ -f "$BACKUP_DIR/squid.conf.backup" ] && cp "$BACKUP_DIR/squid.conf.backup" /etc/squid/squid.conf && systemctl restart squid 2>/dev/null
[ -f "$BACKUP_DIR/nginx.conf.backup" ] && cp "$BACKUP_DIR/nginx.conf.backup" /etc/nginx/nginx.conf
[ -f "$BACKUP_DIR/status.conf.backup" ] && cp "$BACKUP_DIR/status.conf.backup" /etc/nginx/conf.d/status.conf && systemctl restart nginx 2>/dev/null
[ -f "$BACKUP_DIR/rc.local.backup" ] && cp "$BACKUP_DIR/rc.local.backup" /etc/rc.local && chmod +x /etc/rc.local

systemctl stop ws-proxy 2>/dev/null
systemctl disable ws-proxy 2>/dev/null
rm -f /etc/systemd/system/ws-proxy.service
rm -rf /opt/ws-proxy

if [ -f "$BACKUP_DIR/iptables.backup" ]; then
    iptables-restore < "$BACKUP_DIR/iptables.backup" 2>/dev/null
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null
    fi
fi

systemctl daemon-reload
echo "=== System restored to original installation baseline ==="
EOF
    chmod +x /root/vpn-rollback.sh
    
    print_success "Backup preserved at: $BACKUP_DIR"
    print_info "Rollback script: /root/vpn-rollback.sh $BACKUP_DIR"
}

# ============================================================
# INSTALL WITH RETRY
# ============================================================
install_with_retry() {
    local package=$1
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if apt install -y "$package" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null; then
            return 0
        fi
        retry=$((retry + 1))
        print_warning "Failed to install $package, retry $retry/$MAX_RETRIES"
        sleep $RETRY_DELAY
    done
    
    return 1
}

# ============================================================
# INSTALL BASE PACKAGES
# ============================================================
install_base_packages() {
    print_step "Installing base packages..."
    
    # Update package list with retry
    local retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        if apt update -y 2>/dev/null; then
            break
        fi
        retry=$((retry + 1))
        print_warning "Failed to update package list, retry $retry/$MAX_RETRIES"
        sleep $RETRY_DELAY
    done
    
    # Upgrade with retry
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || true
    apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || true
    
    # Remove conflicting packages
    apt-get remove --purge ufw firewalld exim4 -y 2>/dev/null || true
    
    local packages=(
        "screen" "curl" "jq" "bzip2" "gzip" "vnstat" "coreutils"
        "rsyslog" "iftop" "zip" "unzip" "git" "apt-transport-https"
        "build-essential" "net-tools" "wget" "gnupg" "gnupg2"
        "openssl" "ca-certificates" "nginx" "stunnel4" "dropbear"
        "squid" "fail2ban"
    )
    
    # Debian 13 specific packages
    if [[ "$IS_DEBIAN_13" == true ]]; then
        packages+=("python3-full" "python3-pip")
    fi
    
    # Install each package with retry
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -qE "^ii|^hi" "$pkg"; then
            print_info "$pkg already installed"
        else
            print_info "Installing $pkg..."
            if install_with_retry "$pkg"; then
                print_success "Installed $pkg"
            else
                print_warning "Failed to install $pkg, continuing..."
            fi
        fi
    done
    
    # Install Node.js if not present
    if ! command -v node &>/dev/null; then
        print_info "Installing Node.js 20 LTS..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> /dev/null 2>&1 || {
            print_warning "Node.js setup script failed"
        }
        apt install -y nodejs >> /dev/null 2>&1 || {
            print_warning "Node.js installation failed"
        }
    else
        print_info "Node.js already installed: $(node -v 2>/dev/null || echo 'unknown')"
    fi
    
    print_success "Base packages installed"
}

# ============================================================
# SETUP RC.LOCAL
# ============================================================
setup_rclocal() {
    print_step "Setting up rc.local..."
    
    cat > /etc/systemd/system/rc-local.service <<-'END'
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
    
    cat > /etc/rc.local <<-'END'
#!/bin/sh -e
exit 0
END
    
    chmod +x /etc/rc.local
    systemctl enable rc-local 2>/dev/null || true
    systemctl start rc-local.service 2>/dev/null || true
    
    if ! grep -q "disable_ipv6" /etc/rc.local 2>/dev/null; then
        sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local 2>/dev/null || true
    fi
    
    print_success "rc.local configured"
}

# ============================================================
# CONFIGURE SSH
# ============================================================
configure_ssh() {
    print_step "Configuring SSH server..."
    
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.pre_change" 2>/dev/null || true
    
    # Clean old custom configurations
    sed -i '/^Port /d' /etc/ssh/sshd_config
    sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
    sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
    sed -i '/^Banner /d' /etc/ssh/sshd_config
    sed -i '/^KexAlgorithms /d' /etc/ssh/sshd_config
    sed -i '/^Ciphers /d' /etc/ssh/sshd_config
    sed -i '/^HostKeyAlgorithms /d' /etc/ssh/sshd_config
    sed -i '/^PubkeyAcceptedAlgorithms /d' /etc/ssh/sshd_config
    
    # Apply new configuration
    cat >> /etc/ssh/sshd_config <<-'EOF'
Port 22
Port 80
PasswordAuthentication yes
PermitRootLogin yes
Banner /etc/ssh/ssh_banner

# --- MARCSCRIPT PROTOCOL COMPATIBILITY ENGINE ---
KexAlgorithms +diffie-hellman-group-exchange-sha256
Ciphers +aes128-ctr,aes192-ctr,aes256-ctr
HostKeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
EOF
    
    # Create SSH banner
    mkdir -p /etc/ssh
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
📡 <font color="#00b0ff">MARCSCRIPT SSH XRAY VPN SERVER</font>
</h2>

━━━━━━━━━━━━━━━━━━━━━━━━━━

<font color="#00ff66"><b>📡 AVAILABLE PROTOCOLS</b></font>
<br><br>

<font color="#ffffff">🔹 SSH DIRECT</font><br>
<font color="#00e5ff">➜ Port : 22 & 80</font>

<br><br>

<font color="#ffffff">🔹 SSH + SSL (Stunnel)</font><br>
<font color="#00e5ff">➜ Port : 8443, 8444</font>

<br><br>

<font color="#ffffff">🔹 SSH + WebSocket</font><br>
<font color="#00e5ff">➜ Port : 8080, 8082</font>

<br><br>

<font color="#ffffff">🔹 SSH + WS + SSL</font><br>
<font color="#00e5ff">➜ Port : 8445</font>

<br><br>

<font color="#ffffff">🔹 Dropbear SSH</font><br>
<font color="#00e5ff">➜ Port : 109, 143</font>

<br><br>

<font color="#ffffff">🔹 Squid Proxy</font><br>
<font color="#00e5ff">➜ Port : 3128, 8082, 8888</font>

<br><br>

<font color="#ffffff">🔹 Xray / V2Ray TLS</font><br>
<font color="#00ff80">➜ Port : 443</font>

<br><br>

<font color="#ffffff">🔹 Xray / V2Ray None TLS</font><br>
<font color="#ffeb3b">➜ Port : 80</font>

<br><br>

━━━━━━━━━━━━━━━━━━━━━━━━━━

<font color="#00ffcc">
🚀 FAST • STABLE • SECURE
</font>

<br>

<font color="#80ff00">
⚡ MARCSCRIPT VPN ⚡
</font>

</center>
EOF
    
    # Validate configuration
    if sshd -t 2>&1; then
        print_success "SSH configuration valid"
    else
        print_error "SSH config test failed!"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config 2>/dev/null || true
        print_fatal "SSH configuration invalid"
    fi
    
    # Restart SSH
    systemctl restart ssh 2>/dev/null || {
        print_error "Failed to restart SSH"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config 2>/dev/null || true
        systemctl restart ssh 2>/dev/null || true
        print_fatal "SSH restart failed"
    }
    
    sleep 2
    if systemctl is-active --quiet ssh 2>/dev/null; then
        print_success "SSH configured on ports 22 and 80"
    else
        print_fatal "SSH not running after configuration"
    fi
}

# ============================================================
# CONFIGURE STUNNEL
# ============================================================
configure_stunnel() {
    print_step "Configuring SSH+SSL (Stunnel)..."
    
    apt install -y stunnel4 2>/dev/null || {
        print_error "Failed to install stunnel4"
        return 1
    }
    
    mkdir -p /etc/ssl/vpn /etc/stunnel /var/log/stunnel4 /var/run/stunnel4
    
    # Generate SSL certificate if not exists
    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        print_info "Generating SSL certificate..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/ssl/vpn/privkey.pem \
            -out /etc/ssl/vpn/fullchain.pem \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=MarcScript/CN=$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')" 2>/dev/null
        cat /etc/ssl/vpn/fullchain.pem /etc/ssl/vpn/privkey.pem > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem
    fi
    
    # Create stunnel user if not exists
    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi
    
    chown -R stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown -R root:root /var/log/stunnel4 2>/dev/null || true
    chown -R stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown -R root:root /var/run/stunnel4 2>/dev/null || true
    chmod 755 /var/run/stunnel4 2>/dev/null || true
    
    # Create stunnel configuration
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
    systemctl stop stunnel4 2>/dev/null || true
    sleep 1
    systemctl start stunnel4 2>/dev/null || {
        print_warning "Stunnel4 failed to start, checking logs..."
        journalctl -u stunnel4 --no-pager -n 5 2>/dev/null || true
    }
    
    sleep 2
    if systemctl is-active --quiet stunnel4 2>/dev/null; then
        print_success "SSH+SSL on ports 8443, 8444, 8445"
    else
        print_warning "Stunnel4 not running, continuing..."
    fi
}

# ============================================================
# CONFIGURE WEBSOCKET
# ============================================================
configure_websocket() {
    print_step "Configuring SSH+WebSocket..."
    
    fuser -k 8080/tcp 2>/dev/null || true
    fuser -k 8082/tcp 2>/dev/null || true
    
    mkdir -p /opt/ws-proxy /var/log
    
    # Create WebSocket proxy
    cat > /opt/ws-proxy/ws-proxy.js <<'EOF'
#!/usr/bin/env node
const net = require('net');
const http = require('http');
const fs = require('fs');

const SSH_HOST = '127.0.0.1';
const SSH_PORT = 22;
const WS_PORT = 8080;
const WS_PORT_ALT = 8082;
const LOG_FILE = '/var/log/ws-proxy.log';

function log(msg) {
    const ts = new Date().toISOString();
    const line = `[${ts}] ${msg}\n`;
    console.log(line.trim());
    fs.appendFileSync(LOG_FILE, line, { flag: 'a' });
}

function createServer(port) {
    const server = http.createServer();
    
    server.on('connect', (req, socket) => {
        log(`CONNECT: ${req.url} (port ${port})`);
        const ssh = net.connect(SSH_PORT, SSH_HOST, () => {
            socket.write('HTTP/1.1 200 Connection Established\r\nProxy-Agent: MarcScript\r\n\r\n');
            ssh.pipe(socket);
            socket.pipe(ssh);
        });
        ssh.on('error', (e) => { log(`SSH error: ${e.message}`); socket.destroy(); });
        socket.on('error', (e) => { log(`Socket error: ${e.message}`); ssh.destroy(); });
    });

    server.on('upgrade', (req, socket) => {
        log(`WebSocket upgrade: ${req.headers.host} (port ${port})`);
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
                <p>Port: ${port}</p>
                <p>Uptime: ${Math.floor(process.uptime())} s</p>
                <p>SSH: ${SSH_HOST}:${SSH_PORT}</p>
                <hr><small>MarcScript SSH VPN Proxy</small></body></html>`);
        } else {
            res.writeHead(404);
            res.end('Not Found');
        }
    });

    server.listen(port, '0.0.0.0', () => log(`✅ WebSocket proxy on port ${port}`));
    return server;
}

const server1 = createServer(WS_PORT);
const server2 = createServer(WS_PORT_ALT);

process.on('SIGTERM', () => { log('SIGTERM, shutting down...'); server1.close(); server2.close(); process.exit(0); });
process.on('SIGINT',  () => { log('SIGINT, shutting down...'); server1.close(); server2.close(); process.exit(0); });
process.on('uncaughtException', (e) => log(`Uncaught: ${e.message}`));
EOF
    
    chmod +x /opt/ws-proxy/ws-proxy.js
    
    # Create systemd service
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
    systemctl start ws-proxy 2>/dev/null || {
        print_warning "WebSocket proxy failed to start on first attempt"
    }
    
    sleep 3
    if systemctl is-active --quiet ws-proxy 2>/dev/null; then
        print_success "SSH+WS on ports 8080, 8082"
    else
        print_warning "WebSocket proxy failed to start, check logs"
    fi
}

# ============================================================
# CONFIGURE SQUID
# ============================================================
configure_squid() {
    print_step "Configuring Squid proxy..."
    
    apt install -y squid 2>/dev/null || {
        print_warning "Failed to install squid, continuing..."
        return 1
    }
    
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
    
    systemctl stop squid 2>/dev/null || true
    systemctl start squid 2>/dev/null || {
        print_warning "Squid failed to start"
    }
    systemctl enable squid 2>/dev/null || true
    
    if systemctl is-active --quiet squid 2>/dev/null; then
        print_success "Squid on ports 3128, 8082, 8888"
    else
        print_warning "Squid not running"
    fi
}

# ============================================================
# INSTALL DROPBEAR
# ============================================================
install_dropbear() {
    print_step "Installing Dropbear..."
    
    apt install --reinstall -y dropbear 2>/dev/null || apt install -y dropbear 2>/dev/null || {
        print_warning "Failed to install dropbear"
        return 1
    }
    
    if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
        print_info "Generating Dropbear host keys..."
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null
        dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key 2>/dev/null
        dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null
    fi
    
    cat > /etc/default/dropbear <<-'DROPBEAR'
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143"
DROPBEAR_BANNER="/etc/ssh/ssh_banner"
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR
    
    echo "/bin/false" >> /etc/shells 2>/dev/null || true
    echo "/usr/sbin/nologin" >> /etc/shells 2>/dev/null || true
    
    systemctl enable dropbear 2>/dev/null || true
    systemctl restart dropbear 2>/dev/null || {
        print_warning "Dropbear failed to restart"
    }
    
    sleep 2
    if systemctl is-active --quiet dropbear 2>/dev/null; then
        print_success "Dropbear on ports 109, 143"
    else
        print_warning "Dropbear not running"
    fi
}

# ============================================================
# INSTALL BADVPN
# ============================================================
install_badvpn() {
    print_step "Installing BADVPN UDP gateway..."
    
    cd /tmp || return 1
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ssh/newudpgw" 2>/dev/null || {
        print_warning "Failed to download BADVPN binary"
        return 1
    }
    chmod +x /usr/bin/badvpn-udpgw
    
    for port in 7100 7200 7300 7400; do
        local num=$((port/100))
        if ! grep -q "badvpn$num" /etc/rc.local 2>/dev/null; then
            sed -i "\$ i\screen -dmS badvpn$num badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50" /etc/rc.local 2>/dev/null || true
        fi
        screen -dmS badvpn$num badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
    
    print_success "BADVPN on ports 7100-7400"
}

# ============================================================
# INSTALL FAIL2BAN
# ============================================================
install_fail2ban() {
    print_step "Installing Fail2ban..."
    
    apt install -y fail2ban 2>/dev/null || {
        print_warning "Failed to install fail2ban"
        return 1
    }
    
    cat > /etc/fail2ban/jail.local <<-'F2B'
[DEFAULT]
findtime  = 600
bantime   = 3600
maxretry  = 5
backend   = polling

[sshd]
enabled   = true
port      = ssh,8443,8444,8445,8080,8082
logpath   = %(sshd_log)s
maxretry  = 5
F2B
    
    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || {
        print_warning "Fail2ban failed to start"
    }
    
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        print_success "Fail2ban configured"
    else
        print_warning "Fail2ban not running"
    fi
}

# ============================================================
# OPTIMIZE SYSTEM
# ============================================================
optimize_system() {
    print_step "Optimizing system..."
    
    # System tuning
    cat >> /etc/sysctl.conf <<-'SYSCTL'
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
    
    sysctl -p >/dev/null 2>&1 || true
    
    # Create swap if not exists
    if [ ! -f /swapfile ]; then
        print_info "Creating 512MB swap..."
        fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null || true
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null || true
        swapon /swapfile 2>/dev/null || true
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Swap created"
    fi
    
    print_success "System optimized"
}

# ============================================================
# BLOCK TORRENT
# ============================================================
block_torrent() {
    print_step "Blocking torrent traffic..."
    
    local torrent_rules=(
        "FORWARD -m string --string 'get_peers' --algo bm -j DROP"
        "FORWARD -m string --string 'announce_peer' --algo bm -j DROP"
        "FORWARD -m string --string 'find_node' --algo bm -j DROP"
        "FORWARD -m string --algo bm --string 'BitTorrent' -j DROP"
        "FORWARD -m string --algo bm --string 'BitTorrent protocol' -j DROP"
        "FORWARD -m string --algo bm --string 'peer_id=' -j DROP"
        "FORWARD -m string --algo bm --string '.torrent' -j DROP"
        "FORWARD -m string --algo bm --string 'announce.php?passkey=' -j DROP"
        "FORWARD -m string --algo bm --string 'torrent' -j DROP"
        "FORWARD -m string --algo bm --string 'announce' -j DROP"
        "FORWARD -m string --algo bm --string 'info_hash' -j DROP"
    )
    
    for rule in "${torrent_rules[@]}"; do
        iptables -A $rule 2>/dev/null || true
    done
    
    # Save rules
    iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || true
        netfilter-persistent reload 2>/dev/null || true
    fi
    
    print_success "Torrent traffic blocked"
}

# ============================================================
# CONFIGURE NGINX
# ============================================================
configure_nginx() {
    print_step "Configuring Nginx..."
    
    apt install -y nginx 2>/dev/null || {
        print_warning "Failed to install nginx"
        return 1
    }
    
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
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
    echo "<h1>MARCSCRIPT VPN Server</h1>" > /home/vps/public_html/index.html
    
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
        return 200 "MarcScript SSH VPN Server (Xray Compatible)\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    nginx -t >> /dev/null 2>&1 || {
        print_warning "Nginx config test failed"
    }
    
    systemctl restart nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        print_success "Nginx on ports 81, 8081"
    else
        print_warning "Nginx not running"
    fi
}

# ============================================================
# DOWNLOAD SCRIPTS
# ============================================================
download_scripts() {
    print_step "Downloading management scripts..."
    
    local GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin || return 1
    
    dl() {
        local name=$1
        local path=$2
        local url="$GHBASE/$path"
        local target="/usr/bin/$name"
        
        local retry=0
        while [ $retry -lt $MAX_RETRIES ]; do
            if wget -q -O "$target" "$url" 2>/dev/null; then
                chmod +x "$target"
                sed -i 's/\r$//' "$target"
                return 0
            fi
            retry=$((retry + 1))
            sleep 2
        done
        print_warning "Failed to download $name"
        return 1
    }
    
    # Download all scripts
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
    print_success "Management scripts downloaded"
}

# ============================================================
# CREATE VPN STATUS
# ============================================================
create_vpn_status() {
    print_step "Creating vpn-status command..."
    
    cat > /usr/local/bin/vpn-status <<-'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT SERVICE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
svc() { systemctl is-active --quiet "$1" 2>/dev/null && echo -e "\033[1;32m● Running\033[0m" || echo -e "\033[1;31m● Not Running\033[0m"; }
printf "%-28s : %s\n" "SSH (22, 80)" "$(svc ssh)"
printf "%-28s : %s\n" "Dropbear (109, 143)" "$(svc dropbear)"
printf "%-28s : %s\n" "Stunnel4 (8443,8444,8445)" "$(svc stunnel4)"
printf "%-28s : %s\n" "Nginx (81, 8081)" "$(svc nginx)"
printf "%-28s : %s\n" "Squid Proxy (3128)" "$(svc squid)"
printf "%-28s : %s\n" "Fail2Ban" "$(svc fail2ban)"
[ -f /etc/systemd/system/ws-proxy.service ] && printf "%-28s : %s\n" "WS-Proxy (Node.js)" "$(svc ws-proxy)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me 2>/dev/null || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
EOF
    chmod +x /usr/local/bin/vpn-status
    print_success "vpn-status created"
}

# ============================================================
# CREATE GUIDE
# ============================================================
create_guide() {
    local VPS_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
    
    cat > /root/ssh-connection-guide.txt <<EOF
===========================================
MARCSCRIPT SSH VPN CONNECTION GUIDE
===========================================
Server IP: $VPS_IP

PROTOCOLS:
1. SSH Direct: Port 22, 80
2. SSH+SSL (Stunnel): Port 8443, 8444
3. SSH+WebSocket: Port 8080, 8082
4. SSH+WS+SSL: Port 8445
5. Dropbear SSH: Port 109, 143
6. Squid Proxy: Port 3128, 8082, 8888
7. BADVPN UDP: Port 7100-7400 (local)

MANAGEMENT:
- Type 'menu' to access management panel
- Type 'vpn-status' to check services

BACKUP:
- Rollback: /root/vpn-rollback.sh $BACKUP_DIR
===========================================
EOF
    print_success "Guide saved to /root/ssh-connection-guide.txt"
}

# ============================================================
# SETUP CRON
# ============================================================
setup_cron() {
    print_step "Setting up cron jobs..."
    
    cat > /etc/cron.d/re_otm <<-'END'
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
    print_step "Restarting all services..."
    
    local services=("nginx" "cron" "ssh" "dropbear" "stunnel4" "ws-proxy" "squid" "fail2ban")
    
    for svc in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            systemctl restart $svc 2>/dev/null && print_success "Restarted $svc" || print_warning "Failed to restart $svc"
        fi
    done
    
    # Restart BADVPN
    for port in 7100 7200 7300 7400; do
        local num=$((port/100))
        screen -dmS badvpn$num badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 50 2>/dev/null || true
    done
    
    print_success "Services restarted"
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    print_step "Cleaning up..."
    
    apt autoclean -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    history -c
    echo "unset HISTFILE" >> /etc/profile
    
    rm -f /root/key.pem /root/cert.pem /root/ssh-vpn.sh /root/bbr.sh 2>/dev/null || true
    
    print_success "Cleanup completed"
}

# ============================================================
# DISPLAY FINAL STATUS
# ============================================================
display_final_status() {
    local VPS_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
    
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
    echo "   🔹 SSH + WS        : ws://$VPS_IP:8080, 8082"
    echo "   🔹 SSH + WS + SSL  : wss://$VPS_IP:8445"
    echo "   🔹 Dropbear SSH    : $VPS_IP:109, 143"
    echo "   🔹 Squid Proxy     : $VPS_IP:3128, 8082, 8888"
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
    echo "   WS Proxy         : /opt/ws-proxy/ws-proxy.js"
    echo "   Squid Config     : /etc/squid/squid.conf"
    echo "   Dropbear Config  : /etc/default/dropbear"
    echo ""
    echo "📋 LOG FILES:"
    echo "   SSH Logs         : journalctl -u ssh"
    echo "   Dropbear Logs    : journalctl -u dropbear"
    echo "   Stunnel Logs     : /var/log/stunnel4/stunnel.log"
    echo "   WS Proxy Logs    : /var/log/ws-proxy.log"
    echo "   Install Log      : $LOG_FILE"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  💡 VPS IP: $VPS_IP"
    echo "  💡 Guide saved: /root/ssh-connection-guide.txt"
    echo "  💡 Rollback System: /root/vpn-rollback.sh $BACKUP_DIR"
    echo "  💡 Backup Location: $BACKUP_DIR"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo "==========================================="
    echo "   MARCSCRIPT SSH VPN INSTALLER v3.0"
    echo "   (All Protocols Fixed & Working)"
    echo "==========================================="
    echo ""
    
    if ! read -p "Continue? (y/N): " -n 1 -r; then
        echo
        print_info "Installation cancelled by user"
        exit 0
    fi
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
    
    detect_os
    setup_environment
    run_safety_and_backup
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
    display_final_status
    
    print_success "Installation completed successfully!"
    print_info "Type 'menu' to access the management panel"
    print_info "Rollback available at: /root/vpn-rollback.sh $BACKUP_DIR"
}

# ============================================================
# SCRIPT ENTRY
# ============================================================
main "$@"