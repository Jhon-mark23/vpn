#!/bin/bash
# ============================================================
# MARCSCRIPT VPN - SERVICE STATUS
# Version: 3.0 (Python WS + DNSTT)
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
MYIP=$(cat /etc/myipvps 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "Unknown")
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
    systemctl is-active --quiet "$1" 2>/dev/null && echo "${GREEN}● Running${NC}" || echo "${RED}● Not Running${NC}"
}

# Check all services
SSH_STATUS=$(svc ssh)
STUNNEL_STATUS=$(svc stunnel4)
WS_8080_STATUS=$(svc ws-8080)
WS_9445_STATUS=$(svc ws-9445)
WSS_9443_STATUS=$(svc ws-9443)
XRAY_STATUS=$(svc xray)
NGINX_STATUS=$(svc nginx)
FAIL2BAN_STATUS=$(svc fail2ban)
CRON_STATUS=$(svc cron)
DNSTT_STATUS=$(svc server-sldns)

# ---------- PORT LISTENING CHECK ----------
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
printf "  ${CYAN}%-14s${NC} : %s\n" "Hostname" "$(hostname)"
printf "  ${CYAN}%-14s${NC} : %s %s\n" "OS" "$NAME" "$VERSION_ID"
printf "  ${CYAN}%-14s${NC} : %s\n" "Kernel" "$kernelku"
printf "  ${CYAN}%-14s${NC} : %s\n" "Public IP" "$MYIP"
printf "  ${CYAN}%-14s${NC} : %s\n" "Domain" "$Domen"
printf "  ${CYAN}%-14s${NC} : ${used_ram}MB / ${totalram}MB\n" "RAM"
printf "  ${CYAN}%-14s${NC} : ${cpu_usage}%%\n" "CPU"
echo ""

# ---------- SERVICE STATUS ----------
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                    SERVICE STATUS                      ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}┌────────────────────────────────┬──────────┬──────────────┐${NC}"
echo -e "${CYAN}│${WHITE} SERVICE                        ${CYAN}│${WHITE} PORT     ${CYAN}│${WHITE} STATUS       ${CYAN}│${NC}"
echo -e "${CYAN}├────────────────────────────────┼──────────┼──────────────┤${NC}"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "SSH Server" "22,80" "$SSH_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Stunnel4 (SSL)" "8443-8445" "$STUNNEL_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Python WS Proxy" "8080" "$WS_8080_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Python WS Proxy Alt" "9445" "$WS_9445_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Python WSS Proxy" "9443" "$WSS_9443_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Xray Core" "443" "$XRAY_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Nginx Web Server" "81,8081" "$NGINX_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "DNSTT (SlowDNS)" "5300" "$DNSTT_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Fail2Ban" "auto" "$FAIL2BAN_STATUS"
printf "${CYAN}│${NC} %-30s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-12s ${CYAN}│${NC}\n" "Cron Scheduler" "-" "$CRON_STATUS"
echo -e "${CYAN}└────────────────────────────────┴──────────┴──────────────┘${NC}"

echo ""

# ---------- PORT STATUS ----------
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                      PORT STATUS                       ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}  SSH:          $(port_check 22) 22  $(port_check 80) 80"
echo -e "${CYAN}  SSL:          $(port_check 8443) 8443  $(port_check 8444) 8444  $(port_check 8445) 8445"
echo -e "${CYAN}  WS Proxy:     $(port_check 8080) 8080  $(port_check 9445) 9445  $(port_check 9443) 9443"
echo -e "${CYAN}  Xray/Nginx:   $(port_check 443) 443  $(port_check 81) 81  $(port_check 8081) 8081"
echo -e "${CYAN}  DNSTT:        $(port_check 5300) 5300 (UDP)"
echo -e "${CYAN}  BADVPN:       7100-7400 (UDP)"
echo ""

# ---------- QUICK COMMANDS ----------
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                     QUICK COMMANDS                     ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}menu${NC}           Main menu"
echo -e "  ${CYAN}usernew${NC}        Create SSH user"
echo -e "  ${CYAN}trial${NC}          Create trial user"
echo -e "  ${CYAN}cek${NC}            Check user accounts"
echo -e "  ${CYAN}add-ws${NC}         Add VMess account"
echo -e "  ${CYAN}add-vless${NC}      Add VLess account"
echo -e "  ${CYAN}add-tr${NC}         Add Trojan account"
echo ""

# ---------- FOOTER ----------
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}  MarcScript VPN | $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""