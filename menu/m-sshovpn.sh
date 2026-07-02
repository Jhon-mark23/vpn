#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - SSH & WEBSOCKET CORE MENU
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
echo -e "${purple}║${cyan}                     • SSH & WS SERVICE MENU •                 ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e " [ ${cyan}01${NC} ] Create SSH & WS Account"
echo -e " [ ${cyan}02${NC} ] Trial SSH & WS Account"
echo -e " [ ${cyan}03${NC} ] Renew SSH & WS Account"
echo -e " [ ${cyan}04${NC} ] Delete SSH & WS Account"
echo -e " [ ${cyan}05${NC} ] Check User Login Sessions"
echo -e " [ ${cyan}06${NC} ] List All Active VPN Members"
echo -e " [ ${cyan}07${NC} ] Purge / Auto-Clean Expired Users"
echo -e " [ ${cyan}08${NC} ] Configure Multi-Login Autokill Guard"
echo -e " [ ${cyan}09${NC} ] Inspect Multi-Login Violation Violators"
echo -e " [ ${cyan}10${NC} ] View Registration Log History File"
echo ""
echo -e " [ ${red}00${NC} ] ${red}BACK TO MAIN MENU${NC}"
echo ""
echo -e " Press ${yellow}x${NC} or [ ${yellow}Ctrl+C${NC} ] to Exit"
echo ""
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Select menu [0-10 or x]: " opt
echo -e ""

case $opt in
1|01) clear ; usernew ; exit ;;
2|02) clear ; trial ; exit ;;
3|03) clear ; renew ; exit ;;
4|04) clear ; hapus ; exit ;;
5|05) clear ; cek ; exit ;;
6|06) clear ; member ; exit ;;
7|07) clear ; delete ; exit ;;
8|08) clear ; autokill ; exit ;;
9|09) clear ; ceklim ; exit ;;
10) 
    clear
    echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${yellow} [📋] CREATED ACCOUNT ARCHIVE LOGS:${NC}"
    echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    if [ -s /etc/log-create-ssh.log ]; then
        cat /etc/log-create-ssh.log
    else
        echo -e "  ${red}No accounts created logs found yet.${NC}"
    fi
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to SSH Menu..."
    m-sshovpn
    ;;
0|00) clear ; menu ; exit ;;
x|X) exit ;;
*) echo -e "${red}✗ Error: Invalid choice option!${NC}" ; sleep 1 ; m-sshovpn ;;
esac
