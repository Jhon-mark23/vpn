#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN USER LIST
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
NC='\033[0m'

OVPN_CLIENT_DIR="/etc/openvpn/client-configs"
USER_DB="$OVPN_CLIENT_DIR/users.db"

clear
echo "==========================================="
echo "   📋 MARCSCRIPT OPENVPN USERS"
echo "==========================================="
echo ""

if [ ! -f "$USER_DB" ]; then
    echo "No users found!"
    exit 0
fi

printf "%-4s %-15s %-14s %-8s %-8s\n" "No" "Username" "Expiry Date" "Days" "Status"
echo "-------------------------------------------------------------------"

num=1
while IFS=':' read -r user pass expire days status created; do
    if [ -n "$user" ]; then
        # Calculate days left
        expire_epoch=$(date -d "$expire" +%s 2>/dev/null)
        current_epoch=$(date +%s)
        
        if [ -n "$expire_epoch" ]; then
            days_left=$(( ($expire_epoch - $current_epoch) / 86400 ))
            
            if [ $days_left -lt 0 ]; then
                status="${RED}Expired${NC}"
                days_left="EXP"
            elif [ $days_left -eq 0 ]; then
                status="${YELLOW}Today${NC}"
            elif [ $days_left -le 3 ]; then
                status="${YELLOW}Active${NC}"
            else
                status="${GREEN}Active${NC}"
            fi
            
            printf "%-4s %-15s %-14s %-8s " "$num" "$user" "$expire" "$days_left"
            echo -e "$status"
        fi
        ((num++))
    fi
done < "$USER_DB"

echo "-------------------------------------------------------------------"
echo "Total Users: $((num-1))"
echo ""
echo "Config Directory: $OVPN_CLIENT_DIR"
echo "==========================================="
