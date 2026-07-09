#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
green='\033[0;32m'
yellow='\033[1;33m'
red='\033[1;31m'
NC='\033[0m'

# ============================================================
# SYSTEM SETUP MENU
# ============================================================
echo "=========================================="
echo "         SYSTEM SETUP MENU                "
echo "=========================================="
echo ""

echo "[1] Domain Panel"
echo "[2] VPS Speedtest"
echo "[3] Set Auto Reboot"
echo "[4] Restart All Services"
echo "[5] Check Bandwidth"
echo "[6] Install TCP BBR"
echo "[7] DNS Changer"
echo "[8] Edit Script Banner"
echo "[9] Add API"
echo ""
echo "[0] Back to Main Menu"
echo ""
echo "Press x or Ctrl+C to Exit"
echo ""
echo "=========================================="
echo ""

read -p "Select [0-8 or x]: " opt

case $opt in
1|01) clear; m-domain ;;
2|02) clear; speedtest ;;
3|03) clear; auto-reboot ;;
4|04) clear; restart ;;
5|05) clear; bw ;;
6|06) clear; m-tcp ;;
7|07) clear; m-dns ;;
8|08) clear; m-banner ;;
9|09) clear; set-api  ;;
0|00) clear; menu ;;
x|X) exit ;;
*) echo -e "\n${red}Invalid selection!${NC}"; sleep 1; exec bash "$0" ;;
esac