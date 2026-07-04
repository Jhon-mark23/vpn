#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - MAIN INTERACTIVE SYSTEM DASHBOARD
# ============================================================

MYIP=$(curl -sS ifconfig.me)
NET_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
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
# VPS INFORMATION ENGINE
# ============================================================
domain=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "None")
PUBKEY=$(cat "/etc/slowdns/server.pub")
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

# Memory Information Realtime Calculations
tram=$( free -m | awk 'NR==2 {print $2}' )
uram=$( free -m | awk 'NR==2 {print $3}' )

# Client System Metadata Profile
Exp2="Lifetime"
Name="marc"

# ============================================================
# UNIFIED MARCSCRIPT INTERACTIVE UI
# ============================================================
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}                  • CORE DASHBOARD PANEL •                     ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Dynamic Environment Diagnostics Table
echo -e "${cyan} [🖥️] LIVE METRICS & VPS DIAGNOSTICS:${NC}"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"
printf "  ${white}%-14s${NC} : %-42s\n" "OS Baseline" "$os_name"
printf "  ${white}%-14s${NC} : %-42s\n" "System Uptime" "$uptime"
printf "  ${white}%-14s${NC} : %-42s\n" "Public IP" "$MYIP"
printf "  ${white}%-14s${NC} : %-42s\n" "Active Domain" "$domain"
printf "  ${white}%-14s${NC} : %-42s\n" "NS: " "$nsdomain"
printf "  ${white}%-14s${NC} : %-42s\n" "PUBKEY" "$PUBKEY"
printf "  ${white}%-14s${NC} : %-42s\n" "Memory Capacity" "$uram MB / $tram MB"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Menu Navigation Routing Selection Nodes
echo -e " [ ${cyan}01${NC} ] SSH & WebSocket Menu"
echo -e " [ ${cyan}02${NC} ] Xray  Menu"
echo -e " [ ${cyan}03${NC} ] Xray Vmess Menu"
echo -e " [ ${cyan}04${NC} ] Xray Vless Menu"
echo -e " [ ${cyan}05${NC} ] Xray Trojan Menu"
echo -e " [ ${cyan}06${NC} ] Xray Shadowsocks Menu"
echo -e " [ ${cyan}07${NC} ] Server Settings Menu"
echo -e " [ ${cyan}08${NC} ] Check Services Status"
echo -e " [ ${cyan}09${NC} ] Flush System RAM Cache  ${purple}→ Free volatile memory${NC}"
echo -e " [ ${cyan}10${NC} ] Upgrade / Reinstall Core VPN Scripts Engine${NC}"
echo ""
echo -e " [ ${red}00${NC} ] ${red}CLOSE CURRENT SESSION (EXIT)${NC}"
echo ""
echo -e " Press ${yellow}x${NC} or [ ${yellow}Ctrl+C${NC} ] to Exit"
echo ""
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${cyan}Client :${NC} ${white}$Name${NC} | ${cyan}Expiry :${NC} ${green}$Exp2${NC} | ${cyan}SSL :${NC} ${yellow}$tlsStatus${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Select menu [0-10 or x]: " opt
echo ""

case $opt in
1|01) 
    clear 
    m-sshovpn 
    ;;
2|02) 
    clear 
    m-xray 
    ;;
3|03) 
    clear 
    m-vmess 
    ;;
4|04) 
    clear 
    m-vless 
    ;;
5|05) 
    clear 
    m-trojan 
    ;;
6|06) 
    clear 
    m-ssws 
    ;;
7|07) 
    clear 
    m-system 
    ;;
8|08) 
    clear 
    running 
    ;;
9|09) 
    clear 
    clearcache 
    ;;
10) 
    clear
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${yellow}               🔄 UPGRADE CORE ENGINE SYSTEM                  ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " This operation will patch/reinstall all underlying architecture:"
    echo -e "  ${green}✅${NC} Full SSH VPN Scripts suite"
    echo -e "  ${green}✅${NC} Daemon Protocol WebSockets engines"
    echo -e "  ${green}✅${NC} Core Xray Engine Configurations Framework"
    echo -e "  ${green}✅${NC} Interactive Menu Systems Management Layer"
    echo -e "  ${green}✅${NC} All default proxy endpoints configuration structures"
    echo ""
    echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " Initialize remote upgrade runtime execution? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e " [ ${yellow}⚙️${NC} ] Initiating script ecosystem update matrix..."
        echo ""
        
        # Deploy configuration backup snapshot directory structure safely
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_DIR="/root/backup-$TIMESTAMP"
        echo -e " [ ${cyan}•${NC} ] Structuring filesystem archive layer at: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        cp -r /etc/xray "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/stunnel "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/nginx "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/squid "$BACKUP_DIR/" 2>/dev/null || true
        cp -f /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null || true
        cp -f /root/domain "$BACKUP_DIR/" 2>/dev/null || true
        cp -f /root/domain.txt "$BACKUP_DIR/" 2>/dev/null || true
        echo -e " ${green}✓ Backup saved successfully.${NC}"
        echo ""
        
        # Remotely download and verify central upgrade binary
        echo -e " [ ${cyan}•${NC} ] Contacting remote GitHub distribution repository server..."
        cd /root
        wget -q -O update.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/update.sh
        if [ $? -eq 0 ]; then
            chmod +x update.sh
            sed -i -e 's/\r$//' update.sh
            echo -e " ${green}✓ Modern upgrade component staging completed.${NC}"
            echo ""
            echo -e " [ ${yellow}⚙️${NC} ] Launching updates script pipeline..."
            sleep 1
            bash update.sh
        else
            echo -e " ${red}✗ Central update descriptor download failed!${NC}"
            echo -e " [ ${yellow}⚙️${NC} ] Activating fallback bootstrap protocol..."
            
            # Fallback Routine Sequence Initiation
            wget -q -O setup.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh
            chmod +x setup.sh
            sed -i -e 's/\r$//' setup.sh
            bash setup.sh
            
            # Enforce updating interface paths mapping explicitly
            cd /usr/bin
            wget -q -O menu https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/menu.sh
            wget -q -O running https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/running.sh
            wget -q -O clearcache https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/clearcache.sh
            chmod +x menu running clearcache
            sed -i -e 's/\r$//' menu running clearcache
        fi
        
        echo ""
        echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${green}            🏆 ECOSYSTEM UPGRADE EXECUTED CLEANLY!             ${NC}"
        echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e " Backup reference archive pointer preserved at: ${yellow}$BACKUP_DIR${NC}"
        echo ""
        read -n 1 -s -r -p "Press any key to load fresh menu interface wrapper..."
        menu
    else
        echo -e "\n ${yellow}Upgrade transaction abandoned by client request.${NC}"
        sleep 1
        menu
    fi
    ;;
0|00|x|X) 
    clear 
    exit 
    ;;
*) 
    echo -e "${red}✗ Error: Invalid selection entry option!${NC}" 
    sleep 1 
    menu 
    ;;
esac