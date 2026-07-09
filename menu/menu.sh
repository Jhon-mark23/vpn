#!/bin/bash
# ============================================================
# MARCSCRIPT VPN - MAIN MENU
# Version: 3.0 (Simple + Updated Services)
# ============================================================

MYIP=$(curl -sS ifconfig.me 2>/dev/null || echo "Unknown")
clear

# ---------- COLOURS ----------
purple='\033[0;35m'
cyan='\033[1;36m'
green='\033[0;32m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

# ---------- SYSTEM INFO ----------
domain=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "Not Set")
PUBKEY=$(cat /etc/dnstt/private.key 2>/dev/null || echo "Not Generated")
nsdomain="ns.${domain}"
os_name=$(hostnamectl 2>/dev/null | grep "Operating System" | cut -d: -f2 | xargs)
uptime_info=$(uptime -p 2>/dev/null | cut -d' ' -f2-)
tram=$(free -m 2>/dev/null | awk 'NR==2{print $2}')
uram=$(free -m 2>/dev/null | awk 'NR==2{print $3}')
Exp2="Lifetime"

# ---------- HEADER ----------
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}         MARCSCRIPT VPN - MAIN MENU                    ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ---------- SYSTEM INFO ----------
echo -e "${cyan}┌─────────────────────────────────────────────────────────────┐${NC}"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "OS" "$os_name"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "Uptime" "$uptime_info"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "IP" "$MYIP"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "Domain" "$domain"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "NS Domain" "$nsdomain"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "Memory" "${uram}MB / ${tram}MB"
printf "${cyan}│${NC} ${white}%-12s${NC}: %-44s ${cyan}│${NC}\n" "DNSTT Key" "$PUBKEY"
echo -e "${cyan}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# ---------- MENU ----------
echo -e "${white}  [${green}1${white}] ${cyan}SSH & WebSocket Menu${NC}"
echo -e "${white}  [${green}2${white}] ${cyan}Xray VMess/VLess/Trojan Menu${NC}"
echo -e "${white}  [${green}3${white}] ${cyan}System & Settings Menu${NC}"
echo -e "${white}  [${green}4${white}] ${cyan}Service Status Dashboard${NC}"
echo -e "${white}  [${green}5${white}] ${cyan}Clear RAM Cache${NC}"
echo -e "${white}  [${green}6${white}] ${cyan}Update / Reinstall Scripts${NC}"
echo ""
echo -e "${white}  [${red}0${white}] ${red}Exit${NC}"
echo ""

# ---------- FOOTER ----------
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${cyan}Client:${NC} ${white}MarcScript${NC} | ${cyan}Expiry:${NC} ${green}${Exp2}${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p " Select option [0-6]: " opt

case $opt in
1|01)
    clear
    m-sshovpn 2>/dev/null || {
        echo -e "${red}SSH Menu not found!${NC}"
        sleep 1
        menu
    }
    ;;
2|02)
    clear
    m-xray 2>/dev/null || {
        echo -e "${red}Xray Menu not found!${NC}"
        sleep 1
        menu
    }
    ;;
3|03)
    clear
    m-system 2>/dev/null || {
        echo -e "${red}System Menu not found!${NC}"
        sleep 1
        menu
    }
    ;;
4|04)
    clear
    running 2>/dev/null || {
        # Fallback inline status if running.sh not found
        echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${purple}║${white}                  SERVICE STATUS                       ${purple}║${NC}"
        echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        for svc in ssh stunnel4 nginx xray fail2ban ws-8080 ws-9443 ws-9445 server-sldns; do
            if systemctl is-active --quiet $svc 2>/dev/null; then
                echo -e " ${green}●${NC} $svc ${green}Running${NC}"
            else
                echo -e " ${red}●${NC} $svc ${red}Not Running${NC}"
            fi
        done
        echo ""
        read -n 1 -s -r -p "Press any key to return..."
    }
    menu
    ;;
5|05)
    clear
    echo -e "${cyan}Clearing RAM cache...${NC}"
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    echo -e "${green}✓ RAM cache cleared!${NC}"
    sleep 1
    menu
    ;;
6|06)
    clear
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${yellow}              UPDATE / REINSTALL SYSTEM                    ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " This will update all VPN scripts:"
    echo -e "  ${green}•${NC} SSH & WebSocket scripts"
    echo -e "  ${green}•${NC} Xray core & configs"
    echo -e "  ${green}•${NC} Menu system files"
    echo -e "  ${green}•${NC} Management tools"
    echo ""
    read -p " Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${cyan}Starting update...${NC}"
        
        # Download update script from private repo
        gtoken=$(cat /root/token 2>/dev/null || cat /root/token.txt 2>/dev/null)
        if [[ -n "$gtoken" ]]; then
            curl -sS -H "Authorization: Bearer $gtoken" \
                -H "Accept: application/vnd.github.raw" \
                "https://api.github.com/repos/Jhon-mark23/vpn/contents/menu/update.sh?ref=main" \
                -o /root/update.sh
        else
            echo -e "${red}No GitHub token found!${NC}"
            sleep 2
            menu
        fi
        
        chmod +x /root/update.sh
        sed -i 's/\r$//' /root/update.sh
        bash /root/update.sh
    else
        echo -e "${yellow}Update cancelled.${NC}"
        sleep 1
        menu
    fi
    ;;
0|00|x|X)
    clear
    echo -e "${green}Goodbye!${NC}"
    exit 0
    ;;
*)
    echo -e "${red}Invalid option!${NC}"
    sleep 1
    menu
    ;;
esac