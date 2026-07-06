#!/bin/bash
# VLESS User Creator - JSON Output

USER="$1"
MASA_AKTIF="$2"
[ -z "$MASA_AKTIF" ] && MASA_AKTIF=30

# Get domain
domain=$(cat /etc/xray/domain 2>/dev/null || echo "yourdomain.com")
tls="443"
none="80"

# Check if user exists
if grep -qw "$USER" /etc/xray/config.json 2>/dev/null; then
    echo '{"success": false, "error": "User already exists"}'
    exit 1
fi

uuid=$(cat /proc/sys/kernel/random/uuid)
exp=$(date -d "$MASA_AKTIF days" +"%Y-%m-%d")

# Add to config
sed -i '/#vless$/a\#& '"$USER $exp"'\
},{"id": "'""$uuid""'","email": "'""$USER""'"' /etc/xray/config.json
sed -i '/#vlessgrpc$/a\#& '"$USER $exp"'\
},{"id": "'""$uuid""'","email": "'""$USER""'"' /etc/xray/config.json

systemctl restart xray > /dev/null 2>&1

# Generate links
vlesslink1="vless://${uuid}@${domain}:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${USER}"
vlesslink2="vless://${uuid}@${domain}:${none}?path=%2Fvless&encryption=none&type=ws#${USER}"
vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${USER}"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Created VLESS: $USER (expires: $exp)" >> /etc/log-create-vless.log

cat <<EOF
{
    "success": true,
    "type": "vless",
    "username": "$USER",
    "uuid": "$uuid",
    "expired": "$exp",
    "duration": $MASA_AKTIF,
    "domain": "$domain",
    "ports": {
        "tls": "$tls",
        "non_tls": "$none"
    },
    "paths": {
        "ws": "/vless",
        "grpc": "vless-grpc"
    },
    "links": {
        "vless_tls": "$vlesslink1",
        "vless_non_tls": "$vlesslink2",
        "vless_grpc": "$vlesslink3"
    }
}
EOF