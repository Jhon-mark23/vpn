#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS"
clear

source /var/lib/ipvps.conf
if [[ "$IP" = "" ]]; then
    domain=$(cat /etc/xray/domain)
else
    domain=$IP
fi

# TLS and non-TLS ports are now fixed (Nginx handles both)
tls="443"
ntls="80"

until [[ $user =~ ^[a-zA-Z0-9_]+$ && ${CLIENT_EXISTS} == '0' ]]; do
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m      Add Shadowsocks Account    \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

    read -rp "User: " -e user
    CLIENT_EXISTS=$(grep -w "$user" /etc/xray/config.json | wc -l)

    if [[ ${CLIENT_EXISTS} == '1' ]]; then
        clear
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\\E[0;41;36m      Add Shadowsocks Account      \E[0m"
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        echo "A client with the specified name was already created, please choose another name."
        echo ""
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu
    fi
done

cipher="aes-128-gcm"
uuid=$(cat /proc/sys/kernel/random/uuid)
read -p "Expired (days): " expireddays
exp=$(date -d "$expireddays days" +"%Y-%m-%d")

# Add to config.json
sed -i '/#ssws$/a\### '"$user $exp"'\
},{"password": "'""$uuid""'","method": "'""$cipher""'","email": "'""$user""'"' /etc/xray/config.json
sed -i '/#ssgrpc$/a\### '"$user $exp"'\
},{"password": "'""$uuid""'","method": "'""$cipher""'","email": "'""$user""'"' /etc/xray/config.json

# Build Shadowsocks links
# Format: ss://base64(method:password)@server:port?params#name
shadowsocks_base64=$(echo -n "${cipher}:${uuid}" | base64 -w 0)
shadowsockslink="ss://${shadowsocks_base64}@${domain}:${tls}?path=%2Fss-ws&security=tls&host=${domain}&type=ws&sni=bug.com.${domain}#${user}"
shadowsockslink1="ss://${shadowsocks_base64}@${domain}:${ntls}?path=%2Fss-ws&security=none&host=${domain}&type=ws#${user}"
shadowsockslink2="ss://${shadowsocks_base64}@${domain}:${tls}?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni=bug.com.${domain}#${user}"

systemctl restart xray > /dev/null 2>&1
service cron restart > /dev/null 2>&1

clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "\\E[0;41;36m        Shadowsocks Account      \E[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "Remarks        : ${user}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Domain         : ${domain}" | tee -a /etc/log-create-shadowsocks.log
echo -e "SNI / Host     : bug.com.${domain}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Port TLS       : ${tls}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Port none TLS  : ${ntls}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Port gRPC      : ${tls}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Password       : ${uuid}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Cipher         : ${cipher}" | tee -a /etc/log-create-shadowsocks.log
echo -e "Network        : ws / grpc" | tee -a /etc/log-create-shadowsocks.log
echo -e "Path           : /ss-ws" | tee -a /etc/log-create-shadowsocks.log
echo -e "Service Name   : ss-grpc" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "Link TLS       : ${shadowsockslink}" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "Link none TLS  : ${shadowsockslink1}" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "Link gRPC      : ${shadowsockslink2}" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo -e "Expired On     : $exp" | tee -a /etc/log-create-shadowsocks.log
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m" | tee -a /etc/log-create-shadowsocks.log
echo "" | tee -a /etc/log-create-shadowsocks.log
read -n 1 -s -r -p "Press any key to back on menu"
menu