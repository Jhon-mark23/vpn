#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - MANUAL USER DELETION
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Banner
echo "=========================================="
echo "          MANUAL DELETION PANEL            "
echo "=========================================="
echo ""

# Dynamic User Database Preview
echo "[ACTIVE DELETABLE VPN ACCOUNTS:]"
echo "------------------------------------------"
cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/deletable.txt
if [ ! -s /tmp/deletable.txt ] || [ $(cat /tmp/deletable.txt | wc -l) -eq 0 ]; then
    echo "  (No users registered on this system yet)"
else
    awk -F: '{print "  - " $1}' /tmp/deletable.txt | pr -3 -t -w 65
fi
echo "------------------------------------------"
echo ""

read -p " Enter Username to Delete: " Pengguna
Pengguna="${Pengguna//[[:space:]]/}"

# Input validation
if [[ -z "$Pengguna" ]]; then
    echo -e "\n ${RED}Failure:${NC} Username input cannot be blank."
    rm -f /tmp/deletable.txt
    echo ""
    read -n 1 -s -r -p "Press any key to return to menu..."
    menu
    exit
fi

# Essential System User Protection Guard
if [[ "$Pengguna" == "root" || "$Pengguna" == "bin" || "$Pengguna" == "daemon" || "$Pengguna" == "sync" ]]; then
    echo -e "\n ${RED}Protection Alert:${NC} Deleting system user [${YELLOW}$Pengguna${NC}] is forbidden."
    rm -f /tmp/deletable.txt
    echo ""
    read -n 1 -s -r -p "Press any key to return to menu..."
    menu
    exit
fi

if getent passwd "$Pengguna" > /dev/null 2>&1; then
    echo -e "\n [*] Terminating processes for: ${YELLOW}$Pengguna${NC}..."
    pkill -KILL -u "$Pengguna" > /dev/null 2>&1
    sleep 1

    # Forcefully remove user
    userdel -f "$Pengguna" > /dev/null 2>&1

    # Final Verification
    if ! getent passwd "$Pengguna" > /dev/null 2>&1; then
        echo -e " ${GREEN}Success:${NC} User account ${GREEN}$Pengguna${NC} has been removed."
    else
        echo -e " ${RED}Failure:${NC} Could not remove ${RED}$Pengguna${NC}. Try again."
    fi
else
    echo -e "\n ${RED}Failure:${NC} User account [ ${RED}$Pengguna${NC} ] does not exist."
fi

rm -f /tmp/deletable.txt
echo ""
read -n 1 -s -r -p "Press any key to return to menu..."
menu