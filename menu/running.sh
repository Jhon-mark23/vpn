#!/bin/bash
# ============================================================
# MARCSCRIPT SERVICE STATUS & PORT INFO
# ============================================================

# Colors
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
NC='\033[0m'
yl='\e[32;1m'
bl='\e[36;1m'
gl='\e[32;1m'
rd='\e[31;1m'
mg='\e[0;95m'
blu='\e[34m'
op='\e[35m'
or='\033[1;33m'
bd='\e[1m'
color1='\e[031;1m'
color2='\e[34;1m'
color3='\e[0m'
red='\e[1;31m'
green='\e[1;32m'
NC='\e[0m'

green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }

clear

# ============================================================
# GETTING SYSTEM INFORMATION
# ============================================================
source /etc/os-release
Versi_OS=$VERSION
ver=$VERSION_ID
Tipe=$NAME
URL_SUPPORT=$HOME_URL
basedong=$ID

MYIP=$(cat /etc/myipvps 2>/dev/null || curl -s ifconfig.me)

# ============================================================
# SERVICE STATUS
# ============================================================
ssh_service=$(systemctl status ssh | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
dropbear_status=$(systemctl status dropbear | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
stunnel_service=$(systemctl status stunnel4 | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
wstls=$(systemctl status ws-stunnel.service 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
wsdrop=$(systemctl status ws-dropbear.service 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
xray_status=$(systemctl status xray | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
nginx_status=$(systemctl status nginx | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
squid_status=$(systemctl status squid | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
fail2ban_service=$(systemctl status fail2ban | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
cron_service=$(systemctl status cron | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
vnstat_service=$(systemctl status vnstat | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
ws_proxy=$(systemctl status ws-proxy 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)

# ============================================================
# STATUS COLOR FUNCTION
# ============================================================
status_color() {
    if [[ $1 == "running" ]]; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Not Running${NC}"
    fi
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================
total_ram=$(grep "MemTotal: " /proc/meminfo | awk '{ print $2}')
free_ram=$(grep "MemAvailable: " /proc/meminfo | awk '{ print $2}')
used_ram=$(( ($total_ram - $free_ram) / 1024 ))
totalram=$(($total_ram/1024))
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
kernelku=$(uname -r)
Domen="$(cat /etc/xray/domain 2>/dev/null || echo "Not Set")"
Name="MarcScript"
Exp="Lifetime"

clear

# ============================================================
# HEADER
# ============================================================
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                    SYSTEM INFORMATION                   ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BGreen} Hostname    ${NC}: $HOSTNAME"
echo -e "${BGreen} OS Name     ${NC}: $Tipe"
echo -e "${BGreen} Kernel      ${NC}: $kernelku"
echo -e "${BGreen} RAM Usage   ${NC}: ${used_ram}MB / ${totalram}MB"
echo -e "${BGreen} CPU Usage   ${NC}: ${cpu_usage}%"
echo -e "${BGreen} Public IP   ${NC}: $MYIP"
echo -e "${BGreen} Domain      ${NC}: $Domen"
echo ""
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                  SERVICE STATUS                      ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# SERVICE STATUS TABLE
# ============================================================
echo -e "${BGreen}┌─────────────────────────────┬─────────────────────────────┐${NC}"
echo -e "${BGreen}│${BWhite} SERVICE                    │${BWhite} STATUS                      │${NC}"
echo -e "${BGreen}├─────────────────────────────┼─────────────────────────────┤${NC}"
printf "${BGreen}│${NC} SSH / OpenSSH              │ %-27s${BGreen}│${NC}\n" "$(status_color $ssh_service)"
printf "${BGreen}│${NC} Dropbear                   │ %-27s${BGreen}│${NC}\n" "$(status_color $dropbear_status)"
printf "${BGreen}│${NC} Stunnel4 (SSL)             │ %-27s${BGreen}│${NC}\n" "$(status_color $stunnel_service)"
printf "${BGreen}│${NC} WebSocket (WS)             │ %-27s${BGreen}│${NC}\n" "$(status_color $wsdrop)"
printf "${BGreen}│${NC} WebSocket SSL (WSS)        │ %-27s${BGreen}│${NC}\n" "$(status_color $wstls)"
printf "${BGreen}│${NC} WebSocket Proxy (Node.js)  │ %-27s${BGreen}│${NC}\n" "$(status_color $ws_proxy)"
printf "${BGreen}│${NC} Xray / V2Ray               │ %-27s${BGreen}│${NC}\n" "$(status_color $xray_status)"
printf "${BGreen}│${NC} Nginx                      │ %-27s${BGreen}│${NC}\n" "$(status_color $nginx_status)"
printf "${BGreen}│${NC} Squid Proxy                │ %-27s${BGreen}│${NC}\n" "$(status_color $squid_status)"
printf "${BGreen}│${NC} Fail2Ban                   │ %-27s${BGreen}│${NC}\n" "$(status_color $fail2ban_service)"
printf "${BGreen}│${NC} Cron                       │ %-27s${BGreen}│${NC}\n" "$(status_color $cron_service)"
printf "${BGreen}│${NC} Vnstat                     │ %-27s${BGreen}│${NC}\n" "$(status_color $vnstat_service)"
echo -e "${BGreen}└─────────────────────────────┴─────────────────────────────┘${NC}"

echo ""
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                    MARCSCRIPT VPN                     ${BPurple}║${NC}"
echo -e "${BPurple}║${BCyan}              All Services Running!                     ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  💡 Press any key to return to menu${NC}"
echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

read -n 1 -s -r -p ""
menu