#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN USER RENEWAL
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
USER_DB="$OVPN_CLIENT_DIR/users.db"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

clear
echo "==========================================="
echo "   🔄 MARCSCRIPT OVPN USER RENEWAL"
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

read -p "Username to renew: " username

# Check if user exists
if ! grep -q "^$username:" "$USER_DB"; then
    print_error "User $username not found!"
    exit 1
fi

# Get current info
CURRENT_EXPIRE=$(grep "^$username:" "$USER_DB" | cut -d: -f3)

read -p "Additional days: " days

# Calculate new expiration
NEW_EXPIRE=$(date -d "$CURRENT_EXPIRE +$days days" +"%Y-%m-%d")

# Update database
sed -i "s/^$username:.*:active/$username:$(grep "^$username:" "$USER_DB" | cut -d: -f2):$NEW_EXPIRE:$days:active:$(date '+%Y-%m-%d')/" "$USER_DB"

# Update config files
if [ -f "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn" ]; then
    sed -i "s/Expires:.*/Expires: $NEW_EXPIRE ($days days)/" "$OVPN_CLIENT_DIR/$username/$username-tcp.ovpn"
fi
if [ -f "$OVPN_CLIENT_DIR/$username/$username-udp.ovpn" ]; then
    sed -i "s/Expires:.*/Expires: $NEW_EXPIRE ($days days)/" "$OVPN_CLIENT_DIR/$username/$username-udp.ovpn"
fi

# Update info file
if [ -f "$OVPN_CLIENT_DIR/$username/$username.info" ]; then
    sed -i "s/Expires.*:.*/Expires     : $NEW_EXPIRE/" "$OVPN_CLIENT_DIR/$username/$username.info"
    sed -i "s/Duration.*:.*/Duration    : $days days (renewed)/" "$OVPN_CLIENT_DIR/$username/$username.info"
fi

print_success "User $username renewed until $NEW_EXPIRE"
