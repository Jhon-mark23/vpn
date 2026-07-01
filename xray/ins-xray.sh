#!/bin/bash
# ============================================================
# ENHANCED XRAY INSTALLATION SCRIPT
# NO CERTIFICATE CONFLICT WITH STUNNEL4
# 
# Features:
#   - Shares certificate with Stunnel4
#   - No acme.sh rate limit issues
#   - One certificate for all services
#   - Improved error handling
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS"
clear
echo ""
date
echo ""
domain=$(cat /root/domain 2>/dev/null)
if [ -z "$domain" ]; then
    echo -e "\e[1;31mERROR: Domain not found! Please run setup.sh first.\e[0m"
    exit 1
fi
sleep 0.5

# Colors
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
NC='\e[0m'

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo "Cannot detect OS. Exiting..."
        exit 1
    fi
    
    echo -e "[ ${green}INFO${NC} ] Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo -e "[ ${red}ERROR${NC} ] This script only supports Ubuntu or Debian"
        exit 1
    fi
}

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "[ ${green}OK${NC} ] $1"
    else
        echo -e "[ ${red}FAILED${NC} ] $1"
        return 1
    fi
}

detect_os

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

mkdir -p /etc/xray
echo -e "[ ${green}INFO${NC} ] Installing required packages..."

# Install packages with better handling
apt update -y >/dev/null 2>&1

# Core packages
PACKAGES="iptables iptables-persistent net-tools screen curl socat xz-utils wget 
apt-transport-https gnupg gnupg2 dnsutils lsb-release bash-completion cron 
openssl zip pwgen ca-certificates"

# Install core packages
for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        apt install -y $pkg >/dev/null 2>&1
    fi
done

# Handle netcat package based on OS
if [[ "$OS" == "ubuntu" ]]; then
    apt install -y netcat-openbsd >/dev/null 2>&1
elif [[ "$OS" == "debian" ]]; then
    apt install -y netcat-traditional >/dev/null 2>&1 || apt install -y netcat >/dev/null 2>&1 || true
    apt install -y software-properties-common >/dev/null 2>&1
fi

check_success "Package installation"

sleep 0.5
echo -e "[ ${green}INFO${NC} ] Setting timezone"
timedatectl set-timezone Asia/Manila 2>/dev/null || true
timedatectl set-ntp true 2>/dev/null || true

# Install xray core
sleep 0.5
echo -e "[ ${green}INFO${NC} ] Downloading & Installing Xray core"

domainSock_dir="/run/xray"
[ ! -d $domainSock_dir ] && mkdir -p $domainSock_dir
chown www-data.www-data $domainSock_dir 2>/dev/null || true

mkdir -p /var/log/xray
mkdir -p /etc/xray
chown www-data.www-data /var/log/xray 2>/dev/null || true
chmod 755 /var/log/xray

# Create log files
touch /var/log/xray/access.log 2>/dev/null
touch /var/log/xray/error.log 2>/dev/null
touch /var/log/xray/access2.log 2>/dev/null
touch /var/log/xray/error2.log 2>/dev/null
chown www-data.www-data /var/log/xray/*.log 2>/dev/null || true

# Install Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data
check_success "Xray installation"

# ============================================================
# SSL CERTIFICATE - SHARED WITH STUNNEL4 (NO CONFLICT)
# ============================================================
echo -e "[ ${green}INFO${NC} ] Setting up SSL certificate (shared with Stunnel4)..."

systemctl stop nginx 2>/dev/null || true

# ============================================================
# OPTION 1: Use Existing Stunnel4 Certificate
# ============================================================
if [ -f /etc/stunnel/stunnel.pem ]; then
    echo -e "[ ${green}INFO${NC} ] Using existing Stunnel4 certificate..."
    
    # Extract certificate and key from Stunnel PEM
    openssl x509 -in /etc/stunnel/stunnel.pem -out /etc/xray/xray.crt 2>/dev/null
    openssl rsa -in /etc/stunnel/stunnel.pem -out /etc/xray/xray.key 2>/dev/null
    
    if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
        check_success "Certificate copied from Stunnel4"
    else
        echo -e "[ ${yell}WARNING${NC} ] Failed to extract certificate, generating new one..."
        CERT_ISSUED=false
    fi
else
    CERT_ISSUED=false
fi

# ============================================================
# OPTION 2: Generate New Shared Certificate
# ============================================================
if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
    echo -e "[ ${green}INFO${NC} ] Generating new certificate (will be shared with Stunnel4)..."
    
    # Generate certificate with SAN (Subject Alternative Name)
    cat > /tmp/openssl.cnf <<'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = PH
ST = Metro Manila
L = Manila
O = VPN
CN = DOMAIN_PLACEHOLDER

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = DOMAIN_PLACEHOLDER
DNS.2 = *.DOMAIN_PLACEHOLDER
EOF

    # Replace domain placeholder
    sed -i "s/DOMAIN_PLACEHOLDER/$domain/g" /tmp/openssl.cnf
    
    # Generate certificate with SAN
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -config /tmp/openssl.cnf \
        -extensions v3_req 2>/dev/null
    
    rm -f /tmp/openssl.cnf
    
    # If SAN fails, fallback to simple
    if [ ! -f /etc/xray/xray.crt ]; then
        echo -e "[ ${yell}WARNING${NC} ] SAN generation failed, using simple certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/xray/xray.key -out /etc/xray/xray.crt \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=VPN/CN=$domain" 2>/dev/null
    fi
    
    # Copy to Stunnel4 so they share the same certificate
    if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
        echo -e "[ ${green}INFO${NC} ] Sharing certificate with Stunnel4..."
        cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem
        chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
        
        # Restart Stunnel4 to use new certificate
        systemctl restart stunnel4 2>/dev/null || true
        
        check_success "Certificate generated and shared with Stunnel4"
    fi
fi

# Set proper permissions
chmod 600 /etc/xray/xray.crt /etc/xray/xray.key 2>/dev/null || true
chown www-data:www-data /etc/xray/xray.crt /etc/xray/xray.key 2>/dev/null || true

# Verify certificate exists
if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
    echo -e "[ ${red}ERROR${NC} ] Certificate generation failed!"
    echo -e "[ ${red}ERROR${NC} ] Please check: /etc/xray/xray.crt and /etc/xray/xray.key"
    exit 1
fi

check_success "Certificate setup complete"

# ============================================================
# Generate UUID
# ============================================================
uuid=$(cat /proc/sys/kernel/random/uuid)

# Xray config
cat > /etc/xray/config.json << END
{
  "log" : {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
      {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
   {
     "listen": "127.0.0.1",
     "port": "14016",
     "protocol": "vless",
      "settings": {
          "decryption":"none",
            "clients": [
               {
                 "id": "${uuid}"
#vless
             }
          ]
       },
       "streamSettings":{
         "network": "ws",
            "wsSettings": {
                "path": "/vless"
          }
        }
     },
     {
     "listen": "127.0.0.1",
     "port": "23456",
     "protocol": "vmess",
      "settings": {
            "clients": [
               {
                 "id": "${uuid}",
                 "alterId": 0
#vmess
             }
          ]
       },
       "streamSettings":{
         "network": "ws",
            "wsSettings": {
                "path": "/vmess"
          }
        }
     },
    {
      "listen": "127.0.0.1",
      "port": "25432",
      "protocol": "trojan",
      "settings": {
          "decryption":"none",
           "clients": [
              {
                 "password": "${uuid}"
#trojanws
              }
          ],
         "udp": true
       },
       "streamSettings":{
           "network": "ws",
           "wsSettings": {
               "path": "/trojan-ws"
            }
         }
     },
    {
         "listen": "127.0.0.1",
        "port": "30300",
        "protocol": "shadowsocks",
        "settings": {
           "clients": [
           {
           "method": "aes-128-gcm",
          "password": "${uuid}"
#ssws
           }
          ],
          "network": "tcp,udp"
       },
       "streamSettings":{
          "network": "ws",
             "wsSettings": {
               "path": "/ss-ws"
           }
        }
     },
      {
        "listen": "127.0.0.1",
     "port": "24456",
        "protocol": "vless",
        "settings": {
         "decryption":"none",
           "clients": [
             {
               "id": "${uuid}"
#vlessgrpc
             }
          ]
       },
          "streamSettings":{
             "network": "grpc",
             "grpcSettings": {
                "serviceName": "vless-grpc"
           }
        }
     },
     {
      "listen": "127.0.0.1",
     "port": "31234",
     "protocol": "vmess",
      "settings": {
            "clients": [
               {
                 "id": "${uuid}",
                 "alterId": 0
#vmessgrpc
             }
          ]
       },
       "streamSettings":{
         "network": "grpc",
            "grpcSettings": {
                "serviceName": "vmess-grpc"
          }
        }
     },
     {
        "listen": "127.0.0.1",
     "port": "33456",
        "protocol": "trojan",
        "settings": {
          "decryption":"none",
             "clients": [
               {
                 "password": "${uuid}"
#trojangrpc
               }
           ]
        },
         "streamSettings":{
         "network": "grpc",
           "grpcSettings": {
               "serviceName": "trojan-grpc"
         }
      }
   },
   {
    "listen": "127.0.0.1",
    "port": "30310",
    "protocol": "shadowsocks",
    "settings": {
        "clients": [
          {
             "method": "aes-128-gcm",
             "password": "${uuid}"
#ssgrpc
           }
         ],
           "network": "tcp,udp"
      },
    "streamSettings":{
     "network": "grpc",
        "grpcSettings": {
           "serviceName": "ss-grpc"
          }
       }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ]
      }
    ]
  },
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink" : true,
      "statsOutboundDownlink" : true
    }
  }
}
END

rm -rf /etc/systemd/system/xray.service.d
rm -rf /etc/systemd/system/xray@.service

cat <<EOF> /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=500
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/runn.service <<EOF
[Unit]
Description=Mantap-Sayang
After=network.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown www-data:www-data /var/run/xray
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

# ============================================================
# ENHANCED NGINX CONFIG - Fixed http2 deprecation
# ============================================================
echo -e "[ ${green}INFO${NC} ] Creating nginx configuration with fixed http2..."

cat > /etc/nginx/conf.d/xray.conf <<'EOF'
# Nginx port 81 - internal web page
server {
    listen 81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
}

# Port 80 - SSH WS (HTTP/None TLS) + Xray None TLS
server {
    listen 80;
    listen [::]:80;
    server_name *.$domain;
    root /home/vps/public_html;

    # Xray Vmess None TLS
    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Vless None TLS
    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Trojan None TLS
    location = /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Shadowsocks None TLS
    location = /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # SSH Websocket HTTP
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
}

# Port 443 - TLS (Xray + SSH WSS)
server {
    listen 443 ssl reuseport;
    listen [::]:443 ssl reuseport;
    http2 on;
    server_name *.$domain;
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    root /home/vps/public_html;

    # Xray Vmess TLS
    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Vless TLS
    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Trojan TLS
    location = /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray Shadowsocks TLS
    location = /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # Xray gRPC
    location ^~ /vless-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
        grpc_pass grpc://127.0.0.1:24456;
    }

    location ^~ /vmess-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
        grpc_pass grpc://127.0.0.1:31234;
    }

    location ^~ /trojan-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
        grpc_pass grpc://127.0.0.1:33456;
    }

    location ^~ /ss-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
        grpc_pass grpc://127.0.0.1:30310;
    }

    # SSH WSS (HTTPS)
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
}
EOF

# Fix the domain variable in nginx config
sed -i "s/\\\$domain/$domain/g" /etc/nginx/conf.d/xray.conf

echo -e "[ ${green}INFO${NC} ] Restarting all services"
systemctl daemon-reload

# Enable & restart Xray
echo -e "[ ${green}INFO${NC} ] Enabling and restarting Xray..."
systemctl enable xray 2>/dev/null || true
systemctl restart xray
check_success "Xray service restart"

# Restart Nginx
echo -e "[ ${green}INFO${NC} ] Testing and restarting Nginx..."
nginx -t 2>/dev/null
if [ $? -eq 0 ]; then
    systemctl restart nginx
    check_success "Nginx restart"
else
    echo -e "[ ${red}ERROR${NC} ] Nginx configuration test failed!"
    echo -e "[ ${yell}WARNING${NC} ] Please check: nginx -t"
fi

systemctl enable runn 2>/dev/null || true
systemctl restart runn 2>/dev/null || true

# Download management scripts
cd /usr/bin/

echo -e "[ ${green}INFO${NC} ] Downloading management scripts..."

# Vmess
wget -q -O add-ws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/add-ws.sh" && chmod +x add-ws
wget -q -O trialvmess "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/trialvmess.sh" && chmod +x trialvmess
wget -q -O renew-ws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/renew-ws.sh" && chmod +x renew-ws
wget -q -O del-ws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/del-ws.sh" && chmod +x del-ws
wget -q -O cek-ws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/cek-ws.sh" && chmod +x cek-ws

# Vless
wget -q -O add-vless "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/add-vless.sh" && chmod +x add-vless
wget -q -O trialvless "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/trialvless.sh" && chmod +x trialvless
wget -q -O renew-vless "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/renew-vless.sh" && chmod +x renew-vless
wget -q -O del-vless "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/del-vless.sh" && chmod +x del-vless
wget -q -O cek-vless "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/cek-vless.sh" && chmod +x cek-vless

# Trojan
wget -q -O add-tr "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/add-tr.sh" && chmod +x add-tr
wget -q -O trialtrojan "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/trialtrojan.sh" && chmod +x trialtrojan
wget -q -O del-tr "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/del-tr.sh" && chmod +x del-tr
wget -q -O renew-tr "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/renew-tr.sh" && chmod +x renew-tr
wget -q -O cek-tr "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/cek-tr.sh" && chmod +x cek-tr

# Shadowsocks
wget -q -O add-ssws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/add-ssws.sh" && chmod +x add-ssws
wget -q -O trialssws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/trialssws.sh" && chmod +x trialssws
wget -q -O del-ssws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/del-ssws.sh" && chmod +x del-ssws
wget -q -O renew-ssws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/renew-ssws.sh" && chmod +x renew-ssws
wget -q -O cek-ssws "https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray/cek-ssws.sh" && chmod +x cek-ssws

# Clean up
sleep 0.5
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
yellow "Xray installation complete!"
yellow "VMess, VLess, Trojan, and Shadowsocks are ready"

# Move domain file
mv /root/domain /etc/xray/ 2>/dev/null || true
if [ -f /root/scdomain ]; then
    rm /root/scdomain > /dev/null 2>&1
fi

# Final verification
echo -e "\n[ ${green}INFO${NC} ] Verifying services..."
sleep 2

# Check Xray
if systemctl is-active --quiet xray; then
    echo -e "[ ${green}✓${NC} ] Xray is running"
else
    echo -e "[ ${red}✗${NC} ] Xray is not running. Check: journalctl -u xray"
fi

# Check Nginx
if systemctl is-active --quiet nginx; then
    echo -e "[ ${green}✓${NC} ] Nginx is running"
else
    echo -e "[ ${red}✗${NC} ] Nginx is not running. Check: journalctl -u nginx"
fi

# Check Stunnel4 (ensure it's still running after cert change)
if systemctl is-active --quiet stunnel4; then
    echo -e "[ ${green}✓${NC} ] Stunnel4 is running (shared certificate)"
else
    echo -e "[ ${red}✗${NC} ] Stunnel4 is not running. Check: journalctl -u stunnel4"
    systemctl restart stunnel4 2>/dev/null || true
fi

clear
rm -f ins-xray.sh