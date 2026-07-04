#!/bin/bash
# ============================================================
# INS-XRAY.SH v2.0 - Install Xray (Universal)
# Compatible with Ubuntu & Debian (including Debian 13)
# ============================================================
# Prerequisites:
#   - Domain in /root/domain or /root/domain.txt
#   - Certificate should exist (auto-created if missing)
#   - Nginx installed (for reverse proxy)
# ============================================================

set -euo pipefail

# ============================================================
# COLOURS
# ============================================================
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
blue='\e[0;34m'
cyan='\e[0;36m'
NC='\e[0m'

# ============================================================
# LOGGING FUNCTIONS
# ============================================================
print_info()    { echo -e "[ ${green}INFO${NC} ] $1"; }
print_warn()    { echo -e "[ ${yell}WARN${NC} ] $1"; }
print_error()   { echo -e "[ ${red}ERROR${NC} ] $1" >&2; }
print_success() { echo -e "[ ${green}✓${NC} ] $1"; }
print_step()    { echo -e "[ ${cyan}STEP${NC} ] $1"; }
print_fatal()   { echo -e "[ ${red}FATAL${NC} ] $1" >&2; exit 1; }

# ============================================================
# ERROR HANDLING
# ============================================================
trap 'print_error "Script interrupted at line $LINENO"' INT TERM
trap 'print_error "Error occurred at line $LINENO. Exit code: $?"' ERR

# ============================================================
# DETECT OS
# ============================================================
detect_os() {
    print_step "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_fatal "Cannot detect OS"
    fi
    
    print_info "Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_fatal "This script only supports Ubuntu or Debian"
    fi
    
    # Check if Debian 13 (Trixie) or later
    if [[ "$OS" == "debian" ]] && [[ "$VER" == "13" || "$VER" == "trixie" || "$VER" -ge 13 ]]; then
        IS_DEBIAN_13=true
        print_info "Debian 13+ detected - using compatibility mode"
    else
        IS_DEBIAN_13=false
    fi
}

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_fatal "Please run as root"
fi

# ============================================================
# GET DOMAIN
# ============================================================
get_domain() {
    print_step "Getting domain..."
    
    # Try multiple sources for domain
    DOMAIN=$(cat /root/domain 2>/dev/null || \
             cat /root/domain.txt 2>/dev/null || \
             cat /etc/xray/domain 2>/dev/null || \
             cat /etc/v2ray/domain 2>/dev/null || \
             echo "")
    
    DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')
    
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain not found in common locations!"
        print_info "Please run setup.sh first or provide domain manually."
        
        read -rp "Enter your domain: " DOMAIN
        DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')
        
        if [[ -z "$DOMAIN" ]]; then
            print_fatal "Domain cannot be empty"
        fi
        
        # Save domain
        echo "$DOMAIN" > /root/domain
        echo "$DOMAIN" > /root/domain.txt
    fi
    
    print_info "Domain: $DOMAIN"
    export DOMAIN
}

# ============================================================
# INSTALL PACKAGES
# ============================================================
install_packages() {
    print_step "Installing required packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    
    # Update package list with retry
    local retry=0
    while [ $retry -lt 3 ]; do
        if apt update -y 2>/dev/null; then
            break
        fi
        retry=$((retry + 1))
        print_warn "Failed to update package list, retry $retry/3"
        sleep 3
    done
    
    local packages=(
        "iptables" "iptables-persistent" "net-tools" "screen"
        "curl" "socat" "xz-utils" "wget" "apt-transport-https"
        "gnupg" "gnupg2" "dnsutils" "lsb-release" "bash-completion"
        "cron" "openssl" "zip" "pwgen" "ca-certificates" "jq"
    )
    
    # OS-specific packages
    if [[ "$OS" == "ubuntu" ]]; then
        packages+=("netcat-openbsd")
    elif [[ "$OS" == "debian" ]]; then
        packages+=("netcat-traditional" "software-properties-common")
        # For Debian 13, use different package names if needed
        if [[ "$IS_DEBIAN_13" == true ]]; then
            packages+=("python3-full" "python3-pip")
        fi
    fi
    
    # Install packages one by one with retry
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            continue
        fi
        
        retry=0
        while [ $retry -lt 3 ]; do
            if apt install -y "$pkg" 2>/dev/null; then
                print_info "Installed: $pkg"
                break
            fi
            retry=$((retry + 1))
            print_warn "Failed to install $pkg, retry $retry/3"
            sleep 2
        done
        
        if [ $retry -eq 3 ]; then
            print_warn "Failed to install $pkg, continuing..."
        fi
    done
    
    print_success "Package installation completed"
}

# ============================================================
# SETUP CERTIFICATE
# ============================================================
setup_certificate() {
    print_step "Setting up certificate..."
    
    mkdir -p /etc/xray /etc/ssl/vpn
    
    if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
        print_info "Certificate already exists in /etc/xray/"
        return 0
    fi
    
    print_warn "Xray certificate not found in /etc/xray/"
    
    # Try create-cert.sh if available
    if [ -f /usr/local/bin/create-cert.sh ]; then
        print_info "Running create-cert.sh to obtain certificate..."
        if bash /usr/local/bin/create-cert.sh 2>/dev/null; then
            if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
                print_success "Certificate obtained via create-cert.sh"
                return 0
            fi
        fi
        print_warn "create-cert.sh failed or didn't create certificate"
    fi
    
    # Generate self-signed fallback
    print_info "Generating self-signed fallback certificate..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/vpn/privkey.pem \
        -out /etc/ssl/vpn/fullchain.pem \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=VPN/CN=$DOMAIN" 2>/dev/null
    
    if [ -f /etc/ssl/vpn/fullchain.pem ] && [ -f /etc/ssl/vpn/privkey.pem ]; then
        ln -sf /etc/ssl/vpn/fullchain.pem /etc/xray/xray.crt
        ln -sf /etc/ssl/vpn/privkey.pem /etc/xray/xray.key
        chmod 600 /etc/xray/xray.key
        print_success "Self-signed certificate created"
    else
        print_error "Failed to create self-signed certificate!"
        return 1
    fi
}

# ============================================================
# INSTALL XRAY
# ============================================================
install_xray() {
    print_step "Installing Xray core..."
    
    # Create directories
    mkdir -p /var/log/xray /etc/xray /run/xray
    chown www-data:www-data /var/log/xray 2>/dev/null || true
    chown www-data:www-data /run/xray 2>/dev/null || true
    chmod 755 /var/log/xray /run/xray
    
    # Touch log files
    touch /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null
    chown www-data:www-data /var/log/xray/*.log 2>/dev/null || true
    
    # Install Xray
    print_info "Downloading and installing Xray..."
    
    local retry=0
    while [ $retry -lt 3 ]; do
        if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data 2>/dev/null; then
            break
        fi
        retry=$((retry + 1))
        print_warn "Xray installation failed, retry $retry/3"
        sleep 3
    done
    
    if [ $retry -eq 3 ]; then
        print_warn "Xray installation had issues, trying force reinstall..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --force 2>/dev/null || {
            print_error "Xray installation failed!"
            return 1
        }
    fi
    
    # Verify binary
    if [ ! -f /usr/local/bin/xray ]; then
        print_error "Xray binary not found!"
        return 1
    fi
    
    # Check version
    local xray_version=$(/usr/local/bin/xray version 2>/dev/null | head -n1 || echo "Unknown")
    print_success "Xray installed: $xray_version"
    
    # Generate UUID
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "d5b8b8e3-8b8e-4b8e-8b8e-8b8e8b8e8b8e")
    print_info "UUID: $UUID"
}

# ============================================================
# CONFIGURE XRAY
# ============================================================
configure_xray() {
    print_step "Configuring Xray..."
    
    cat > /etc/xray/config.json << END
{
  "log": {
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
        "decryption": "none",
        "clients": [
          {
            "id": "${UUID}"
          }
        ]
      },
      "streamSettings": {
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
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
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
        "decryption": "none",
        "clients": [
          {
            "password": "${UUID}"
          }
        ],
        "udp": true
      },
      "streamSettings": {
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
            "password": "${UUID}"
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
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
        "decryption": "none",
        "clients": [
          {
            "id": "${UUID}"
          }
        ]
      },
      "streamSettings": {
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
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
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
        "decryption": "none",
        "clients": [
          {
            "password": "${UUID}"
          }
        ]
      },
      "streamSettings": {
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
            "password": "${UUID}"
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
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
          "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10",
          "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24",
          "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15",
          "198.51.100.0/24", "203.0.113.0/24",
          "::1/128", "fc00::/7", "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": ["bittorrent"]
      }
    ]
  },
  "stats": {},
  "api": {
    "services": ["StatsService"],
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
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  }
}
END

    # Create systemd service
    cat > /etc/systemd/system/xray.service <<'EOF'
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

    chmod 644 /etc/systemd/system/xray.service
    
    print_success "Xray configuration created"
}

# ============================================================
# CONFIGURE NGINX
# ============================================================
configure_nginx() {
    print_step "Configuring Nginx..."
    
    # Ensure nginx is installed
    if ! command -v nginx &>/dev/null; then
        print_warn "Nginx not found, installing..."
        apt install -y nginx 2>/dev/null || {
            print_error "Failed to install nginx"
            return 1
        }
    fi
    
    # Create web root
    mkdir -p /home/vps/public_html
    echo "<h1>VPN Server</h1>" > /home/vps/public_html/index.html
    chown -R www-data:www-data /home/vps/public_html
    
    # Create nginx config
    cat > /etc/nginx/conf.d/xray.conf <<'EOF'
server {
    listen 81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
}

server {
    listen 80;
    listen [::]:80;
    server_name *.$DOMAIN;
    root /home/vps/public_html;

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

server {
    listen 443 ssl reuseport;
    listen [::]:443 ssl reuseport;
    http2 on;
    server_name *.$DOMAIN;
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers DEFAULT:!aNULL:!eNULL:!LOW:!MD5:!EXP:!RC4;
    root /home/vps/public_html;

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

    # Replace domain placeholder
    sed -i "s/\\\$DOMAIN/$DOMAIN/g" /etc/nginx/conf.d/xray.conf
    
    # Test nginx config
    if nginx -t 2>/dev/null; then
        print_success "Nginx configuration valid"
    else
        print_error "Nginx configuration test failed!"
        nginx -t 2>&1
        return 1
    fi
    
    # Restart nginx
    systemctl restart nginx 2>/dev/null || {
        print_warn "Failed to restart nginx"
        return 1
    }
    
    print_success "Nginx configured"
}

# ============================================================
# DOWNLOAD MANAGEMENT SCRIPTS
# ============================================================
download_scripts() {
    print_step "Downloading management scripts..."
    
    cd /usr/bin/ || {
        print_error "Cannot change to /usr/bin/"
        return 1
    }
    
    local BASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/xray"
    
    # Helper function to download with retry
    dl() {
        local name=$1
        local url="$BASE/$name.sh"
        local target="/usr/bin/$name"
        
        local retry=0
        while [ $retry -lt 3 ]; do
            if wget -q -O "$target" "$url" 2>/dev/null; then
                chmod +x "$target"
                sed -i 's/\r$//' "$target"
                return 0
            fi
            retry=$((retry + 1))
            sleep 2
        done
        print_warn "Failed to download $name"
        return 1
    }
    
    local scripts=(
        "add-ws" "trialvmess" "renew-ws" "del-ws" "cek-ws"
        "add-vless" "trialvless" "renew-vless" "del-vless" "cek-vless"
        "add-tr" "trialtrojan" "del-tr" "renew-tr" "cek-tr"
        "add-ssws" "trialssws" "del-ssws" "renew-ssws" "cek-ssws"
    )
    
    for script in "${scripts[@]}"; do
        dl "$script" &
    done
    
    wait
    
    print_success "Management scripts downloaded"
}

# ============================================================
# START SERVICES
# ============================================================
start_services() {
    print_step "Starting services..."
    
    systemctl daemon-reload
    
    # Start Xray
    systemctl enable xray 2>/dev/null || true
    if systemctl restart xray 2>/dev/null; then
        print_success "Xray started successfully"
    else
        print_error "Failed to start Xray"
        journalctl -u xray --no-pager -n 20 2>/dev/null || true
        return 1
    fi
    
    # Start Nginx
    if systemctl restart nginx 2>/dev/null; then
        print_success "Nginx started successfully"
    else
        print_error "Failed to start Nginx"
        journalctl -u nginx --no-pager -n 10 2>/dev/null || true
        return 1
    fi
    
    # Run helper service
    cat > /etc/systemd/system/runn.service <<'EOF'
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
    
    systemctl enable runn 2>/dev/null || true
    systemctl restart runn 2>/dev/null || true
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================
display_summary() {
    clear
    echo -e "${green}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${green}║${NC}         ${green}✅ XRAY INSTALLATION COMPLETE!                  ${green}║${NC}"
    echo -e "${green}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${cyan}📡 XRAY INFORMATION:${NC}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  ${green}%-14s${NC} : ${green}%s${NC}\n" "Domain" "$DOMAIN"
    printf "  ${green}%-14s${NC} : ${green}%s${NC}\n" "UUID" "$UUID"
    echo ""
    
    echo -e "${cyan}🔧 SERVICE STATUS:${NC}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if systemctl is-active --quiet xray; then
        printf "  ${green}%-14s${NC} : ${green}✅ Running${NC}\n" "Xray"
    else
        printf "  ${green}%-14s${NC} : ${red}❌ Stopped${NC}\n" "Xray"
    fi
    
    if systemctl is-active --quiet nginx; then
        printf "  ${green}%-14s${NC} : ${green}✅ Running${NC}\n" "Nginx"
    else
        printf "  ${green}%-14s${NC} : ${red}❌ Stopped${NC}\n" "Nginx"
    fi
    echo ""
    
    echo ""
    
    echo -e "${cyan}🔧 COMMANDS:${NC}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${green}Status${NC}  : systemctl status xray"
    echo -e "  ${green}Restart${NC} : systemctl restart xray"
    echo -e "  ${green}Logs${NC}    : journalctl -u xray -f"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo -e "${green}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${green}║${NC}         ${green}🔒 XRAY INSTALLER v2.0                          ${green}║${NC}"
    echo -e "${green}║${NC}         ${green}Universal Ubuntu & Debian Support               ${green}║${NC}"
    echo -e "${green}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    detect_os
    get_domain
    install_packages
    setup_certificate || print_warn "Certificate setup had issues, continuing..."
    install_xray || print_fatal "Xray installation failed!"
    configure_xray
    configure_nginx || print_warn "Nginx configuration had issues, continuing..."
    download_scripts
    start_services
    
    # Save domain to /etc/xray
    echo "$DOMAIN" > /etc/xray/domain 2>/dev/null || true
    rm -f /root/domain /root/domain.txt 2>/dev/null || true
    
    display_summary
    
    print_success "Xray installation completed!"
    
    # Clean up
    rm -f ins-xray.sh 2>/dev/null || true
}

# ============================================================
# SCRIPT ENTRY
# ============================================================
main "$@"