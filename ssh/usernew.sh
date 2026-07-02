#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - CREATE SSH USER
# ============================================================

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

# Fetch Active Configuration Domain
domen=""
for path in "/root/domain.txt" "/etc/xray/domain" "/etc/v2ray/domain" "/root/domain"; do
    if [ -s "$path" ]; then
        domen=$(cat "$path" | tr -d '[:space:]')
        break
    fi
done
[ -z "$domen" ] && domen=$(wget -qO- ipv4.icanhazip.com)

# Scraping active service configurations
IP=$(wget -qO- ipv4.icanhazip.com || curl -sS ifconfig.me)
opensh="22"
portsshws="8080"
wsssl="8445"
ssl="8443"

# Banner Implementation
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}                     • CREATE SSH VPN ACCOUNT •                ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Username Intake and Validation Check
while true; do
    read -p " Enter Username : " Login
    Login="${Login//[[:space:]]/}"
    if [ -z "$Login" ]; then
        echo -e "${red}✗ Error: Username cannot be blank!${NC}"
        continue
    fi
    if id "$Login" &>/dev/null; then
        echo -e "${red}✗ Error: User '$Login' already exists! Choose another name.${NC}"
        continue
    fi
    break
done

read -p " Enter Password : " Pass
read -p " Active Duration (Days): " masaaktif

# Validation fallbacks for active duration integers
if ! [[ "$masaaktif" =~ ^[0-9]+$ ]]; then
    masaaktif=30
fi

# Create System User Explicitly Non-Shell
useradd -e "$(date -d "$masaaktif days" +"%Y-%m-%d")" -s /bin/false -M "$Login"
echo -e "$Pass\n$Pass" | passwd "$Login" &> /dev/null
exp="$(chage -l "$Login" | grep "Account expires" | awk -F": " '{print $2}')"

clear

# Output Generation Block
{
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${cyan}                    📡 SSH VPN ACCOUNT DETAIL                 ${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " Username    : ${green}$Login${NC}"
echo -e " Password    : ${green}$Pass${NC}"
echo -e " Expired On  : ${yellow}$exp ($masaaktif Days)${NC}"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"
echo -e " IP Address  : $IP"
echo -e " Host/Domain : $domen"
echo -e " OpenSSH     : $opensh"
echo -e " SSH WS      : $portsshws"
echo -e " SSH SSL WS  : $IP:$wsssl"
echo -e " SSL/TLS     : $ssl"
echo -e " UDPGW Port  : 7100-7400"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${yellow}⚙️ HTTP CUSTOM / HTTP INJECTOR WEBSOCKET PAYLOADS${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${cyan}■ TLS / WSS Payload:${NC}"
echo -e "GET wss://[host]/ HTTP/1.1[crlf]Host: ${domen}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo -e ""
echo -e "${cyan}■ Direct / WS Payload:${NC}"
echo -e "GET / HTTP/1.1[crlf]Host: ${domen}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
} | tee -a /etc/log-create-ssh.log

echo ""
read -n 1 -s -r -p "Press any key to return to system menu..."
menu
