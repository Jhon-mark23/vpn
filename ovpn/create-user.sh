#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN USER CREATOR WITH TLS SUPPORT
# Creates OVPN users with expiration + download URLs
# Supports: Direct TCP, Direct UDP, TLS over Stunnel
# ============================================================

# Colors (matching your existing style)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}OK${NC} ] $1"; }

# Configuration
OVPN_DIR="/etc/openvpn"
OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CERT_DIR="/etc/ssl/vpn"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Ports
OVPN_TCP_PORT="1194"       # Direct TCP
OVPN_UDP_PORT="2200"       # Direct UDP
OVPN_TLS_PORT="4443"       # Via Stunnel (TLS wrapped)
OVPN_TLS_ALT_PORT="4444"   # Via Stunnel alternate

# Nginx web server for downloads
NGINX_PORT="81"
WEB_DIR="/home/vps/public_html/ovpn"
USER_DB="$OVPN_CLIENT_DIR/users.db"

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Check if OpenVPN is installed
if [ ! -d "$EASYRSA_DIR" ]; then
    print_error "OpenVPN not installed. Run install-ovpn.sh first!"
    exit 1
fi

clear
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}              👤 MARCSCRIPT OVPN USER CREATOR                 ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p " Username : " username
read -p " Password : " password
read -p " Duration (days) : " days

# Validate input
if [ -z "$username" ] || [ -z "$password" ] || [ -z "$days" ]; then
    print_error "All fields are required!"
    exit 1
fi

# Validate days is a number
if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    print_error "Days must be a number!"
    exit 1
fi

# Check if user exists
if [ -f "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" ]; then
    print_error "User $username already exists!"
    read -p "Renew instead? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash /root/ovpn/renew-user.sh "$username" "$days"
        exit 0
    fi
    exit 1
fi

print_info "Creating OpenVPN user: $username ($days days)..."

# Create user directory
mkdir -p "$OVPN_CLIENT_DIR/$username"

cd "$EASYRSA_DIR"

# Generate client certificate
print_info "Generating certificates..."
./easyrsa --batch gen-req "$username" nopass 2>/dev/null
./easyrsa --batch sign-req client "$username" 2>/dev/null

# Copy certificates
cp "$EASYRSA_DIR/pki/ca.crt" "$OVPN_CLIENT_DIR/$username/"
cp "$EASYRSA_DIR/pki/issued/$username.crt" "$OVPN_CLIENT_DIR/$username/"
cp "$EASYRSA_DIR/pki/private/$username.key" "$OVPN_CLIENT_DIR/$username/"
cp "$OVPN_DIR/ta.key" "$OVPN_CLIENT_DIR/$username/" 2>/dev/null

# Calculate expiration date
EXPIRE_DATE=$(date -d "+$days days" +"%Y-%m-%d")
CREATED_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Detect OpenVPN version for compatibility
OVPN_VERSION=$(openvpn --version 2>/dev/null | head -1 | awk '{print $2}' | cut -d. -f1,2)
if [[ "$OVPN_VERSION" =~ ^2\.[6-9] ]] || [[ "$OVPN_VERSION" =~ ^2\.[1-9][0-9] ]]; then
    CIPHER_LINE="data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC"
else
    CIPHER_LINE="# OpenVPN $OVPN_VERSION compatible"
fi

# ============================================================
# CREATE CLIENT CONFIG FILES
# ============================================================

# 1. Direct TCP Config
print_info "Creating TCP config..."
cat > "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN Configuration
# User: $username
# Protocol: TCP (Direct)
# Created: $CREATED_DATE
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP:$OVPN_TCP_PORT
# ============================================

client
dev tun
proto tcp
remote $SERVER_IP $OVPN_TCP_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
$CIPHER_LINE
compress lz4-v2
key-direction 1
verb 3

<ca>
$(cat $OVPN_CLIENT_DIR/$username/ca.crt)
</ca>

<cert>
$(cat $OVPN_CLIENT_DIR/$username/$username.crt)
</cert>

<key>
$(cat $OVPN_CLIENT_DIR/$username/$username.key)
</key>

<tls-auth>
$(cat $OVPN_CLIENT_DIR/$username/ta.key)
</tls-auth>
EOF

# 2. Direct UDP Config
print_info "Creating UDP config..."
cat > "$OVPN_CLIENT_DIR/$username/$username-udp.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN Configuration
# User: $username
# Protocol: UDP (Direct)
# Created: $CREATED_DATE
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP:$OVPN_UDP_PORT
# ============================================

client
dev tun
proto udp
remote $SERVER_IP $OVPN_UDP_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
$CIPHER_LINE
compress lz4-v2
key-direction 1
verb 3

<ca>
$(cat $OVPN_CLIENT_DIR/$username/ca.crt)
</ca>

<cert>
$(cat $OVPN_CLIENT_DIR/$username/$username.crt)
</cert>

<key>
$(cat $OVPN_CLIENT_DIR/$username/$username.key)
</key>

<tls-auth>
$(cat $OVPN_CLIENT_DIR/$username/ta.key)
</tls-auth>
EOF

# 3. TLS over Stunnel Config (uses existing Stunnel certificate)
print_info "Creating TLS config..."
cat > "$OVPN_CLIENT_DIR/$username/$username-tls.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN Configuration
# User: $username
# Protocol: TCP over TLS (Stunnel Wrapper)
# Created: $CREATED_DATE
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP:$OVPN_TLS_PORT
# ============================================

client
dev tun
proto tcp
remote $SERVER_IP $OVPN_TLS_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
$CIPHER_LINE
compress lz4-v2
key-direction 1
verb 3

<ca>
$(cat $OVPN_CLIENT_DIR/$username/ca.crt)
</ca>

<cert>
$(cat $OVPN_CLIENT_DIR/$username/$username.crt)
</cert>

<key>
$(cat $OVPN_CLIENT_DIR/$username/$username.key)
</key>

<tls-auth>
$(cat $OVPN_CLIENT_DIR/$username/ta.key)
</tls-auth>
EOF

# 4. TLS Alternate Config
cat > "$OVPN_CLIENT_DIR/$username/$username-tls-alt.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN Configuration
# User: $username
# Protocol: TCP over TLS (Stunnel Wrapper Alt)
# Created: $CREATED_DATE
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP:$OVPN_TLS_ALT_PORT
# ============================================

client
dev tun
proto tcp
remote $SERVER_IP $OVPN_TLS_ALT_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
$CIPHER_LINE
compress lz4-v2
key-direction 1
verb 3

<ca>
$(cat $OVPN_CLIENT_DIR/$username/ca.crt)
</ca>

<cert>
$(cat $OVPN_CLIENT_DIR/$username/$username.crt)
</cert>

<key>
$(cat $OVPN_CLIENT_DIR/$username/$username.key)
</key>

<tls-auth>
$(cat $OVPN_CLIENT_DIR/$username/ta.key)
</tls-auth>
EOF

# ============================================================
# CREATE DOWNLOAD WEB DIRECTORY
# ============================================================
print_info "Setting up download links..."
mkdir -p "$WEB_DIR/$username"

# Copy configs to web directory
cp "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" "$WEB_DIR/$username/"
cp "$OVPN_CLIENT_DIR/$username/$username-udp.ovpn" "$WEB_DIR/$username/"
cp "$OVPN_CLIENT_DIR/$username/$username-tls.ovpn" "$WEB_DIR/$username/"
cp "$OVPN_CLIENT_DIR/$username/$username-tls-alt.ovpn" "$WEB_DIR/$username/"

# Create index page for downloads
cat > "$WEB_DIR/$username/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>MarcScript VPN - $username</title>
    <style>
        body { font-family: Arial; max-width: 600px; margin: 50px auto; padding: 20px; }
        .card { border: 2px solid #2196F3; border-radius: 10px; padding: 20px; margin: 10px 0; }
        .btn { display: block; background: #2196F3; color: white; padding: 10px; text-align: center; 
               text-decoration: none; border-radius: 5px; margin: 5px 0; }
        .btn:hover { background: #0b7dda; }
        .tls { background: #4CAF50; }
        .tls:hover { background: #45a049; }
        h2 { color: #2196F3; }
        .info { background: #f5f5f5; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <h2>🔐 MarcScript VPN Configurations</h2>
    <div class="info">
        <strong>Username:</strong> $username<br>
        <strong>Expires:</strong> $EXPIRE_DATE<br>
        <strong>Server:</strong> $SERVER_IP
    </div>
    
    <div class="card">
        <h3>📡 Direct Connections</h3>
        <a href="$username-tcp.ovpn" class="btn" download>⬇️ Download TCP Config (Port $OVPN_TCP_PORT)</a>
        <a href="$username-udp.ovpn" class="btn" download>⬇️ Download UDP Config (Port $OVPN_UDP_PORT)</a>
    </div>
    
    <div class="card">
        <h3>🔐 TLS/SSL Connections (Stunnel Wrapper)</h3>
        <a href="$username-tls.ovpn" class="btn tls" download>⬇️ Download TLS Config (Port $OVPN_TLS_PORT)</a>
        <a href="$username-tls-alt.ovpn" class="btn tls" download>⬇️ Download TLS Alt Config (Port $OVPN_TLS_ALT_PORT)</a>
    </div>
</body>
</html>
EOF

# Create user info file
cat > "$OVPN_CLIENT_DIR/$username/$username.info" <<EOF
====================================
MarcScript OpenVPN Account
====================================
Username    : $username
Password    : $password
Created     : $CREATED_DATE
Expires     : $EXPIRE_DATE
Duration    : $days days
Server IP   : $SERVER_IP
====================================
Connection Ports:
  Direct TCP  : $OVPN_TCP_PORT
  Direct UDP  : $OVPN_UDP_PORT
  TLS (SSL)   : $OVPN_TLS_PORT
  TLS Alt     : $OVPN_TLS_ALT_PORT
====================================
Config Files:
  TCP: $OVPN_CLIENT_DIR/$username/$username-tcp.ovpn
  UDP: $OVPN_CLIENT_DIR/$username/$username-udp.ovpn
  TLS: $OVPN_CLIENT_DIR/$username/$username-tls.ovpn
====================================
Download Links:
  http://$SERVER_IP:$NGINX_PORT/ovpn/$username/
  http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tcp.ovpn
  http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tls.ovpn
====================================
EOF

# Add to user database
echo "$username:$password:$EXPIRE_DATE:$days:active:$CREATED_DATE" >> "$USER_DB"

# ============================================================
# DISPLAY USER INFO WITH DOWNLOAD URLs
# ============================================================
clear
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}              ✅ OVPN ACCOUNT CREATED SUCCESSFULLY           ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}📋 Account Details:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Username" "$username"
printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Password" "$password"
printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Created" "$CREATED_DATE"
printf "  ${WHITE}%-14s${NC} : ${YELLOW}%s${NC} (%s days)\n" "Expires" "$EXPIRE_DATE" "$days"
printf "  ${WHITE}%-14s${NC} : ${GREEN}%s${NC}\n" "Server IP" "$SERVER_IP"
echo ""

echo -e "${CYAN}📡 Connection Methods:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}Direct TCP${NC}  : ${GREEN}$SERVER_IP:$OVPN_TCP_PORT${NC}"
echo -e "  ${WHITE}Direct UDP${NC}  : ${GREEN}$SERVER_IP:$OVPN_UDP_PORT${NC}"
echo -e "  ${WHITE}TLS (SSL)${NC}   : ${GREEN}$SERVER_IP:$OVPN_TLS_PORT${NC} ${CYAN}(via Stunnel)${NC}"
echo -e "  ${WHITE}TLS Alt${NC}     : ${GREEN}$SERVER_IP:$OVPN_TLS_ALT_PORT${NC} ${CYAN}(via Stunnel)${NC}"
echo ""

echo -e "${CYAN}📁 Config Files:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}TCP:${NC}  $OVPN_CLIENT_DIR/$username/$username-tcp.ovpn"
echo -e "  ${WHITE}UDP:${NC}  $OVPN_CLIENT_DIR/$username/$username-udp.ovpn"
echo -e "  ${WHITE}TLS:${NC}  $OVPN_CLIENT_DIR/$username/$username-tls.ovpn"
echo ""

echo -e "${CYAN}🌐 Download URLs:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}Web Page:${NC}  ${GREEN}http://$SERVER_IP:$NGINX_PORT/ovpn/$username/${NC}"
echo -e "  ${WHITE}TCP:${NC}      ${YELLOW}http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tcp.ovpn${NC}"
echo -e "  ${WHITE}UDP:${NC}      ${YELLOW}http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-udp.ovpn${NC}"
echo -e "  ${WHITE}TLS:${NC}      ${YELLOW}http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tls.ovpn${NC}"
echo ""

echo -e "${CYAN}📱 Mobile/Desktop Import:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}1.${NC} Open OpenVPN Connect app"
echo -e "  ${WHITE}2.${NC} Import profile via URL:"
echo -e "     ${YELLOW}http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tcp.ovpn${NC}"
echo -e "  ${WHITE}3.${NC} Enter password: ${GREEN}$password${NC}"
echo ""

echo -e "${CYAN}💡 Quick Copy Commands:${NC}"
echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}Download TCP:${NC}"
echo -e "  ${YELLOW}wget http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tcp.ovpn${NC}"
echo ""
echo -e "  ${WHITE}Download TLS:${NC}"
echo -e "  ${YELLOW}wget http://$SERVER_IP:$NGINX_PORT/ovpn/$username/$username-tls.ovpn${NC}"
echo ""

echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${CYAN}  🔐 TLS uses existing Stunnel SSL certificate              ${PURPLE}║${NC}"
echo -e "${PURPLE}║${CYAN}  📁 Cert: /etc/stunnel/stunnel.pem                        ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"

print_success "User $username created successfully!"
echo ""
print_info "Share the download URL with the user to import into OpenVPN client"