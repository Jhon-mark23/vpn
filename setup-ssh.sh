#!/bin/bash
# ============================================================
# MARCSCRIPT SSH VPN SETUP - XRAY/V2RAY COMPATIBLE
# All ports changed to avoid conflicts:
#   - SSH Direct: 22, 2222 (Xray safe)
#   - SSH SSL: 8443, 8444 (Xray uses 443)
#   - SSH WS: 8080, 8082 (Xray safe)
#   - SSH WSS: 8445 (Xray safe)
#   - Squid Proxy: 3128, 8082, 8888 (Xray safe)
#   - API: 3021 (Xray safe)
# ============================================================

set -e  # Exit on any error

# ------------------------------------------------------------
# Global settings
# ------------------------------------------------------------
BACKUP_DIR="/root/ssh-vpn-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-vpn-install.log"
JSON_FILE="/etc/marcscript-vpn-config.json"
INSTALL_ID=$(date +%Y%m%d_%H%M%S)
API_PORT=3021

# Xray compatible ports
SSH_DIRECT_PORTS="22, 2222"
SSH_SSL_PORTS="8443, 8444"
SSH_WS_PORTS="8080, 8082"
SSH_WSS_PORT="8445"
SQUID_PORTS="3128, 8082, 8888"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

# ------------------------------------------------------------
# JSON helpers
# ------------------------------------------------------------
init_json() {
    cat > "$JSON_FILE" <<EOF
{
    "installation": {
        "id": "$INSTALL_ID",
        "timestamp": "$(date -Iseconds)",
        "status": "running",
        "vps_ip": "$(curl -s ifconfig.me || echo 'unknown')"
    },
    "ssh": {
        "ports": [$SSH_DIRECT_PORTS],
        "status": "pending"
    },
    "ssl": {
        "stunnel_ports": [$SSH_SSL_PORTS],
        "status": "pending"
    },
    "websocket": {
        "ports": [$SSH_WS_PORTS],
        "status": "pending"
    },
    "wss": {
        "port": $SSH_WSS_PORT,
        "status": "pending"
    },
    "squid": {
        "ports": [$SQUID_PORTS],
        "status": "pending"
    },
    "api": {
        "port": $API_PORT,
        "status": "pending"
    },
    "system": {
        "architecture": "",
        "os": "",
        "kernel": ""
    },
    "errors": [],
    "warnings": []
}
EOF
}

# ------------------------------------------------------------
# Safety & pre‑checks
# ------------------------------------------------------------
safety_check() {
    log_info "Running safety checks..."

    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    if ! systemctl is-active --quiet ssh; then
        log_warn "SSH service is not running. Attempting to start..."
        systemctl start ssh
        sleep 2
        if ! systemctl is-active --quiet ssh; then
            log_error "SSH cannot be started. Aborting."
            exit 1
        fi
    fi

    for cmd in curl wget lsof ss systemctl openssl; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command '$cmd' not found."
            exit 1
        fi
    done

    local free_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 500000 ]; then
        log_warn "Low disk space: $((free_space/1024)) MB free"
    fi

    # Check for port conflicts (Xray safe ports)
    local used_ports=$(ss -tuln | grep -E ':(22|2222|8443|8444|8445|8080|8082|3128|8888|3021)' || true)
    if [ -n "$used_ports" ]; then
        log_warn "Some required ports are already in use:"
        echo "$used_ports"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Installation aborted by user."
            exit 1
        fi
    fi

    echo ""
    echo "⚠️  This script will install and configure (Xray Compatible):"
    echo "   - SSH Direct     : $SSH_DIRECT_PORTS"
    echo "   - SSH over SSL   : $SSH_SSL_PORTS"
    echo "   - SSH WebSocket  : $SSH_WS_PORTS"
    echo "   - SSH WSS        : $SSH_WSS_PORT"
    echo "   - Squid Proxy    : $SQUID_PORTS"
    echo "   - Management API : $API_PORT"
    echo ""
    echo "✅ Xray uses: 80, 443, 81 - NO CONFLICT!"
    echo ""
    read -p "Proceed with installation? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Installation aborted by user."
        exit 1
    fi

    log_info "Creating backup in $BACKUP_DIR ..."
    mkdir -p "$BACKUP_DIR"
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup" 2>/dev/null || true
    cp /etc/stunnel/stunnel.conf "$BACKUP_DIR/stunnel.conf.backup" 2>/dev/null || true
    cp /etc/default/stunnel4 "$BACKUP_DIR/stunnel4.backup" 2>/dev/null || true
    cp /etc/squid/squid.conf "$BACKUP_DIR/squid.conf.backup" 2>/dev/null || true

    cat > "$BACKUP_DIR/rollback.sh" <<'EOF'
#!/bin/bash
echo "=== Full rollback in progress ==="
[ -f "$BACKUP_DIR/sshd_config.backup" ] && cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config
[ -f "$BACKUP_DIR/stunnel.conf.backup" ] && cp "$BACKUP_DIR/stunnel.conf.backup" /etc/stunnel/stunnel.conf
[ -f "$BACKUP_DIR/stunnel4.backup" ] && cp "$BACKUP_DIR/stunnel4.backup" /etc/default/stunnel4
[ -f "$BACKUP_DIR/squid.conf.backup" ] && cp "$BACKUP_DIR/squid.conf.backup" /etc/squid/squid.conf
systemctl restart ssh stunnel4 squid 2>/dev/null || true
echo "=== Rollback complete. ==="
EOF
    chmod +x "$BACKUP_DIR/rollback.sh"
    log_info "Backup created at $BACKUP_DIR"
}

rollback_on_error() {
    log_error "Installation failed! Rolling back..."
    [ -f "$BACKUP_DIR/rollback.sh" ] && bash "$BACKUP_DIR/rollback.sh"
    exit 1
}

# ------------------------------------------------------------
# Package installation
# ------------------------------------------------------------
install_packages() {
    log_info "Installing required packages..."
    apt update -y >> "$LOG_FILE" 2>&1 || true

    PACKAGES="openssh-server stunnel4 curl wget lsof squid ufw openssl net-tools jq python3 python3-pip"
    for pkg in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            log_info "Installing $pkg..."
            apt install -y $pkg >> "$LOG_FILE" 2>&1 || {
                log_error "Failed to install $pkg"
                rollback_on_error
            }
        fi
    done

    # Node.js for WebSocket proxy
    if ! command -v node &>/dev/null; then
        log_info "Installing Node.js 20 LTS..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
        apt install -y nodejs >> "$LOG_FILE" 2>&1 || {
            log_warn "Node.js installation failed, WebSocket may not work"
        }
    fi

    log_success "Packages installed"
}

# ------------------------------------------------------------
# SSH configuration - Xray Compatible
# ------------------------------------------------------------
configure_ssh() {
    log_info "Configuring SSH server (Xray compatible)..."
    update_json "ssh.status" "configuring"

    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.pre_change"

    # Ensure port 22 is enabled
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
    # Add port 2222 (Xray safe)
    if ! grep -q "^Port 2222" /etc/ssh/sshd_config; then
        echo "Port 2222" >> /etc/ssh/sshd_config
    fi

    # Enable password auth & root login
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

    echo "MarcScript SSH VPN Server (Xray Compatible)" > /etc/ssh/ssh_banner
    if ! grep -q "Banner" /etc/ssh/sshd_config; then
        echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
    fi

    sshd -t >> "$LOG_FILE" 2>&1 || {
        log_error "SSH config test failed"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        rollback_on_error
    }

    systemctl restart ssh >> "$LOG_FILE" 2>&1 || {
        log_error "Failed to restart SSH"
        cp "$BACKUP_DIR/sshd_config.pre_change" /etc/ssh/sshd_config
        rollback_on_error
    }

    systemctl enable ssh >> "$LOG_FILE" 2>&1
    update_json "ssh.status" "running"
    log_success "SSH configured on ports $SSH_DIRECT_PORTS"
}

# ------------------------------------------------------------
# Stunnel SSL - Xray Compatible (uses 8443, 8444 instead of 443)
# ------------------------------------------------------------
configure_stunnel() {
    log_info "Configuring Stunnel SSL (Xray compatible - ports $SSH_SSL_PORTS)..."

    apt install -y stunnel4 2>/dev/null
    update_json "ssl.status" "configuring"

    mkdir -p /var/log/stunnel4
    mkdir -p /etc/stunnel
    mkdir -p /var/run/stunnel4

    if ! id "stunnel4" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
    fi

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
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=MarcScript/CN=localhost" \
        2>/dev/null
    cat /tmp/stunnel-key.pem /tmp/stunnel-cert.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
    rm -f /tmp/stunnel-key.pem /tmp/stunnel-cert.pem
    cd

    cat > /etc/stunnel/stunnel.conf <<EOF
; Stunnel4 Config - Xray Compatible
; Xray uses 443, we use 8443, 8444, 8445
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

    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4

    mkdir -p /etc/systemd/system/stunnel4.service.d/
    cat > /etc/systemd/system/stunnel4.service.d/override.conf <<-EOF
[Service]
RuntimeDirectory=stunnel4
RuntimeDirectoryMode=0755
ExecStartPre=/bin/mkdir -p /var/run/stunnel4
ExecStartPre=/bin/chown stunnel4:stunnel4 /var/run/stunnel4
EOF

    systemctl daemon-reload
    systemctl enable stunnel4 >> "$LOG_FILE" 2>&1
    systemctl stop stunnel4 2>/dev/null; sleep 1
    systemctl start stunnel4 >> "$LOG_FILE" 2>&1 || {
        log_error "Failed to start Stunnel"
        rollback_on_error
    }

    update_json "ssl.status" "running"
    log_success "Stunnel configured on ports $SSH_SSL_PORTS and 8445"
}

# ------------------------------------------------------------
# WebSocket proxy (Node.js) - Xray Compatible
# ------------------------------------------------------------
configure_websocket() {
    log_info "Configuring WebSocket proxy (Xray compatible - ports $SSH_WS_PORTS)..."

    update_json "websocket.status" "configuring"

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
    systemctl enable ws-proxy >> "$LOG_FILE" 2>&1
    systemctl start ws-proxy >> "$LOG_FILE" 2>&1

    sleep 3
    if ! systemctl is-active --quiet ws-proxy; then
        log_warn "WebSocket proxy failed on port 8080, trying 8082..."
        sed -i 's/WS_PORT = 8080;/WS_PORT = 8082;/' /opt/ws-proxy/ws-proxy.js
        systemctl restart ws-proxy >> "$LOG_FILE" 2>&1
        sleep 2
        if systemctl is-active --quiet ws-proxy; then
            log_warn "WebSocket proxy started on alternate port 8082"
        else
            log_error "WebSocket proxy failed on all ports"
            rollback_on_error
        fi
    fi

    update_json "websocket.status" "running"
    log_success "WebSocket proxy configured on ports $SSH_WS_PORTS"
}

# ------------------------------------------------------------
# Squid proxy - Xray Compatible
# ------------------------------------------------------------
configure_squid() {
    log_info "Configuring Squid proxy (Xray compatible - ports $SQUID_PORTS)..."

    apt install -y squid 2>/dev/null
    update_json "squid.status" "configuring"

    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf "$BACKUP_DIR/squid.conf.backup"

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
    squid -z >> "$LOG_FILE" 2>&1 || true

    systemctl restart squid >> "$LOG_FILE" 2>&1 || {
        log_error "Failed to start Squid"
        rollback_on_error
    }
    systemctl enable squid >> "$LOG_FILE" 2>&1

    update_json "squid.status" "running"
    log_success "Squid proxy configured on ports $SQUID_PORTS"
}

# ------------------------------------------------------------
# Management API on port 3021
# ------------------------------------------------------------
configure_api() {
    log_info "Configuring Management API on port $API_PORT..."

    mkdir -p /opt/marcscript-api

    cat > /opt/marcscript-api/api.js <<'EOF'
#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const { exec } = require('child_process');

const API_PORT = 3021;
const LOG_FILE = '/var/log/marcscript-api.log';
const CONFIG_FILE = '/etc/marcscript-vpn-config.json';

function log(msg) {
    const ts = new Date().toISOString();
    const line = `[${ts}] ${msg}\n`;
    console.log(line.trim());
    fs.appendFileSync(LOG_FILE, line, { flag: 'a' });
}

function readJson(file) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function getBackupDir() {
    const dirs = fs.readdirSync('/root').filter(d => d.startsWith('ssh-vpn-backup-'));
    if (dirs.length === 0) return null;
    dirs.sort().reverse();
    return '/root/' + dirs[0];
}

function runRollback(res) {
    const backupDir = getBackupDir();
    if (!backupDir) {
        res.writeHead(500);
        res.end('No backup found');
        return;
    }
    const script = backupDir + '/rollback.sh';
    if (!fs.existsSync(script)) {
        res.writeHead(500);
        res.end('Rollback script not found');
        return;
    }
    exec(`bash ${script}`, (error, stdout, stderr) => {
        if (error) {
            res.writeHead(500);
            res.end('Rollback failed: ' + error.message);
        } else {
            res.writeHead(200);
            res.end('Rollback completed successfully');
        }
    });
}

const server = http.createServer((req, res) => {
    const url = req.url;
    log(`Request: ${req.method} ${url}`);

    if (url === '/status' && req.method === 'GET') {
        const data = readJson(CONFIG_FILE);
        if (data) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(data, null, 2));
        } else {
            res.writeHead(500);
            res.end('Cannot read config');
        }
        return;
    }

    if (url === '/reset' && req.method === 'POST') {
        runRollback(res);
        return;
    }

    if (url === '/ping' && req.method === 'GET') {
        res.writeHead(200);
        res.end('pong');
        return;
    }

    if (url === '/' || url === '/help') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<html><head><title>MarcScript API</title></head>
            <body><h1>🔧 MarcScript API</h1>
            <p>Available endpoints:</p>
            <ul>
                <li><b>GET /status</b> – JSON configuration</li>
                <li><b>POST /reset</b> – trigger full rollback</li>
                <li><b>GET /ping</b> – health check</li>
            </ul>
            <p>Port: ${API_PORT}</p>
            <hr><small>MarcScript SSH VPN</small></body></html>`);
        return;
    }

    res.writeHead(404);
    res.end('Not Found');
});

server.listen(API_PORT, '127.0.0.1', () => {
    log(`✅ Management API running on port ${API_PORT} (localhost only)`);
});

process.on('SIGTERM', () => { log('SIGTERM, shutting down...'); server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { log('SIGINT, shutting down...');  server.close(() => process.exit(0)); });
process.on('uncaughtException', (e) => log(`Uncaught: ${e.message}`));
EOF

    chmod +x /opt/marcscript-api/api.js

    cat > /etc/systemd/system/marcscript-api.service <<EOF
[Unit]
Description=MarcScript Management API
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node /opt/marcscript-api/api.js
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable marcscript-api >> "$LOG_FILE" 2>&1
    systemctl start marcscript-api >> "$LOG_FILE" 2>&1 || {
        log_error "Management API failed to start"
        rollback_on_error
    }

    log_success "Management API running on localhost:$API_PORT"
}

# ------------------------------------------------------------
# Firewall
# ------------------------------------------------------------
configure_firewall() {
    log_info "Configuring firewall (Xray compatible)..."

    if command -v ufw &>/dev/null; then
        ufw --force reset >> "$LOG_FILE" 2>&1
        for p in 22 2222 8443 8444 8445 8080 8082 3128 8888; do
            ufw allow ${p}/tcp >> "$LOG_FILE" 2>&1
        done
        ufw allow from 127.0.0.1 to any port $API_PORT >> "$LOG_FILE" 2>&1
        ufw --force enable >> "$LOG_FILE" 2>&1
        log_success "UFW configured"
    else
        log_warn "UFW not installed, skipping firewall"
    fi
}

# ------------------------------------------------------------
# Management scripts
# ------------------------------------------------------------
create_management_scripts() {
    log_info "Creating management scripts..."

    cat > /usr/local/bin/create <<'EOF'
#!/bin/bash
clear
echo "==================================="
echo "   MARCSCRIPT SSH VPN USER MAKER"
echo "==================================="
read -p "Username : " USER
read -p "Password : " PASS
read -p "Expire (days) : " DAYS

if id "$USER" &>/dev/null; then
    echo "❌ User already exists!"
    exit 1
fi
useradd -m -s /bin/bash "$USER"
echo "$USER:$PASS" | chpasswd
EXPIRE_DATE=$(date -d "$DAYS days" +"%Y-%m-%d")
chage -E "$EXPIRE_DATE" "$USER"

clear
echo "==================================="
echo "   ✅ SSH VPN ACCOUNT CREATED"
echo "==================================="
echo " Username : $USER"
echo " Password : $PASS"
echo " Expires  : $EXPIRE_DATE"
echo "-----------------------------------"
echo " SSH DIRECT  : 22, 2222"
echo " SSH SSL     : 8443, 8444"
echo " SSH WS      : 8080, 8082"
echo " SSH WSS     : 8445"
echo " SQUID PROXY : 3128, 8082, 8888"
echo " API         : localhost:3021"
echo "==================================="
EOF
    chmod +x /usr/local/bin/create

    cat > /usr/local/bin/wsproxy <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status) systemctl $1 ws-proxy ;;
    logs) journalctl -u ws-proxy -f ;;
    kill) fuser -k 8080/tcp 2>/dev/null; fuser -k 8082/tcp 2>/dev/null; echo "Killed WebSocket ports" ;;
    *) echo "Usage: wsproxy {start|stop|restart|status|logs|kill}" ;;
esac
EOF
    chmod +x /usr/local/bin/wsproxy

    cat > /usr/local/bin/api <<'EOF'
#!/bin/bash
case "$1" in
    start|stop|restart|status) systemctl $1 marcscript-api ;;
    logs) journalctl -u marcscript-api -f ;;
    reset) curl -X POST http://localhost:3021/reset ;;
    status) curl -s http://localhost:3021/status | jq . ;;
    ping) curl -s http://localhost:3021/ping ;;
    *) echo "Usage: api {start|stop|restart|status|logs|reset|status|ping}" ;;
esac
EOF
    chmod +x /usr/local/bin/api

    cat > /usr/local/bin/vpn-status <<'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "   MARCSCRIPT VPN SERVICE STATUS (Xray Compatible)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "SSH Server      : $(systemctl is-active ssh)   (22, 2222)"
echo "Stunnel SSL     : $(systemctl is-active stunnel4)   (8443, 8444, 8445)"
echo "WebSocket Proxy : $(systemctl is-active ws-proxy)   (8080/8082)"
echo "Squid Proxy     : $(systemctl is-active squid)   (3128, 8082, 8888)"
echo "API             : $(systemctl is-active marcscript-api)   (localhost:3021)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Commands: create - Create SSH user | wsproxy - WS management | vpn-status - This"
EOF
    chmod +x /usr/local/bin/vpn-status

    log_success "Management scripts created"
}

# ------------------------------------------------------------
# Create connection guide
# ------------------------------------------------------------
create_guide() {
    VPS_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "unknown")

    cat > /root/ssh-connection-guide.txt <<EOF
===========================================
   MARCSCRIPT SSH VPN CONNECTION GUIDE
   (Xray/V2Ray Compatible)
===========================================

VPS IP: $VPS_IP

===========================================
SSH DIRECT
===========================================
ssh -p 22 root@$VPS_IP
ssh -p 2222 root@$VPS_IP

===========================================
SSH OVER SSL (Stunnel4)
===========================================
ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8443 -quiet" root@$VPS_IP
ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8444 -quiet" root@$VPS_IP

===========================================
SSH OVER WEBSOCKET
===========================================
ssh -o ProxyCommand="websocat ws://$VPS_IP:8080" root@$VPS_IP
ssh -o ProxyCommand="websocat ws://$VPS_IP:8082" root@$VPS_IP

===========================================
SSH OVER WSS (WebSocket + SSL)
===========================================
ssh -o ProxyCommand="openssl s_client -connect $VPS_IP:8445 -quiet" root@$VPS_IP

===========================================
SSH + PAYLOAD + REMOTE PROXY
===========================================
SSH Host: $VPS_IP
SSH Port: 22 or 2222
Proxy: HTTP $VPS_IP:3128 (or 8082, 8888)
Payload: custom headers (client-side)

===========================================
SSH + SSL + PAYLOAD + REMOTE PROXY
===========================================
SSH Host: $VPS_IP
SSH Port: 8443 or 8444
SSL: ON
Proxy: HTTP $VPS_IP:3128 (or 8082, 8888)
Payload: custom headers (client-side)

===========================================
MANAGEMENT
===========================================
create       - Create SSH user
wsproxy      - Manage WebSocket proxy
vpn-status   - Check service status

===========================================
XRAY COMPATIBILITY
===========================================
✅ No port conflicts with Xray/V2Ray
✅ Xray uses: 80, 443, 81
✅ SSH uses: 22, 2222, 8443, 8444, 8445, 8080, 8082
===========================================
EOF

    log_success "Connection guide saved to /root/ssh-connection-guide.txt"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
main() {
    init_json
    safety_check
    install_packages
    configure_ssh
    configure_stunnel
    configure_websocket
    configure_squid
    configure_api
    configure_firewall
    create_management_scripts
    create_guide

    clear
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ✅ MARCSCRIPT SSH VPN INSTALLATION COMPLETE!"
    echo "   (Xray/V2Ray Compatible)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "📡 CONNECTION METHODS:"
    echo ""
    echo "   SSH Direct     : 22, 2222"
    echo "   SSH SSL        : 8443, 8444"
    echo "   SSH WS         : 8080, 8082"
    echo "   SSH WSS        : 8445"
    echo "   HTTP Proxy     : 3128, 8082, 8888"
    echo ""
    echo "🔧 MANAGEMENT COMMANDS:"
    echo "   create         - Create new SSH user"
    echo "   wsproxy        - Manage WebSocket proxy"
    echo "   api            - Control API service (port $API_PORT)"
    echo "   vpn-status     - Check service status"
    echo ""
    echo "📁 Backup: $BACKUP_DIR"
    echo "   Rollback: $BACKUP_DIR/rollback.sh"
    echo ""
    echo "⚠️  Xray uses: 80, 443, 81 - NO CONFLICT!"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  💡 VPS IP: $(curl -s ifconfig.me || echo 'unknown')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    log_success "Installation completed successfully!"
}

# Trap errors
trap 'rollback_on_error "Unexpected error"' ERR

# Run
main "$@"