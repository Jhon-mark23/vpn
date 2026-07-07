#!/bin/bash
# ============================================================
# MARCSCRIPT VPN - SERVICE STATUS
# Version: 3.1 (Auto-return to menu)
# ============================================================

clear

# ---------- COLOURS ----------
GREEN='\033[0;32m'
RED='\033[1;31m'
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---------- GET SYSTEM INFO ----------
source /etc/os-release 2>/dev/null
MYIP=$(cat /etc/myipvps 2>/dev/null || curl -s ipv4.icanhazip.com 2>/dev/null || echo "Unknown")
Domen=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "Not Set")
kernelku=$(uname -r)

# RAM Info
total_ram=$(grep "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')
[ -z "$total_ram" ] && total_ram=0
free_ram=$(grep "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}')
[ -z "$free_ram" ] && free_ram=0
totalram=$((total_ram / 1024))
used_ram=$(((total_ram - free_ram) / 1024))
[ "$used_ram" -lt 0 ] && used_ram=0

# CPU Usage
cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
[ -z "$cpu_usage" ] && cpu_usage="N/A"

# ---------- SERVICE STATUS CHECK ----------
svc() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}● Not Running${NC}"
    fi
}

# Check all services
SSH_STATUS=$(svc ssh 2>/dev/null)
STUNNEL_STATUS=$(svc stunnel4 2>/dev/null)
WS_8080_STATUS=$(svc ws-8080 2>/dev/null)
WS_9445_STATUS=$(svc ws-9445 2>/dev/null)
WSS_9443_STATUS=$(svc ws-9443 2>/dev/null)
XRAY_STATUS=$(svc xray 2>/dev/null)
NGINX_STATUS=$(svc nginx 2>/dev/null)
FAIL2BAN_STATUS=$(svc fail2ban 2>/dev/null)
CRON_STATUS=$(svc cron 2>/dev/null)
DNSTT_STATUS=$(svc server-sldns 2>/dev/null)

# ---------- PORT CHECK ----------
port_check() {
    if ss -tlnp 2>/dev/null | grep -q ":$1 "; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}●${NC}"
    fi
}

# ---------- DISPLAY ----------
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                  SYSTEM INFORMATION                     ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
printf "  ${CYAN}%-12s${NC} : %s\n" "Hostname" "$(hostname)"
printf "  ${CYAN}%-12s${NC} : %s %s\n" "OS" "$NAME" "$VERSION_ID"
printf "  ${CYAN}%-12s${NC} : %s\n" "Kernel" "$kernelku"
printf "  ${CYAN}%-12s${NC} : %s\n" "Public IP" "$MYIP"
printf "  ${CYAN}%-12s${NC} : %s\n" "Domain" "$Domen"
printf "  ${CYAN}%-12s${NC} : ${used_ram}MB / ${totalram}MB\n" "RAM"
printf "  ${CYAN}%-12s${NC} : ${cpu_usage}%%\n" "CPU"
echo ""

# ---------- SERVICE STATUS ----------
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                    SERVICE STATUS                      ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}┌──────────────────────────────┬──────────┬──────────────┐${NC}"
echo -e "${CYAN}│${WHITE} SERVICE                      ${CYAN}│${WHITE} PORT     ${CYAN}│${WHITE} STATUS       ${CYAN}│${NC}"
echo -e "${CYAN}├──────────────────────────────┼──────────┼──────────────┤${NC}"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "SSH Server" "22,80" "$SSH_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Stunnel4 (SSL)" "8443-45" "$STUNNEL_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Python WS Proxy" "8080" "$WS_8080_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Python WS Proxy Alt" "9445" "$WS_9445_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Python WSS Proxy" "9443" "$WSS_9443_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Xray Core" "443" "$XRAY_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Nginx Web Server" "81,8081" "$NGINX_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "DNSTT (SlowDNS)" "5300" "$DNSTT_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Fail2Ban" "auto" "$FAIL2BAN_STATUS"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %s ${CYAN}│${NC}\n" "Cron Scheduler" "-" "$CRON_STATUS"
echo -e "${CYAN}└──────────────────────────────┴──────────┴──────────────┘${NC}"

echo ""

# ---------- PORT STATUS ----------
echo -e "${CYAN}  Ports: $(port_check 22)22 $(port_check 80)80 $(port_check 443)443 $(port_check 8443)8443 $(port_check 8080)8080 $(port_check 9443)9443 $(port_check 9445)9445 $(port_check 5300)5300${NC}"
echo ""

# ---------- QUICK COMMANDS ----------
echo -e "${YELLOW}  menu | usernew | trial | cek | add-ws | add-vless | add-tr${NC}"
echo ""

# ---------- AUTO-RETURN TO MENU ----------
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}  Returning to menu in 3 seconds... ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Countdown and auto-return
for i in 3 2 1; do
    echo -ne "\r  Auto-return in ${i}... (press any key to return now) "
    read -t 1 -n 1 key 2>/dev/null
    if [ $? -eq 0 ]; then
        echo ""
        break
    fi
done

# Go back to menu
menu 2>/dev/null || {
    clear
    echo -e "${GREEN}Menu command not found. Type 'menu' manually.${NC}"
    exit 0
}