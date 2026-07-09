#!/bin/bash
# ============================================================
# MARCSCRIPT VPN - SERVICE STATUS
# Version: 3.3 (Press any key to return)
# ============================================================

clear

# ---------- COLOURS ----------
GREEN='\033[0;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
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
        echo -e "${GREEN}RUNNING${NC}"
    else
        echo -e "${RED}STOPPED${NC}"
    fi
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
DNSTT_STATUS=$(svc dnstt)

# ---------- DISPLAY ----------
echo "=========================================="
echo "         SYSTEM INFORMATION               "
echo "=========================================="
echo ""
echo "Hostname      : $(hostname)"
echo "OS            : $NAME $VERSION_ID"
echo "Kernel        : $kernelku"
echo "Public IP     : $MYIP"
echo "Domain        : $Domen"
echo "RAM           : ${used_ram}MB / ${totalram}MB"
echo "CPU           : ${cpu_usage}%"
echo ""

# ---------- SERVICE STATUS ----------
echo "=========================================="
echo "         SERVICE STATUS                   "
echo "=========================================="
echo ""
echo "SSH Server           : $SSH_STATUS"
echo "Stunnel4 (SSL)       : $STUNNEL_STATUS"
echo "Python WS Proxy      : $WS_8080_STATUS"
echo "Python WS Proxy Alt  : $WS_9445_STATUS"
echo "Python WSS Proxy     : $WSS_9443_STATUS"
echo "Xray Core            : $XRAY_STATUS"
echo "Nginx Web Server     : $NGINX_STATUS"
echo "DNSTT (SlowDNS)      : $DNSTT_STATUS"
echo "Fail2Ban             : $FAIL2BAN_STATUS"
echo "Cron Scheduler       : $CRON_STATUS"
echo ""

# ---------- QUICK COMMANDS ----------
echo "Quick Commands: menu | usernew | trial | cek | add-ws | add-vless | add-tr"
echo ""

# ---------- PRESS ANY KEY TO RETURN ----------
echo "=========================================="
echo "  Press any key to return to menu...     "
echo "=========================================="

# Wait for any key press
read -n 1 -s

# Go back to menu
menu 2>/dev/null || {
    clear
    echo -e "${GREEN}Menu command not found. Type 'menu' manually.${NC}"
    exit 0
}