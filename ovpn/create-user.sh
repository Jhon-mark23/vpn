#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN USER CREATOR
# Creates OVPN users with expiration date
# ============================================================

# Colors (matching your existing style)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}OK${NC} ] $1"; }

# Configuration
OVPN_DIR="/etc/openvpn"
OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
OVPN_TCP_PORT="1194"
OVPN_UDP_PORT="2200"
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
echo "==========================================="
echo "   👤 MARCSCRIPT OVPN USER CREATOR"
echo "==========================================="
echo ""
read -p "Username : " username
read -p "Password : " password
read -p "Duration (days) : " days

# Validate input
if [ -z "$username" ] || [ -z "$password" ] || [ -z "$days" ]; then
    print_error "All fields are required!"
    exit 1
fi

# Check if user exists
if [ -f "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" ]; then
    print_error "User $username already exists!"
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

# Create TCP config
print_info "Creating TCP config..."
cat > "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN TCP Configuration
# User: $username
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP
# Port: $OVPN_TCP_PORT (TCP)
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
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
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

# Create UDP config
print_info "Creating UDP config..."
cat > "$OVPN_CLIENT_DIR/$username/$username-udp.ovpn" <<EOF
# ============================================
# MarcScript OpenVPN UDP Configuration
# User: $username
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Expires: $EXPIRE_DATE ($days days)
# Server: $SERVER_IP
# Port: $OVPN_UDP_PORT (UDP)
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
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
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

# Create user info file
cat > "$OVPN_CLIENT_DIR/$username/$username.info" <<EOF
====================================
MarcScript OpenVPN Account
====================================
Username    : $username
Password    : $password
Created     : $(date '+%Y-%m-%d %H:%M:%S')
Expires     : $EXPIRE_DATE
Duration    : $days days
Server IP   : $SERVER_IP
TCP Port    : $OVPN_TCP_PORT
UDP Port    : $OVPN_UDP_PORT
Status      : Active
====================================
Config Files:
TCP: $OVPN_CLIENT_DIR/$username/$username-tcp.ovpn
UDP: $OVPN_CLIENT_DIR/$username/$username-udp.ovpn
====================================
EOF

# Add to user database
echo "$username:$password:$EXPIRE_DATE:$days:active:$(date '+%Y-%m-%d')" >> "$USER_DB"

# Display summary
clear
echo "==========================================="
echo "   ✅ OVPN ACCOUNT CREATED SUCCESSFULLY"
echo "==========================================="
echo ""
echo "📋 Account Details:"
echo "   Username   : $username"
echo "   Password   : $password"
echo "   Expires    : $EXPIRE_DATE ($days days)"
echo "   Server IP  : $SERVER_IP"
echo ""
echo "📡 Connection Info:"
echo "   TCP Port   : $OVPN_TCP_PORT"
echo "   UDP Port   : $OVPN_UDP_PORT"
echo ""
echo "📁 Config Files:"
echo "   TCP: $OVPN_CLIENT_DIR/$username/$username-tcp.ovpn"
echo "   UDP: $OVPN_CLIENT_DIR/$username/$username-udp.ovpn"
echo ""
echo "💡 Quick Download:"
echo "   cat $OVPN_CLIENT_DIR/$username/$username-tcp.ovpn"
echo ""
echo "==========================================="

print_success "User $username created successfully!"
