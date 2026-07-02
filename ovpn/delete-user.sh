#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN USER DELETION
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
print_warn()  { echo -e "[ ${YELLOW}WARN${NC} ] $1"; }
print_error() { echo -e "[ ${RED}ERROR${NC} ] $1"; }
print_success(){ echo -e "[ ${BLUE}OK${NC} ] $1"; }

OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
USER_DB="$OVPN_CLIENT_DIR/users.db"

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

clear
echo "==========================================="
echo "   🗑️  MARCSCRIPT OVPN USER DELETION"
echo "==========================================="
echo ""

# List users
if [ ! -f "$USER_DB" ]; then
    print_error "No users found!"
    exit 1
fi

echo "Existing Users:"
echo "-------------------------------------------"
printf "%-4s %-15s %-12s %-10s\n" "No" "Username" "Expiry" "Status"
echo "-------------------------------------------"
num=1
while IFS=':' read -r user pass expire days status created; do
    printf "%-4s %-15s %-12s %-10s\n" "$num" "$user" "$expire" "$status"
    ((num++))
done < "$USER_DB"
echo "-------------------------------------------"

read -p "Username to delete: " username

# Confirm
read -p "Are you sure? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deletion cancelled"
    exit 0
fi

# Revoke certificate
cd "$EASYRSA_DIR"
./easyrsa --batch revoke "$username" 2>/dev/null
./easyrsa gen-crl
cp "$EASYRSA_DIR/pki/crl.pem" "/etc/openvpn/"

# Remove user files
rm -rf "$OVPN_CLIENT_DIR/$username"

# Remove from database
sed -i "/^$username:/d" "$USER_DB"

# Restart OpenVPN
systemctl restart openvpn@server-tcp 2>/dev/null
systemctl restart openvpn@server-udp 2>/dev/null

print_success "User $username deleted successfully!"
