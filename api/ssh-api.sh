#!/bin/bash
# SSH User Creator - JSON Output

LOGIN="$1"
PASS="$2"
MASA_AKTIF="$3"
[ -z "$MASA_AKTIF" ] && MASA_AKTIF=30

# Get domain
domen=""
for path in "/root/domain.txt" "/etc/xray/domain" "/etc/v2ray/domain" "/root/domain"; do
    if [ -s "$path" ]; then
        domen=$(cat "$path" | tr -d '[:space:]')
        break
    fi
done
[ -z "$domen" ] && domen=$(wget -qO- ipv4.icanhazip.com)

IP=$(wget -qO- ipv4.icanhazip.com || curl -sS ifconfig.me)
opensh="22"
portsshws="8080"
wsssl="8445"
ssl="8443"
PUBKEY=$(cat "/etc/dnstt/private.pub" 2>/dev/null || echo "N/A")
nsdomain="ns.${domen}"

if id "$LOGIN" &>/dev/null; then
    echo '{"success": false, "error": "User already exists"}'
    exit 1
fi

useradd -e "$(date -d "$MASA_AKTIF days" +"%Y-%m-%d")" -s /bin/false -M "$LOGIN" 2>/dev/null
echo -e "$PASS\n$PASS" | passwd "$LOGIN" &> /dev/null

if id "$LOGIN" &>/dev/null; then
    exp="$(chage -l "$LOGIN" | grep "Account expires" | awk -F": " '{print $2}')"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Created SSH: $LOGIN (expires: $exp)" >> /etc/log-create-ssh.log
    
    cat <<EOF
{
    "success": true,
    "type": "ssh",
    "username": "$LOGIN",
    "password": "$PASS",
    "expired": "$exp",
    "duration": $MASA_AKTIF,
    "ip": "$IP",
    "domain": "$domen",
    "ns": "$nsdomain",
    "pubkey": "$PUBKEY",
    "ports": {
        "openssh": "$opensh",
        "ssh_ws": "$portsshws",
        "ssh_ssl_ws": "$wsssl",
        "ssl_tls": "$ssl",
        "dnstt": "22",
        "udpgw": "7100-7400"
    },
    "http_custom": "${IP}:22@${LOGIN}:${PASS}",
    "payloads": {
        "tls_wss": "GET wss://[host]/ HTTP/1.1[crlf]Host: ${domen}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]",
        "direct_ws": "GET / HTTP/1.1[crlf]Host: ${domen}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    }
}
EOF
else
    echo '{"success": false, "error": "Failed to create user"}'
    exit 1
fi