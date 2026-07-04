#!/bin/bash
# ============================================================
# MARCSCRIPT XRAY ALL PROTOCOLS MENU
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
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

# ============================================================
# XRAY MENU INTERFACE
# ============================================================
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     █████╗ ██╗  ██╗██████╗  █████╗ ██╗   ██╗${purple}║${NC}"
echo -e "${purple}║${white}    ██╔══██╗╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝${purple}║${NC}"
echo -e "${purple}║${white}    ███████║ ╚███╔╝ ██████╔╝███████║ ╚████╔╝ ${purple}║${NC}"
echo -e "${purple}║${white}    ██╔══██║ ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝  ${purple}║${NC}"
echo -e "${purple}║${white}    ██║  ██║██╔╝ ██╗██║  ██║██║  ██║   ██║   ${purple}║${NC}"
echo -e "${purple}║${white}    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ${purple}║${NC}"
echo -e "${purple}║${cyan}              • XRAY ALL PROTOCOLS MENU •                  ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Display Xray status
if systemctl is-active --quiet xray 2>/dev/null || systemctl is-active --quiet v2ray 2>/dev/null; then
    echo -e " ${green}● Xray Service: Running${NC}"
else
    echo -e " ${red}● Xray Service: Stopped${NC}"
fi
echo ""

# Menu Options
echo -e " ${cyan}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e " ${cyan}│${white}  [1] VMESS (WebSocket) Management                      ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [2] VLESS Management                                  ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [3] TROJAN Management                                 ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [4] SHADOWSOCKS (SS+WS) Management                   ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [5] Xray Certificate Management                      ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [6] Xray Service Control (Start/Stop/Restart)        ${cyan}│${NC}"
echo -e " ${cyan}│${white}  [0] Back to Main Menu                                ${cyan}│${NC}"
echo -e " ${cyan}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

read -p " Select menu [0-6]: " opt
echo ""

case $opt in
1|01) 
    clear 
    m-vmess 
    ;;
2|02) 
    clear 
    m-vless 
    ;;
3|03) 
    clear 
    m-trojan 
    ;;
4|04) 
    clear 
    m-ssws 
    ;;
5|05) 
    clear 
    certv2ray 
    ;;
6|06) 
    clear
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 XRAY SERVICE CONTROL                         ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " [${cyan}1${NC}] Start Xray"
    echo -e " [${cyan}2${NC}] Stop Xray"
    echo -e " [${cyan}3${NC}] Restart Xray"
    echo -e " [${cyan}4${NC}] Check Xray Status"
    echo -e " [${cyan}0${NC}] Back"
    echo ""
    read -p " Select option [0-4]: " xray_opt
    case $xray_opt in
        1) 
            systemctl start xray 2>/dev/null || systemctl start v2ray 2>/dev/null
            echo -e "${green}✓ Xray started${NC}"
            sleep 2
            clear
            m-xray
            ;;
        2) 
            systemctl stop xray 2>/dev/null || systemctl stop v2ray 2>/dev/null
            echo -e "${yellow}✓ Xray stopped${NC}"
            sleep 2
            clear
            m-xray
            ;;
        3) 
            systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
            echo -e "${green}✓ Xray restarted${NC}"
            sleep 2
            clear
            m-xray
            ;;
        4) 
            systemctl status xray 2>/dev/null || systemctl status v2ray 2>/dev/null
            echo ""
            read -n 1 -s -r -p "Press any key to continue..."
            clear
            m-xray
            ;;
        0) 
            clear 
            m-xray 
            ;;
        *) 
            echo -e "${red}Invalid option${NC}"
            sleep 1
            clear
            m-xray
            ;;
    esac
    ;;
0|00) 
    clear 
    menu 
    ;;
*) 
    echo -e "${red}✗ Error: Invalid selection!${NC}" 
    sleep 1 
    clear 
    m-xray 
    ;;
esac