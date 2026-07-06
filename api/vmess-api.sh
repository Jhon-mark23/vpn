#!/bin/bash
# VMESS User Creator - JSON Output

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
sed -i '/#vmess$/a\### '"$USER $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$USER""'"' /etc/xray/config.json
sed -i '/#vmessgrpc$/a\### '"$USER $exp"'\
},{"id": "'""$uuid""'","alterId": '"0"',"email": "'""$USER""'"' /etc/xray/config.json

systemctl restart xray > /dev/null 2>&1

# Build VMess links
vmess_tls_json=$(cat <<EOF
{
    "v": "2",
    "ps": "${USER}",
    "add": "${domain}",
    "port": "443",
    "id": "${uuid}",
    "aid": "0",
    "net": "ws",
    "path": "/vmess",
    "type": "none",
    "host": "bug.com.${domain}",
    "tls": "tls"
}
EOF
)

vmess_none_json=$(cat <<EOF
{
    "v": "2",
    "ps": "${USER}",
    "add": "${domain}",
    "port": "80",
    "id": "${uuid}",
    "aid": "0",
    "net": "ws",
    "path": "/vmess",
    "type": "none",
    "host": "bug.com.${domain}",
    "tls": "none"
}
EOF
)

vmess_grpc_json=$(cat <<EOF
{
    "v": "2",
    "ps": "${USER}",
    "add": "${domain}",
    "port": "443",
    "id": "${uuid}",
    "aid": "0",
    "net": "grpc",
    "path": "vmess-grpc",
    "type": "none",
    "host": "bug.com.${domain}",
    "tls": "tls"
}
EOF
)

vmesslink1="vmess://$(echo "$vmess_tls_json" | base64 -w 0)"
vmesslink2="vmess://$(echo "$vmess_none_json" | base64 -w 0)"
vmesslink3="vmess://$(echo "$vmess_grpc_json" | base64 -w 0)"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Created VMESS: $USER (expires: $exp)" >> /etc/log-create-vmess.log

cat <<EOF
{
    "success": true,
    "type": "vmess",
    "username": "$USER",
    "uuid": "$uuid",
    "alter_id": 0,
    "expired": "$exp",
    "duration": $MASA_AKTIF,
    "domain": "$domain",
    "sni_host": "bug.com.${domain}",
    "ports": {
        "tls": "$tls",
        "non_tls": "$none"
    },
    "paths": {
        "ws": "/vmess",
        "grpc": "vmess-grpc"
    },
    "links": {
        "vmess_tls": "$vmesslink1",
        "vmess_non_tls": "$vmesslink2",
        "vmess_grpc": "$vmesslink3"
    }
}
EOF