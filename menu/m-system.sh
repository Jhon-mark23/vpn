#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS"
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
# UNIFIED MARCSCRIPT BANNER
# ============================================================
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}                    • SYSTEM SETUP MENU •                     ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e " [ ${cyan}01${NC} ] Domain Panel"
echo -e " [ ${cyan}02${NC} ] VPS Speedtest"
echo -e " [ ${cyan}03${NC} ] Set Auto Reboot"
echo -e " [ ${cyan}04${NC} ] Restart All Services"
echo -e " [ ${cyan}05${NC} ] Check Bandwidth"
echo -e " [ ${cyan}06${NC} ] Install TCP BBR"
echo -e " [ ${cyan}07${NC} ] DNS Changer"
echo -e " [ ${cyan}08${NC} ] Edit Script Banner"
echo ""
echo -e " [ ${red}00${NC} ] ${red}BACK TO MAIN MENU${NC}"
echo ""
echo -e " Press ${yellow}x${NC} or [ ${yellow}Ctrl+C${NC} ] to Exit"
echo ""
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Select menu [0-8 or x]: " opt
echo -e ""

case $opt in
1|01) clear ; m-domain ; exit ;;
2|02) clear ; speedtest ; exit ;;
3|03) clear ; auto-reboot ; exit ;;
4|04) clear ; restart ; exit ;;
5|05) clear ; bw ; exit ;;
6|06) clear ; m-tcp ; exit ;;
7|07) clear ; m-dns ; exit ;;
8|08) 
    # Dynamically opens this exact menu script file inside the nano text editor
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$BASH_SOURCE")
    clear
    nano "$SCRIPT_PATH"
    clear
    exec bash "$SCRIPT_PATH"
    exit 
    ;;
0|00) clear ; menu ; exit ;;
x|X) exit ;;
*) echo -e "" ; echo -e "${red}You pressed the wrong key!${NC}" ; sleep 1 ; exec bash "$0" ;;
esac
