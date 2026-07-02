#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - MANUAL USER DELETION
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
purple='\033[0;35m'
blue='\033[0;34m'
green='\033[0;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

# Banner Implementation
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}                     • MANUAL DELETION PANEL •                 ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Dynamic User Database Preview
echo -e "${cyan} [📡] ACTIVE DELETABLE VPN ACCOUNTS:${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/deletable.txt
if [ ! -s /tmp/deletable.txt ] || [ $(cat /tmp/deletable.txt | wc -l) -eq 0 ]; then
    echo -e "  ${yellow}(No users registered on this system yet)${NC}"
else
    # Output usernames in a clean, multi-column format for scannability
    awk -F: '{print "  • " $1}' /tmp/deletable.txt | pr -3 -t -w 65
fi
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Enter Username to Delete: " Pengguna
Pengguna="${Pengguna//[[:space:]]/}"

# Input validation
if [[ -z "$Pengguna" ]]; then
    echo -e "\n ${red}✗ Failure:${NC} Username input cannot be blank."
    rm -f /tmp/deletable.txt
    echo ""
    read -n 1 -s -r -p "Press any key to return to menu..."
    menu
    exit
fi

# Essential System User Protection Guard
if [[ "$Pengguna" == "root" || "$Pengguna" == "bin" || "$Pengguna" == "daemon" || "$Pengguna" == "sync" ]]; then
    echo -e "\n ${red}✗ Protection Alert:${NC} Deleting system user [${yellow}$Pengguna${NC}] is forbidden."
    rm -f /tmp/deletable.txt
    echo ""
    read -n 1 -s -r -p "Press any key to return to menu..."
    menu
    exit
fi

if getent passwd "$Pengguna" > /dev/null 2>&1; then
    echo -e "\n [⚙️] Terminating socket connections and processes for: ${yellow}$Pengguna${NC}..."
    pkill -KILL -u "$Pengguna" > /dev/null 2>&1
    sleep 1

    # Forcefully evict user configuration
    userdel -f "$Pengguna" > /dev/null 2>&1

    # Final Verification
    if ! getent passwd "$Pengguna" > /dev/null 2>&1; then
        echo -e " ${green}✓ Success:${NC} User account ${green}$Pengguna${NC} has been thoroughly purged."
    else
        echo -e " ${red}✗ Failure:${NC} OS lock preventing removal of ${red}$Pengguna${NC}. Try again."
    fi
else
    echo -e "\n ${red}✗ Failure:${NC} User account [ ${red}$Pengguna${NC} ] does not exist."
fi

rm -f /tmp/deletable.txt
echo ""
read -n 1 -s -r -p "Press any key to return to menu..."
menu
