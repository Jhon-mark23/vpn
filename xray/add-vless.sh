#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - ADD VLESS WS & GRPC ACCOUNTS
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS..."
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
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}                  ✨ CREATE NEW VLESS ACCOUNT                 ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -rp " Enter Username: " -e user
    user="${user//[[:space:]]/}" # Trim whitespace characters
    
    if [[ -z "$user" ]]; then
        clear
        echo -e "\n ${red}✗ Error:${NC} Username cannot be completely empty!\n"
        continue
    fi
    
    CLIENT_EXISTS=$(grep -w "$user" /etc/xray/config.json 2>/dev/null | wc -l)

    if [[ ${CLIENT_EXISTS} == '1' ]]; then
        clear
        echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e " ${red}✗ Registration Failure:${NC} User [ ${yellow}$user${NC} ] already exists in system config."
        echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        read -n 1 -s -r -p "Press any key to retry..."
        clear
    fi
done

read -p " Set Account Duration (Days): " masaaktif
# Default fallback to 30 days if input is non-numeric or blank
if ! [[ "$masaaktif" =~ ^[0-9]+$ ]]; then masaaktif=30; fi

exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
uuid=$(cat /proc/sys/kernel/random/uuid)

# Inject parameters cleanly into Xray structures
sed -i '/#vless$/a\#& '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#& '"$user $exp"'\
},{"id": "'""$uuid""'","email": "'""$user""'"' /etc/xray/config.json

# Proxy Transport Configuration Payload Encodings
vlesslink1="vless://${uuid}@${domain}:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@${domain}:${none}?path=%2Fvless&encryption=none&type=ws#${user}"
vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"

# Reload Core Proxy Engine Backend Daemon
systemctl restart xray > /dev/null 2>&1
clear

# ============================================================
# ACCOUNT CONFIGURATION CREDENTIAL RECEIPT PRINT
# ============================================================
{
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}                 🏆 VLESS WEBSOCKET CREDENTIALS                ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Remarks / User" "${user}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Server Domain" "${domain}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Port TLS" "${tls}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Port Non-TLS" "${none}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "User UUID ID" "${uuid}"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Cipher Scheme" "none"
printf "  ${cyan}%-16s${NC} : %-42s\n" "WS Path Node" "/vless"
printf "  ${cyan}%-16s${NC} : %-42s\n" "gRPC Service" "vless-grpc"
printf "  ${cyan}%-16s${NC} : %-42s\n" "Expiration Date" "${exp} (${masaaktif} Days)"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"
echo -e " ${yellow}🔗 VLESS WS TLS LINK:${NC}\n ${white}${vlesslink1}${NC}"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"
echo -e " ${yellow}🔗 VLESS WS NON-TLS LINK:${NC}\n ${white}${vlesslink2}${NC}"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"
echo -e " ${yellow}🔗 VLESS gRPC TLS LINK:${NC}\n ${white}${vlesslink3}${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
} | tee -a /etc/log-create-vless.log

read -n 1 -s -r -p "Press any key to return to dashboard menu..."
menu
