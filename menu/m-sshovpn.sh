#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - SSH & WEBSOCKET CORE MENU
# Version: 2.0 (Simple)
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || echo "Unknown")
clear

# ---------- COLOURS ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# ---------- HEADER ----------
echo "=========================================="
echo "       SSH & WEBSOCKET SERVICE MENU      "
echo "=========================================="
echo ""

# ---------- MENU OPTIONS ----------
echo "1. Create SSH & WS Account"
echo "2. Trial SSH & WS Account"
echo "3. Renew SSH & WS Account"
echo "4. Delete SSH & WS Account"
echo "5. Check User Login Sessions"
echo "6. List All Active VPN Members"
echo "7. Purge Expired Users"
echo "8. Auto-Kill Multi-Login"
echo "9. View Multi-Login Violators"
echo "10. View Account Logs"
echo ""
echo "0. Back to Main Menu"
echo ""

# ---------- FOOTER ----------
echo "=========================================="
echo ""

read -p "Select option [0-10]: " opt

case $opt in
1|01) clear ; usernew ;;
2|02) clear ; trial ;;
3|03) clear ; renew ;;
4|04) clear ; hapus ;;
5|05) clear ; cek ;;
6|06) clear ; member ;;
7|07) clear ; delete ;;
8|08) clear ; autokill ;;
9|09) clear ; ceklim ;;
10) 
    clear
    echo "=========================================="
    echo "          ACCOUNT CREATION LOGS           "
    echo "=========================================="
    echo ""
    if [ -s /etc/log-create-ssh.log ]; then
        cat /etc/log-create-ssh.log
    else
        echo -e "${RED}No logs found.${NC}"
    fi
    echo ""
    echo "=========================================="
    read -n 1 -s -r -p "Press any key to continue..."
    m-sshovpn
    ;;
0|00) clear ; menu ;;
x|X) exit ;;
*) 
    echo -e "${RED}Invalid option!${NC}"
    sleep 1
    m-sshovpn
    ;;
esac