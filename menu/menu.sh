#!/bin/bash
MYIP=$(curl -sS ifconfig.me)
NET_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
echo "Checking VPS"
clear

# ============================================================
# COLOR DEFINITIONS
# ============================================================
DF='\e[39m'
Bold='\e[1m'
Blink='\e[5m'
yell='\e[33m'
red='\e[31m'
green='\e[32m'
blue='\e[34m'
PURPLE='\e[35m'
cyan='\e[36m'
Lred='\e[91m'
Lgreen='\e[92m'
Lyellow='\e[93m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
BCyan='\e[1;36m'
NC='\e[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
LIGHT='\033[0;37m'

# ============================================================
# VPS INFORMATION
# ============================================================
domain=$(cat /etc/xray/domain 2>/dev/null || echo "")

# SSL Certificate Status
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

tlsStatus=${remainingDays}
if [[ ${remainingDays} -le 0 ]]; then
	tlsStatus="expired"
fi

# OS Uptime
uptime="$(uptime -p | cut -d " " -f 2-10)"

# Network Traffic
dtoday="$(vnstat -i $NET_IFACE | grep "today" | awk '{print $2" "substr ($3, 1, 1)}')"
utoday="$(vnstat -i $NET_IFACE | grep "today" | awk '{print $5" "substr ($6, 1, 1)}')"
ttoday="$(vnstat -i $NET_IFACE | grep "today" | awk '{print $8" "substr ($9, 1, 1)}')"

dyest="$(vnstat -i $NET_IFACE | grep "yesterday" | awk '{print $2" "substr ($3, 1, 1)}')"
uyest="$(vnstat -i $NET_IFACE | grep "yesterday" | awk '{print $5" "substr ($6, 1, 1)}')"
tyest="$(vnstat -i $NET_IFACE | grep "yesterday" | awk '{print $8" "substr ($9, 1, 1)}')"

dmon="$(vnstat -i $NET_IFACE -m | grep "`date +"%b '%y"`" | awk '{print $3" "substr ($4, 1, 1)}')"
umon="$(vnstat -i $NET_IFACE -m | grep "`date +"%b '%y"`" | awk '{print $6" "substr ($7, 1, 1)}')"
tmon="$(vnstat -i $NET_IFACE -m | grep "`date +"%b '%y"`" | awk '{print $9" "substr ($10, 1, 1)}')"

# User Info
Exp2=$"Lifetime"
Name=$"marc"

# CPU Information
cpu_usage1="$(ps aux | awk 'BEGIN {sum=0} {sum+=$3}; END {print sum}')"
cpu_usage="$((${cpu_usage1/\.*} / ${corediilik:-1}))"
cpu_usage+=" %"

# System Info
DAY=$(date +%A)
DATE=$(date +%m/%d/%Y)
DATE2=$(date -R | cut -d " " -f -5)
IPVPS=$(curl -s ifconfig.me )
cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
tram=$( free -m | awk 'NR==2 {print $2}' )
uram=$( free -m | awk 'NR==2 {print $3}' )
fram=$( free -m | awk 'NR==2 {print $4}' )

clear 
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo -e "\e[1;34m                      📡 MARCSCRIPT VPN                       \e[0m"
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo ""
echo -e "\e[1;32m ───────────── VPS INFORMATION ─────────────\e[0m"
echo -e "\e[1;32m OS          \e[0m: "`hostnamectl | grep "Operating System" | cut -d ' ' -f5-`	
echo -e "\e[1;32m Uptime      \e[0m: $uptime"
echo -e "\e[1;32m IP          \e[0m: $IPVPS"	
echo -e "\e[1;32m Domain      \e[0m: $domain"	
echo -e "\e[1;32m Date & Time \e[0m: $DATE2"
echo ""
echo -e "\e[1;32m ───────────── RAM INFORMATION ─────────────\e[0m"
echo -e "\e[1;32m RAM Used    \e[0m: $uram MB"	
echo -e "\e[1;32m RAM Total   \e[0m: $tram MB"
echo ""
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo -e "\e[1;34m                         📋 MENU                              \e[0m"
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo ""
echo -e "\e[1;36m 1 \e[0m: Menu SSH (22, 2222, 8443, 8444, 8445, 8080, 8082)"
echo -e "\e[1;36m 2 \e[0m: Menu Vmess (80, 443)"
echo -e "\e[1;36m 3 \e[0m: Menu Vless (80, 443)"
echo -e "\e[1;36m 4 \e[0m: Menu Trojan (80, 443)"
echo -e "\e[1;36m 5 \e[0m: Menu Shadowsocks (80, 443)"
echo -e "\e[1;36m 6 \e[0m: Menu Setting"
echo -e "\e[1;36m 7 \e[0m: Status Service"
echo -e "\e[1;36m 8 \e[0m: Clear RAM Cache"
echo -e "\e[1;36m 9 \e[0m: Update / Reinstall Script"
echo -e "\e[1;36m x \e[0m: Exit"
echo ""
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo -e "\e[1;32m Client Name  \e[0m: $Name"
echo -e "\e[1;32m Expired      \e[0m: $Exp2"
echo -e "\e[1;32m SSL Status   \e[0m: $tlsStatus days remaining"
echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
echo ""
echo -e "\e[1;36m ─────────────────── MARC VPN ───────────────────\e[0m"
echo ""
read -p " Select menu :  "  opt
echo ""

case $opt in
1) clear ; m-sshovpn ;;
2) clear ; m-vmess ;;
3) clear ; m-vless ;;
4) clear ; m-trojan ;;
5) clear ; m-ssws ;;
6) clear ; m-system ;;
7) clear ; running ;;
8) clear ; clearcache ;;
9) 
    clear
    echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
    echo -e "\e[1;34m                  🔄 UPDATE / REINSTALL SCRIPT              \e[0m"
    echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
    echo ""
    echo -e "\e[1;36m This will update/reinstall the following:${NC}"
    echo -e "  ✅ SSH VPN Script"
    echo -e "  ✅ WebSocket Script"
    echo -e "  ✅ Xray Script"
    echo -e "  ✅ Menu & Management Scripts"
    echo -e "  ✅ All configuration files"
    echo ""
    echo -e "\e[1;33m ═══════════════════════════════════════════════════════════════\e[0m"
    echo ""
    read -p " Continue with update? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "\e[1;32m Starting update...${NC}"
        echo ""
        
        # Backup current config
        echo -e "\e[1;33m Creating backup...${NC}"
        mkdir -p /root/backup-$(date +%Y%m%d_%H%M%S)
        BACKUP_DIR="/root/backup-$(date +%Y%m%d_%H%M%S)"
        cp -r /etc/xray "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/stunnel "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/nginx "$BACKUP_DIR/" 2>/dev/null || true
        cp -r /etc/squid "$BACKUP_DIR/" 2>/dev/null || true
        cp -f /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null || true
        cp -f /root/domain "$BACKUP_DIR/" 2>/dev/null || true
        echo -e "\e[1;32m ✅ Backup saved to: $BACKUP_DIR${NC}"
        echo ""
        
        # Download and run update script from menu/update.sh
        echo -e "\e[1;33m Downloading update script...${NC}"
        cd /root
        wget -q -O update.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/update.sh
        if [ $? -eq 0 ]; then
            chmod +x update.sh
            sed -i -e 's/\r$//' update.sh
            echo -e "\e[1;32m ✅ Update script downloaded${NC}"
            echo ""
            echo -e "\e[1;33m Running update script...${NC}"
            bash update.sh
        else
            echo -e "\e[1;31m ❌ Failed to download update script${NC}"
            echo -e "\e[1;33m Trying fallback method...${NC}"
            
            # Fallback: Download and run setup directly
            wget -q -O setup.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh
            chmod +x setup.sh
            sed -i -e 's/\r$//' setup.sh
            bash setup.sh
            
            # Update menu scripts
            cd /usr/bin
            wget -q -O menu https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/menu.sh
            wget -q -O running https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/running.sh
            wget -q -O clearcache https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/menu/clearcache.sh
            chmod +x menu running clearcache
        fi
        
        echo ""
        echo -e "\e[1;32m ═══════════════════════════════════════════════════════════════\e[0m"
        echo -e "\e[1;34m                  ✅ UPDATE COMPLETED!                      \e[0m"
        echo -e "\e[1;32m ═══════════════════════════════════════════════════════════════\e[0m"
        echo ""
        echo -e "\e[1;33m 📁 Backup Location: $BACKUP_DIR${NC}"
        echo ""
        echo -e "\e[1;36m Press any key to return to menu...${NC}"
        read -n 1 -s -r
        menu
    else
        echo -e "\e[1;33m Update cancelled.${NC}"
        sleep 1
        menu
    fi
    ;;
x) clear ; exit ;;
*) echo "Invalid option!" ; sleep 1 ; menu ;;
esac