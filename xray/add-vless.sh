#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - ADD VLESS WS & GRPC ACCOUNTS
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Resolve Domain Configurations
if [ -f /var/lib/ipvps.conf ]; then
    source /var/lib/ipvps.conf
fi

if [[ "$IP" == "" ]]; then
    domain=$(cat /etc/xray/domain 2>/dev/null || echo "yourdomain.com")
else
    domain=$IP
fi

# Explicit Port Overrides
tls="443"
none="80"

# ============================================================
# INTERACTIVE ACCOUNT REGISTRATION PROMPT
# ============================================================
until [[ $user =~ ^[a-zA-Z0-9_]+$ && ${CLIENT_EXISTS} == '0' ]]; do
    echo "=========================================="
    echo "          CREATE NEW VLESS ACCOUNT        "
    echo "=========================================="
    echo ""
    
    read -rp " Enter Username: " -e user
    user="${user//[[:space:]]/}"
    
    if [[ -z "$user" ]]; then
        clear
        echo -e "\n ${RED}Error:${NC} Username cannot be empty!\n"
        continue
    fi
    
    CLIENT_EXISTS=$(grep -w "$user" /etc/xray/config.json 2>/dev/null | wc -l)

    if [[ ${CLIENT_EXISTS} == '1' ]]; then
        clear
        echo "=========================================="
        echo -e " ${RED}Registration Failed:${NC} User [ ${YELLOW}$user${NC} ] already exists."
        echo "=========================================="
        echo ""
        read -n 1 -s -r -p "Press any key to retry..."
        clear
    fi
done

read -p " Set Account Duration (Days): " masaaktif
if ! [[ "$masaaktif" =~ ^[0-9]+$ ]]; then masaaktif=30; fi

exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
uuid=$(cat /proc/sys/kernel/random/uuid)

# Inject parameters into Xray structures
sed -i '/#vless$/a\#& '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#& '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json

# Proxy Transport Configuration
vlesslink1="vless://${uuid}@${domain}:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@${domain}:${none}?path=%2Fvless&encryption=none&type=ws#${user}"
vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"

# Reload Xray
systemctl restart xray > /dev/null 2>&1
clear

# ============================================================
# ACCOUNT CONFIGURATION CREDENTIALS
# ============================================================
{
echo "=========================================="
echo "          VLESS WEBSOCKET CREDENTIALS     "
echo "=========================================="
echo ""
echo "Remarks / User    : $user"
echo "Server Domain     : $domain"
echo "Port TLS          : $tls"
echo "Port Non-TLS      : $none"
echo "User UUID ID      : $uuid"
echo "Cipher Scheme     : none"
echo "WS Path Node      : /vless"
echo "gRPC Service      : vless-grpc"
echo "Expiration Date   : $exp ($masaaktif Days)"
echo ""
echo "=========================================="
echo "VLESS WS TLS LINK:"
echo "$vlesslink1"
echo ""
echo "=========================================="
echo "VLESS WS NON-TLS LINK:"
echo "$vlesslink2"
echo ""
echo "=========================================="
echo "VLESS gRPC TLS LINK:"
echo "$vlesslink3"
echo "=========================================="
echo ""
} | tee -a /etc/log-create-vless.log

read -n 1 -s -r -p "Press any key to return to dashboard menu..."
menu