#!/bin/bash
# ============================================================
# INS-XRAY.SH - Install Xray Core Only
# ============================================================
# Prerequisites:
#   - Domain in /root/domain
#   - Certificate should exist, but a self-signed fallback is
#     created automatically if missing.
#   - Nginx reverse proxy handled by nginx-setup.sh
# ============================================================
# UPDATED: Removed all Nginx config (now in nginx-setup.sh)
#          Xray listens on internal ports only (127.0.0.1)
#          All external traffic via Nginx reverse proxy
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS"
clear
echo ""
date
echo ""
domain=$(cat /root/domain 2>/dev/null || cat /root/domain.txt 2>/dev/null)
domain=$(echo "$domain" | tr -d '[:space:]')

if [[ -z "$domain" ]]; then
    echo -e "\e[1;31mERROR: Domain not found! Please run setup.sh first.\e[0m"
    exit 1
fi
sleep 0.5

green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
NC='\e[0m'

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

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "[ ${green}OK${NC} ] $1"
    else
        echo -e "[ ${red}FAILED${NC} ] $1"
        return 1
    fi
}

detect_os
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

mkdir -p /etc/xray

# ---- Certificate Handling (non‑blocking) ----
if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
    echo -e "[ ${yell}WARNING${NC} ] Xray certificate not found in /etc/xray/"
    if [ -f /usr/local/bin/create-cert.sh ]; then
        echo -e "[ ${green}INFO${NC} ] Running create-cert.sh to obtain certificate..."
        sed -i 's/\r$//' /usr/local/bin/create-cert.sh   # fix line endings
        bash /usr/local/bin/create-cert.sh
    else
        echo -e "[ ${yell}WARNING${NC} ] create-cert.sh not found. Generating self-signed fallback..."
        mkdir -p /etc/ssl/vpn
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/vpn/privkey.pem \
            -out /etc/ssl/vpn/fullchain.pem \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=VPN/CN=$domain" 2>/dev/null
        ln -sf /etc/ssl/vpn/fullchain.pem /etc/xray/xray.crt
        ln -sf /etc/ssl/vpn/privkey.pem /etc/xray/xray.key
        chmod 600 /etc/xray/xray.key
    fi
    # Double-check after attempt
    if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
        echo -e "[ ${red}ERROR${NC} ] Failed to provide a certificate. Xray will start but may not work correctly."
        echo -e "[ ${yell}WARNING${NC} ] Certificate needed for Nginx SSL (run nginx-setup.sh later)"
    fi
fi

echo -e "[ ${green}INFO${NC} ] Installing required packages..."

apt update -y >/dev/null 2>&1

PACKAGES="iptables iptables-persistent net-tools screen curl socat xz-utils wget 
apt-transport-https gnupg gnupg2 dnsutils lsb-release bash-completion cron 
openssl zip pwgen ca-certificates"
for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        apt install -y $pkg >/dev/null 2>&1
    fi
done

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

# ---- Xray core ----
sleep 0.5
echo -e "[ ${green}INFO${NC} ] Downloading & Installing Xray core"

domainSock_dir="/run/xray"
[ ! -d $domainSock_dir ] && mkdir -p $domainSock_dir
chown www-data.www-data $domainSock_dir 2>/dev/null || true

mkdir -p /var/log/xray
mkdir -p /etc/xray
chown www-data.www-data /var/log/xray 2>/dev/null || true
chmod 755 /var/log/xray

touch /var/log/xray/access.log /var/log/xray/error.log /var/log/xray/access2.log /var/log/xray/error2.log 2>/dev/null
chown www-data.www-data /var/log/xray/*.log 2>/dev/null || true

# Install Xray binary
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data
check_success "Xray installation"

# Verify binary exists, if not force reinstall
if [ ! -f /usr/local/bin/xray ]; then
    echo -e "[ ${yell}WARNING${NC} ] Xray binary missing, trying again..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --force
    if [ ! -f /usr/local/bin/xray ]; then
        echo -e "[ ${red}ERROR${NC} ] Xray installation failed. Please install manually."
        exit 1
    fi
fi

# ---- Generate UUID ----
uuid=$(cat /proc/sys/kernel/random/uuid)

# ---- Xray config (ALL internal ports - Nginx proxies from 80/443) ----
echo -e "[ ${green}INFO${NC} ] Creating Xray configuration (internal ports)..."
echo -e "[ ${green}INFO${NC} ] External access via Nginx reverse proxy (nginx-setup.sh)"

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
      "port": 14016,
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
      "port": 23456,
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
      "port": 25432,
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
      "port": 30300,
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
      "port": 24456,
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
      "port": 31234,
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
      "port": 33456,
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
      "port": 30310,
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

# ---- Save UUID for management scripts ----
echo "$uuid" > /etc/xray/uuid
echo -e "[ ${green}INFO${NC} ] UUID saved to /etc/xray/uuid"

# ---- Systemd service for Xray ----
rm -rf /etc/systemd/system/xray.service.d
rm -rf /etc/systemd/system/xray@.service

cat <<EOF> /etc/systemd/system/xray.service
[Unit]
Description=Xray Service (Internal Ports - Nginx Reverse Proxy)
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

# ---- Helper service for /run/xray permissions ----
cat > /etc/systemd/system/runn.service <<EOF
[Unit]
Description=Xray Runtime Directory Setup
After=network.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown www-data:www-data /var/run/xray
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

# ---- Save Xray ports info for nginx-setup.sh ----
cat > /etc/xray/ports.conf <<EOF
# Xray Internal Ports - Used by nginx-setup.sh
XRAY_VLESS_WS=14016
XRAY_VMESS_WS=23456
XRAY_TROJAN_WS=25432
XRAY_SS_WS=30300
XRAY_VLESS_GRPC=24456
XRAY_VMESS_GRPC=31234
XRAY_TROJAN_GRPC=33456
XRAY_SS_GRPC=30310
XRAY_API=10085
EOF
echo -e "[ ${green}INFO${NC} ] Port mapping saved to /etc/xray/ports.conf"

# ---- Note about Nginx ----
echo -e "[ ${yell}NOTE${NC} ] Nginx configuration is now handled by nginx-setup.sh"
echo -e "[ ${yell}NOTE${NC} ] Run nginx-setup.sh after this script to configure reverse proxy"

# ---- Restart services ----
echo -e "[ ${green}INFO${NC} ] Restarting Xray service"
systemctl daemon-reload

systemctl enable xray 2>/dev/null || true
systemctl restart xray
check_success "Xray service restart"

systemctl enable runn 2>/dev/null || true
systemctl restart runn 2>/dev/null || true

# ---- Download management scripts (with CRLF fix) ----
cd /usr/bin/
echo -e "[ ${green}INFO${NC} ] Downloading Xray management scripts..."

# Helper to download, fix line endings and make executable
dl() {
    wget -q -O "$1" "$2" && chmod +x "$1" && sed -i 's/\r$//' "$1"
}

BASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray"

dl add-ws         "$BASE/add-ws.sh"
dl trialvmess     "$BASE/trialvmess.sh"
dl renew-ws       "$BASE/renew-ws.sh"
dl del-ws         "$BASE/del-ws.sh"
dl cek-ws         "$BASE/cek-ws.sh"

dl add-vless      "$BASE/add-vless.sh"
dl trialvless     "$BASE/trialvless.sh"
dl renew-vless    "$BASE/renew-vless.sh"
dl del-vless      "$BASE/del-vless.sh"
dl cek-vless      "$BASE/cek-vless.sh"

dl add-tr         "$BASE/add-tr.sh"
dl trialtrojan    "$BASE/trialtrojan.sh"
dl del-tr         "$BASE/del-tr.sh"
dl renew-tr       "$BASE/renew-tr.sh"
dl cek-tr         "$BASE/cek-tr.sh"

dl add-ssws       "$BASE/add-ssws.sh"
dl trialssws      "$BASE/trialssws.sh"
dl del-ssws       "$BASE/del-ssws.sh"
dl renew-ssws     "$BASE/renew-ssws.sh"
dl cek-ssws       "$BASE/cek-ssws.sh"

# ---- Create xray-info command ----
cat > /usr/local/bin/xray-info <<'XRAYINFO'
#!/bin/bash
# Xray Information Script

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════"
echo "   XRAY SERVICE INFORMATION"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Service status
if systemctl is-active --quiet xray; then
    echo -e "   Status: ${GREEN}● Running${NC}"
else
    echo -e "   Status: ${YELLOW}● Not Running${NC}"
fi

# UUID
if [ -f /etc/xray/uuid ]; then
    echo -e "   UUID: ${CYAN}$(cat /etc/xray/uuid)${NC}"
fi

# Internal ports
echo ""
echo "   Internal Ports (via Nginx reverse proxy):"
echo "   ┌─────────────────────────────────────────────┐"
echo "   │ VLESS WS    : 14016  → /vless               │"
echo "   │ VMess WS    : 23456  → /vmess               │"
echo "   │ Trojan WS   : 25432  → /trojan-ws           │"
echo "   │ SS WS       : 30300  → /ss-ws               │"
echo "   │ VLESS gRPC  : 24456  → /vless-grpc          │"
echo "   │ VMess gRPC  : 31234  → /vmess-grpc          │"
echo "   │ Trojan gRPC : 33456  → /trojan-grpc         │"
echo "   │ SS gRPC     : 30310  → /ss-grpc             │"
echo "   │ API         : 10085  (internal)             │"
echo "   └─────────────────────────────────────────────┘"

echo ""
echo "   Logs:"
echo "   ├── Access: /var/log/xray/access.log"
echo "   ├── Error:  /var/log/xray/error.log"
echo "   └── Journal: journalctl -u xray -f"

echo ""
echo "═══════════════════════════════════════════════════════════════"
XRAYINFO
chmod +x /usr/local/bin/xray-info

# ---- Move domain file ----
mv /root/domain /etc/xray/ 2>/dev/null || true
[ -f /root/scdomain ] && rm /root/scdomain > /dev/null 2>&1

# ---- Final verification ----
sleep 2
echo ""
echo -e "${green}═══════════════════════════════════════════════════════════════${NC}"

if systemctl is-active --quiet xray; then
    echo -e "[ ${green}✓${NC} ] Xray is running on internal ports"
else
    echo -e "[ ${red}✗${NC} ] Xray is not running. Check: journalctl -u xray"
fi

# Check if Nginx is running (informational only)
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "[ ${green}✓${NC} ] Nginx is running (ready for reverse proxy)"
else
    echo -e "[ ${yell}!${NC} ] Nginx not running. Run: nginx-setup.sh"
fi

echo -e "${green}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${green}Xray core installation complete!${NC}"
echo ""
echo -e "${yell}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${yell}║  NEXT STEP: Run nginx-setup.sh to configure reverse proxy  ║${NC}"
echo -e "${yell}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   Commands:"
echo -e "   ├── xray-info       - View Xray configuration"
echo -e "   ├── add-ws          - Add VMess user"
echo -e "   ├── add-vless       - Add VLESS user"
echo -e "   ├── add-tr          - Add Trojan user"
echo -e "   └── add-ssws        - Add Shadowsocks user"
echo ""
echo -e "   Config: /etc/xray/config.json"
echo -e "   UUID:   /etc/xray/uuid"
echo -e "   Ports:  /etc/xray/ports.conf"
echo ""

# Clean up
rm -f ins-xray.sh