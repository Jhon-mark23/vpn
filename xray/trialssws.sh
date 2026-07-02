#!/bin/bash
domain=$(cat /etc/xray/domain)
tls="443"
ntls="80"
user=trial$(tr -dc 'A-Z0-9' </dev/urandom | head -c4)
cipher="aes-128-gcm"
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Add to config.json
sed -i '/#ssws$/a\### '"$user $exp"'\
},{"password": "'""$uuid""'","method": "'""$cipher""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#ssgrpc$/a\### '"$user $exp"'\
},{"password": "'""$uuid""'","method": "'""$cipher""'","email": "'""$user""'"' /etc/xray/config.json

# Build Shadowsocks links (proper base64)
shadowsocks_base64=$(echo -n "${cipher}:${uuid}" | base64 -w 0)
shadowsockslink="ss://${shadowsocks_base64}@${domain}:${tls}?path=%2Fss-ws&security=tls&host=${domain}&type=ws&sni=bug.com.${domain}#${user}"
shadowsockslink1="ss://${shadowsocks_base64}@${domain}:${ntls}?path=%2Fss-ws&security=none&host=${domain}&type=ws#${user}"
shadowsockslink2="ss://${shadowsocks_base64}@${domain}:${tls}?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni=bug.com.${domain}#${user}"

systemctl restart xray > /dev/null 2>&1
service cron restart > /dev/null 2>&1

clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\\E[0;41;36m     Trial Shadowsocks Account     \E[0m"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Remarks        : ${user}"
echo -e "Domain         : ${domain}"
echo -e "SNI / Host     : bug.com.${domain}"
echo -e "Port TLS       : ${tls}"
echo -e "Port none TLS  : ${ntls}"
echo -e "Port gRPC      : ${tls}"
echo -e "Password       : ${uuid}"
echo -e "Cipher         : ${cipher}"
echo -e "Network        : ws / grpc"
echo -e "Path           : /ss-ws"
echo -e "Service Name   : ss-grpc"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link TLS       : ${shadowsockslink}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link none TLS  : ${shadowsockslink1}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link gRPC      : ${shadowsockslink2}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Expired On     : $exp"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo "" | tee -a /etc/log-create-shadowsocks.log
read -n 1 -s -r -p "Press any key to back on menu"
menu