#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - FAHRI ALIMUDIN DESIGN REPLICA
# ============================================================

MYIP=$(curl -sS ifconfig.me)
clear

# ---------- COLOURS ----------
purple='\033[0;35m'
blue='\033[0;34m'
green='\033[1;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

# ============================================================
# VPS INFORMATION ENGINE
# ============================================================
domain=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "None")
PUBKEY=$(cat "/etc/slowdns/server.pub" 2>/dev/null || echo "None")
nsdomain="ns.${domain}"

# SSL Certificate Status Engine
if [ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" ]; then
  modifyTime=$(stat $HOME/.acme.sh/${domain}_ecc/${domain}.key 2>/dev/null | grep Modify | awk '{print $2" "$3}')
  modifyTime1=$(date +%s -d "${modifyTime}" 2>/dev/null || echo "0")
  currentTime=$(date +%s)
  stampDiff=$(expr ${currentTime} - ${modifyTime1} 2>/dev/null || echo "0")
  days=$(expr ${stampDiff} / 86400 2>/dev/null || echo "0")
  remainingDays=$(expr 90 - ${days} 2>/dev/null || echo "90")
else
  remainingDays=90
fi

tlsStatus="${remainingDays}"
if [[ ${remainingDays} -le 0 ]]; then
	tlsStatus="Expired"
else
	tlsStatus="${tlsStatus} Days Remaining"
fi

# OS Details & System Uptime
uptime="$(uptime -p | cut -d " " -f 2-10)"
os_name=$(hostnamectl | grep "Operating System" | cut -d ':' -f2 | sed 's/^[ \t]*//')

# Memory & CPU
tram=$( free -m | awk 'NR==2 {print $2}' )
uram=$( free -m | awk 'NR==2 {print $3}' )
loadcpu=$(uptime | awk -F'load average:' '{print $2}')
date_now=$(date +%d-%m-%Y)
time_now=$(date +%H:%M:%S)

# Client System Metadata Profile
Exp2="Lifetime"
Name="marc"

# ============================================================
# SERVICE STATUS ENGINE (from running.sh)
# ============================================================
green_status() { echo -e "\033[32;1m${*}\033[0m"; }
red_status() { echo -e "\033[31;1m${*}\033[0m"; }

ssh_service=$(systemctl status ssh | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1 2>/dev/null)
dropbear_status=$(systemctl status dropbear | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1 2>/dev/null)
stunnel_service=$(systemctl status stunnel4 | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1 2>/dev/null)
wstls=$(systemctl status ws-stunnel.service 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
wsdrop=$(systemctl status ws-dropbear.service 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
xray_status=$(systemctl status xray | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
nginx_status=$(systemctl status nginx | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
squid_status=$(systemctl status squid | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
fail2ban_service=$(systemctl status fail2ban | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
cron_service=$(systemctl status cron | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
vnstat_service=$(systemctl status vnstat | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)

status_color() {
    [[ "$1" == "running" ]] && green_status "ON" || red_status "OFF"
}

# ============================================================
# UNIFIED UI DISPLAY
# ============================================================
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}          ════════ Welcome to Autoscript Multiport ════════       ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# SYSTEM INFO BOX
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "SYSTEM OS" "$os_name"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "SYSTEM CORE" "$(nproc)"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "SERVER RAM" "$uram / $tram MB"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "LOADCPU" "$loadcpu"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "DATE" "$date_now"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "TIME" "$time_now"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "UPTIME" "$uptime"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "IP VPS" "$MYIP"
printf "${purple}║${white} %-1s ${blue}%-14s${white} = ${green}%-36s ${purple}║${NC}\n" "●" "DOMAIN" "$domain"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# INFO ACCOUNT SECTION
echo -e "${purple}═══════════════ ${white}>>> INFORMATION ACCOUNT <<< ${purple}═══════════════${NC}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "${white}%-27s${NC} = ${green}%-12s${NC}\n" "SSH/OPENVPN/UDP" "0"
printf "${white}%-27s${NC} = ${green}%-12s${NC}\n" "VMESS/WS/GRPC" "0"
printf "${white}%-27s${NC} = ${green}%-12s${NC}\n" "VLESS/WS/GRPC" "0"
printf "${white}%-27s${NC} = ${green}%-12s${NC}\n" "TROJAN/WS/GRPC" "0"
printf "${white}%-27s${NC} = ${green}%-12s${NC}\n" "SHADOW/WS/GRPC" "0"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# INSTALL LINK
echo -e "${purple}═══>>> ${white}install via github.com/fahrialimudin ${purple}<<<═══${NC}"
echo ""

# SERVICE STATUS BOXES (Dynamic from running.sh)
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
printf "${purple}║${green} %-10s${NC} ${green}%-10s${NC} ${green}%-10s${NC} ${green}%-12s${NC} ${purple}║${NC}\n" "SSH" "$(status_color $ssh_service)" "NOOBZVPN" "$(status_color $dropbear_status)" "NGINX" "$(status_color $nginx_status)" "HAPROXY" "$(status_color $stunnel_service)"
printf "${purple}║${green} %-10s${NC} ${green}%-10s${NC} ${green}%-10s${NC} ${green}%-12s${NC} ${purple}║${NC}\n" "WS-ePro" "$(status_color $wsdrop)" "UDP" "$(status_color $squid_status)" "XRAY" "$(status_color $xray_status)" "DROPBEAR" "$(status_color $dropbear_status)"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# MENU COLUMNS (21 options arranged in 3 columns)
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
printf "${purple}║${cyan} [01] ${white}SSH MENU${NC}         ${purple}║${cyan} [08] ${white}BCKP/RSTR${NC}       ${purple}║${cyan} [16] ${white}CHANGE DOMAIN${NC}    ${purple}║${NC}\n"
printf "${purple}║${cyan} [02] ${white}VMESS MENU${NC}       ${purple}║${cyan} [09] ${white}GOTOP X RAM${NC}      ${purple}║${cyan} [17] ${white}FIX CRT DOMAIN${NC}   ${purple}║${NC}\n"
printf "${purple}║${cyan} [03] ${white}VLESS MENU${NC}       ${purple}║${cyan} [10] ${white}RESTART ALL${NC}     ${purple}║${cyan} [18] ${white}CHANGE BANNER${NC}     ${purple}║${NC}\n"
printf "${purple}║${cyan} [04] ${white}TROJAN MENU${NC}      ${purple}║${cyan} [11] ${white}COLOUR${NC}           ${purple}║${cyan} [19] ${white}RESTART BANNER${NC}   ${purple}║${NC}\n"
printf "${purple}║${cyan} [05] ${white}AKUN NOOBZVPN${NC}    ${purple}║${cyan} [12] ${white}UPDATE MENU${NC}      ${purple}║${cyan} [20] ${white}SPEEDTEST${NC}        ${purple}║${NC}\n"
printf "${purple}║${cyan} [06] ${white}SS - LIBEV${NC}       ${purple}║${cyan} [13] ${white}RUNNING${NC}          ${purple}║${cyan} [21] ${white}EKSTRAK MENU${NC}      ${purple}║${NC}\n"
printf "${purple}║${cyan} [07] ${white}INSTALL UDP${NC}      ${purple}║${cyan} [14] ${white}INFO PORT${NC}        ${purple}║${white}                       ${purple}║${NC}\n"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# FOOTER
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white} Script Version = ${green}LIFETIME - Fahri Alimudin 082328013583${NC} ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# INPUT
read -p "Options [ 1 - 21 ] >>> " opt
echo ""

# ============================================================
# CASE MENU MAPPING (Place your actual script calls here)
# ============================================================
case $opt in
1|01) clear; m-sshovpn ;;
2|02) clear; m-vmess ;;
3|03) clear; m-vless ;;
4|04) clear; m-trojan ;;
5|05) clear; m-ssws ;;
6|06) clear; m-system ;;
7|07) clear; m-install-udp ;;
8|08) clear; bckp-rstr ;;
9|09) clear; gotop-x-ram ;;
10) clear; restart-all ;;
11) clear; colour-menu ;;
12) clear; update-menu ;;
13) clear; running ;;  # This calls your running.sh script directly
14) clear; info-port ;;
16) clear; change-domain ;;
17) clear; fix-crt-domain ;;
18) clear; change-banner ;;
19) clear; restart-banner ;;
20) clear; speedtest ;;
21) clear; ekstrak-menu ;;
*) 
   echo -e "${red}✗ Invalid option${NC}" 
   sleep 1
   clear
   bash $0
   ;;
esac