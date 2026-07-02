#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - BANDWIDTH MONITOR (vnStat)
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

# Ensure vnStat dependency is installed and running
if ! command -v vnstat &> /dev/null; then
    echo -e "[ ${yellow}⚠${NC} ] vnStat is not installed. Installing dependencies..."
    apt-get update && apt-get install vnstat -y
    systemctl enable vnstat && systemctl start vnstat
    echo -e "[ ${green}✓${NC} ] vnStat service initiated successfully."
    sleep 2
    clear
fi

show_bw_banner() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
    echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
    echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
    echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
    echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
    echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
    echo -e "${purple}║${cyan}                     • BANDWIDTH MONITOR •                     ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_bw_banner
echo -e " [ ${cyan}01${NC} ] View Overall Total Remaining Bandwidth"
echo -e " [ ${cyan}02${NC} ] Usage Breakdown (Every 5 Minutes)"
echo -e " [ ${cyan}03${NC} ] Usage Breakdown (Hourly)"
echo -e " [ ${cyan}04${NC} ] Usage Breakdown (Daily)"
echo -e " [ ${cyan}05${NC} ] Usage Breakdown (Monthly)"
echo -e " [ ${cyan}06${NC} ] Usage Breakdown (Yearly)"
echo -e " [ ${cyan}07${NC} ] View Highest Traffic Peak Record"
echo -e " [ ${cyan}08${NC} ] Graphical Hourly Usage Statistics"
echo -e " [ ${cyan}09${NC} ] Monitor Live Current Data Stream"
echo -e " [ ${cyan}10${NC} ] View Real-time 5s Traffic Rate"
echo "" 
echo -e " [ ${red}00${NC} ] ${red}BACK TO SYSTEM MENU${NC}"
echo ""
echo -e " Press ${yellow}x${NC} or [ ${yellow}Ctrl+C${NC} ] to Exit"
echo ""
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Select menu [0-10 or x]: " opt
echo -e ""

case $opt in
1|01)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] OVERALL SERVER REMAINING BANDWIDTH:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
2|02)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] 5-MINUTE USAGE LOGS:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -5
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
3|03)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] HOURLY USAGE LOGS:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -h
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
4|04)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] DAILY USAGE LOGS:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -d
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
5|05)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] MONTHLY USAGE LOGS:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -m
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
6|06)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] YEARLY USAGE LOGS:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -y
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
7|07)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] HIGHEST TRAFFIC PEAK RECORDED:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -t
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
8|08)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] GRAPHICAL HOURLY STATS SUMMARY:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -hg
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
9|09)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] MONITOR LIVE REAL-TIME DATA STREAM:${NC}"
    echo -e "${red} Note: Press [ Ctrl+C ] to terminate the live feed stream.${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -l
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
10)
    clear
    show_bw_banner
    echo -e "${yellow} [📊] LIVE 5-SECOND TRAFFIC SAMPLING RATE:${NC}"
    echo -e "${purple}──────────────────────────────────────────────────────────────${NC}\n"
    vnstat -tr
    echo -e "\n${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to return to Bandwidth Menu..."
    bw
    ;;
0|00)
    sleep 0.5
    menu
    ;;
x|X)
    exit
    ;;
*)
    echo -e ""
    echo -e "${red}✗ Error: Invalid input choice option!${NC}"
    sleep 1
    bw
    ;;
esac
