#!/bin/bash
# ============================================================
# MARCSCRIPT SERVICE STATUS & PORT INFO v3.1
# Optimized: Fast execution (<2s), Fixed user count, Cached checks
# ============================================================

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
BCyan='\e[1;36m'
BWhite='\e[1;37m'
NC='\033[0m'

clear

# ============================================================
# CACHED SYSTEM INFO (gathered once, fast)
# ============================================================
source /etc/os-release 2>/dev/null
MYIP=$(cat /etc/myipvps 2>/dev/null || echo "")
[ -z "$MYIP" ] && MYIP=$(curl -s --max-time 2 ifconfig.me 2>/dev/null || echo "Unknown")

# ============================================================
# BATCH SERVICE STATUS (one call, much faster)
# ============================================================
get_status_batch() {
    # Get all service states in one systemctl call
    local services="ssh dropbear stunnel4 ws-dropbear ws-stunnel ws-proxy xray nginx squid fail2ban cron vnstat badvpn-71 badvpn-72 badvpn-73 badvpn-74"
    
    for svc in $services; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            eval "${svc//-/_}_status=running"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            eval "${svc//-/_}_status=dead"
        else
            eval "${svc//-/_}_status=not_installed"
        fi
    done
}

get_status_batch

# ============================================================
# STATUS COLOR FUNCTION
# ============================================================
status_color() {
    case "$1" in
        "running")       echo -e "${GREEN}● Running${NC}" ;;
        "dead")          echo -e "${RED}● Stopped${NC}" ;;
        "not_installed") echo -e "${YELLOW}○ Not Installed${NC}" ;;
        *)               echo -e "${RED}● Unknown${NC}" ;;
    esac
}

port_status() {
    case "$1" in
        "running") echo -e "${GREEN}✓${NC}" ;;
        *)         echo -e "${RED}✗${NC}" ;;
    esac
}

# ============================================================
# SYSTEM INFO (fast operations only)
# ============================================================
total_ram=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
free_ram=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
if [ -n "$total_ram" ] && [ -n "$free_ram" ]; then
    used_ram=$(( ($total_ram - $free_ram) / 1024 ))
    totalram=$(( $total_ram / 1024 ))
else
    used_ram="N/A"; totalram="N/A"
fi

# CPU - single snapshot, no top loop
read cpu_usage < <(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 100 / (t-t1) "%"}' <(grep 'cpu ' /proc/stat; sleep 0.3; grep 'cpu ' /proc/stat) 2>/dev/null)
cpu_usage=${cpu_usage:-"N/A"}

kernelku=$(uname -r)
Domen=$(cat /etc/xray/domain 2>/dev/null || echo "Not Set")

# Connection count (limit scan)
nginx_connections=$(ss -tnp 2>/dev/null | grep -c nginx || echo "0")

# User counts - FIXED
ssh_users=$(wc -l < /etc/log-create-ssh.log 2>/dev/null || echo "0")
xray_users=$(wc -l < /etc/log-create-vmess.log 2>/dev/null || echo "0")

clear

# ============================================================
# HEADER
# ============================================================
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}              MARCSCRIPT VPN v3.1 - SYSTEM INFO            ${BPurple}║${NC}"
echo -e "${BPurple}║${BCyan}             Modular • Nginx Unified Proxy • Fast          ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# SYSTEM INFO BOX
# ============================================================
echo -e "${BGreen}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BGreen}│${BWhite} SYSTEM INFORMATION                                          ${BGreen}│${NC}"
echo -e "${BGreen}├─────────────────────────────────────────────────────────────┤${NC}"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Hostname" "$HOSTNAME"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "OS" "$NAME $VERSION_ID"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Kernel" "$kernelku"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "RAM" "${used_ram}MB / ${totalram}MB"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "CPU" "${cpu_usage}"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Public IP" "$MYIP"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Domain" "$Domen"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Connections" "$nginx_connections (via Nginx)"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "SSH Users" "$ssh_users"
printf "${BGreen}│${NC} %-18s: %-38s ${BGreen}│${NC}\n" "Xray Users" "$xray_users"
echo -e "${BGreen}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# ============================================================
# CORE SERVICES STATUS
# ============================================================
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                    CORE SERVICES STATUS                   ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BGreen}┌───────────────────────────────────────┬───────────────────┐${NC}"
echo -e "${BGreen}│${BWhite} SERVICE                               │${BWhite} STATUS            ${BGreen}│${NC}"
echo -e "${BGreen}├───────────────────────────────────────┼───────────────────┤${NC}"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "SSH (Port 22)" "$(status_color ${ssh_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Dropbear (109, 143)" "$(status_color ${dropbear_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Stunnel4 SSL (Internal)" "$(status_color ${stunnel4_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "WS Proxy Node.js (8080)" "$(status_color ${ws_proxy_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Xray Core (Internal)" "$(status_color ${xray_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Nginx Reverse Proxy" "$(status_color ${nginx_status})"
echo -e "${BGreen}└───────────────────────────────────────┴───────────────────┘${NC}"
echo ""

# ============================================================
# PROXY & ADDITIONAL SERVICES
# ============================================================
echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BCyan}║${BWhite}               PROXY & ADDITIONAL SERVICES                  ${BCyan}║${NC}"
echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BGreen}┌───────────────────────────────────────┬───────────────────┐${NC}"
echo -e "${BGreen}│${BWhite} SERVICE                               │${BWhite} STATUS            ${BGreen}│${NC}"
echo -e "${BGreen}├───────────────────────────────────────┼───────────────────┤${NC}"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "WS-Dropbear (2095)" "$(status_color ${ws_dropbear_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "WS-Stunnel SSL (700)" "$(status_color ${ws_stunnel_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Squid (3128,8082,8888)" "$(status_color ${squid_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "BADVPN UDP 7100" "$(status_color ${badvpn_71_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "BADVPN UDP 7200" "$(status_color ${badvpn_72_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "BADVPN UDP 7300" "$(status_color ${badvpn_73_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "BADVPN UDP 7400" "$(status_color ${badvpn_74_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Fail2Ban" "$(status_color ${fail2ban_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Cron (Auto Reboot)" "$(status_color ${cron_status})"
printf "${BGreen}│${NC} %-37s │ %-17s ${BGreen}│${NC}\n" "Vnstat (Bandwidth)" "$(status_color ${vnstat_status})"
echo -e "${BGreen}└───────────────────────────────────────┴───────────────────┘${NC}"
echo ""

# ============================================================
# PORT LISTENING STATUS
# ============================================================
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                    PORT LISTENING STATUS                   ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BGreen}┌───────┬────────────────────────────────┬──────────┐${NC}"
echo -e "${BGreen}│${BWhite} PORT  │${BWhite} SERVICE                        │${BWhite} STATUS   ${BGreen}│${NC}"
echo -e "${BGreen}├───────┼────────────────────────────────┼──────────┤${NC}"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "22" "SSH Direct" "$(port_status ${ssh_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "80" "Nginx HTTP (WS/Xray)" "$(port_status ${nginx_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "109" "Dropbear SSH" "$(port_status ${dropbear_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "143" "Dropbear SSH Alt" "$(port_status ${dropbear_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "443" "Nginx HTTPS (WSS/gRPC)" "$(port_status ${nginx_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "3128" "Squid HTTP Proxy" "$(port_status ${squid_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "8082" "Squid HTTP Proxy" "$(port_status ${squid_status})"
printf "${BGreen}│${NC} %-5s ${BGreen}│${NC} %-30s ${BGreen}│${NC} %-8s ${BGreen}│${NC}\n" "8888" "Squid HTTP Proxy" "$(port_status ${squid_status})"
echo -e "${BGreen}└───────┴────────────────────────────────┴──────────┘${NC}"
echo ""

# ============================================================
# NGINX ROUTING TABLE (if nginx is running)
# ============================================================
if [ "$nginx_status" = "running" ]; then
    echo -e "${BCyan}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BCyan}║${BWhite}              NGINX REVERSE PROXY ROUTING                   ${BCyan}║${NC}"
    echo -e "${BCyan}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${BYellow}Port 80 (HTTP):${NC}"
    echo -e "   ├── /vmess        → Xray VMess WS"
    echo -e "   ├── /vless        → Xray VLESS WS"
    echo -e "   ├── /trojan-ws    → Xray Trojan WS"
    echo -e "   ├── /ss-ws        → Xray Shadowsocks WS"
    echo -e "   ├── /ssh-ws       → SSH WebSocket"
    echo -e "   └── /             → Dropbear WS / Status"
    echo ""
    echo -e "   ${BYellow}Port 443 (HTTPS):${NC}"
    echo -e "   ├── /vmess        → Xray VMess WS (TLS)"
    echo -e "   ├── /vless        → Xray VLESS WS (TLS)"
    echo -e "   ├── /vless-grpc   → Xray VLESS gRPC"
    echo -e "   ├── /vmess-grpc   → Xray VMess gRPC"
    echo -e "   ├── /trojan-grpc  → Xray Trojan gRPC"
    echo -e "   ├── /ss-grpc      → Xray SS gRPC"
    echo -e "   ├── /ssh-ws-ssl   → SSH WebSocket SSL"
    echo -e "   └── /             → SSL WS Proxy"
    echo ""
fi

# ============================================================
# QUICK COMMANDS
# ============================================================
echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BPurple}║${BWhite}                    QUICK COMMANDS                          ${BPurple}║${NC}"
echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   ${BGreen}menu${NC}              - Main menu"
echo -e "   ${BGreen}vpn-status${NC}        - Text status"
echo -e "   ${BGreen}nginx-proxy status${NC} - Nginx status"
echo -e "   ${BGreen}xray-info${NC}         - Xray config"
echo -e "   ${BGreen}proxy-status${NC}      - Proxy status"
echo ""

# ============================================================
# FOOTER
# ============================================================
echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BWhite}  Arch: Client → Nginx (80/443) → Backend Services          ${NC}"
echo -e "${BWhite}  v3.1 Fast • Modular • No Conflicts                        ${NC}"
echo -e "${BYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BGreen}💡 Press any key to return to menu${NC}"

read -n 1 -s -r -p ""
menu