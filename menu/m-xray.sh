#!/bin/bash
# ============================================================
# SIMPLE XRAY ALL PROTOCOLS MENU
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
green='\033[0;32m'
yellow='\033[1;33m'
red='\033[1;31m'
NC='\033[0m'

# ============================================================
# XRAY MENU INTERFACE
# ============================================================
echo "=========================================="
echo "         XRAY ALL PROTOCOLS MENU          "
echo "=========================================="

# Display Xray status
if systemctl is-active --quiet xray 2>/dev/null || systemctl is-active --quiet v2ray 2>/dev/null; then
    echo -e "\n Xray Status: ${green}ON${NC}"
else
    echo -e "\n Xray Status: ${red}OFF${NC}"
fi

# Menu Options
echo -e "\n[1] VMESS Management"
echo "[2] VLESS Management"
echo "[3] TROJAN Management"
echo "[4] SHADOWSOCKS Management"
echo "[5] Certificate Management"
echo "[6] Service Control"
echo "[0] Back to Main"
echo ""

read -p "Select [0-6]: " opt

case $opt in
1) clear; m-vmess ;;
2) clear; m-vless ;;
3) clear; m-trojan ;;
4) clear; m-ssws ;;
5) clear; certv2ray ;;
6) clear; service_menu ;;
0) clear; menu ;;
*) echo -e "\n${red}Invalid selection!${NC}"; sleep 1; clear; m-xray ;;
esac

# ============================================================
# SERVICE CONTROL SUBMENU
# ============================================================
service_menu() {
    echo "=========================================="
    echo "         SERVICE CONTROL                  "
    echo "=========================================="
    echo -e "\n[1] Start Xray"
    echo "[2] Stop Xray"
    echo "[3] Restart Xray"
    echo "[4] Check Status"
    echo "[0] Back"
    echo ""
    
    read -p "Select [0-4]: " opt
    case $opt in
        1) systemctl start xray 2>/dev/null || systemctl start v2ray 2>/dev/null
           echo -e "\n${green}Xray Started${NC}"; sleep 1; clear; m-xray ;;
        2) systemctl stop xray 2>/dev/null || systemctl stop v2ray 2>/dev/null
           echo -e "\n${yellow}Xray Stopped${NC}"; sleep 1; clear; m-xray ;;
        3) systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
           echo -e "\n${green}Xray Restarted${NC}"; sleep 1; clear; m-xray ;;
        4) systemctl status xray 2>/dev/null || systemctl status v2ray 2>/dev/null
           read -n 1 -s -r -p "\nPress any key to continue..."
           clear; m-xray ;;
        0) clear; m-xray ;;
        *) echo -e "\n${red}Invalid option${NC}"; sleep 1; clear; service_menu ;;
    esac
}