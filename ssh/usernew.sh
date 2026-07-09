#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - CREATE SSH USER
# ============================================================

echo "hello"

# ---------- COLOURS ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
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
IP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -sS ifconfig.me 2>/dev/null || echo "Unknown")
domain=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null || cat /root/domain 2>/dev/null || echo "None")
opensh="22"
portsshws="8080"
wsssl="8445"
ssl="8443"

# Check if PUBKEY exists, if not set placeholder
if [ -f "/etc/slowdns/server.pub" ]; then
    PUBKEY=$(cat "/etc/slowdns/server.pub" 2>/dev/null | tr -d '[:space:]')
else
    PUBKEY="Not Configured"
fi

# Set NS domain
if [[ "$domain" != "None" && "$domain" != "" ]]; then
    nsdomain="ns.${domain}"
else
    nsdomain="Not Set"
fi

# Banner
echo "=========================================="
echo "          CREATE SSH VPN ACCOUNT           "
echo "=========================================="
echo ""

# Username Intake and Validation
while true; do
    read -p " Enter Username : " Login
    Login="${Login//[[:space:]]/}"
    if [ -z "$Login" ]; then
        echo -e "${RED}Error: Username cannot be blank!${NC}"
        continue
    fi
    if id "$Login" &>/dev/null; then
        echo -e "${RED}Error: User '$Login' already exists! Choose another name.${NC}"
        continue
    fi
    break
done

# Hide password input
read -s -p " Enter Password : " Pass
echo ""
read -p " Active Duration (Days): " masaaktif
echo ""

# Validation fallbacks for active duration integers
if ! [[ "$masaaktif" =~ ^[0-9]+$ ]]; then
    masaaktif=30
fi

# Create System User
useradd -e "$(date -d "$masaaktif days" +"%Y-%m-%d")" -s /bin/false -M "$Login"
echo -e "$Pass\n$Pass" | passwd "$Login" &> /dev/null
exp="$(chage -l "$Login" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')"

# If exp is empty, set fallback
if [ -z "$exp" ]; then
    exp="$(date -d "$masaaktif days" +"%b %d, %Y")"
fi

clear

# Output Generation Block
{
echo "=========================================="
echo "          SSH VPN ACCOUNT DETAIL          "
echo "=========================================="
echo "Username        : $Login"
echo "Password        : $Pass"
echo "Expired On      : $exp ($masaaktif Days)"
echo "------------------------------------------"
echo "IP Address      : $IP"
echo "Host/Domain     : $domen"
if [ -n "$PUBKEY" ] && [ "$PUBKEY" != "Not Configured" ]; then
    echo "PUBKEY          : $PUBKEY"
    echo "NS              : $nsdomain"
fi
echo "OpenSSH         : $opensh"
echo "SSH WS          : $portsshws"
echo "SSH SSL WS      : $IP:$wsssl"
echo "SSL/TLS         : $ssl"
echo "UDPGW Port      : 7100-7400"
echo "=========================================="
echo "HTTP CUSTOM / HTTP INJECTOR PAYLOADS"
echo "=========================================="
echo "Http Custom:"
echo "$IP:22@$Login:$Pass"
echo ""
echo "Change the port if you want to connect other protocol"
echo ""
echo "TLS / WSS Payload:"
echo "GET wss://[host]/ HTTP/1.1[crlf]Host: $domen[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo ""
echo "Direct / WS Payload:"
echo "GET / HTTP/1.1[crlf]Host: $domen[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo "=========================================="
} | tee -a /etc/log-create-ssh.log

echo ""
read -n 1 -s -r -p "Press any key to return to system menu..."
menu