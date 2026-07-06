#!/bin/bash
# ============================================================
# VPN API INSTALLER - WORKS WITH ANY UBUNTU VERSION
# ============================================================

clear

# ---------- COLOURS ----------
green='\033[0;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

echo -e "${cyan}🚀 Installing VPN API Server...${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}✗ Run as root!${NC}" 
   exit 1
fi

API_PORT=1123
API_DIR="/var/www/api"
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "vpn.yourdomain.com")
IP=$(wget -qO- ipv4.icanhazip.com || curl -sS ifconfig.me)

# ============================================================
# DETECT OS AND GET CORRECT REPOSITORY
# ============================================================
echo -e "${cyan}Detecting OS...${NC}"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null)
    
    # If codename is invalid or unreleased, use the latest LTS codename
    if [[ -z "$UBUNTU_CODENAME" ]] || [[ "$UBUNTU_CODENAME" == "resolute" ]] || [[ ! "$UBUNTU_CODENAME" =~ ^(focal|jammy|noble|oracular|plucky)$ ]]; then
        # Use the latest LTS release as fallback
        UBUNTU_CODENAME="noble"  # Ubuntu 24.04 LTS
        echo -e "${yellow}⚠️ Using $UBUNTU_CODENAME as fallback codename${NC}"
    fi
else
    echo -e "${red}✗ Unsupported OS${NC}"
    exit 1
fi

echo -e "${green}✓ OS: $OS $VER${NC}"
echo -e "${green}✓ Codename: $UBUNTU_CODENAME${NC}"
echo ""

# ============================================================
# INSTALL PHP REPOSITORY
# ============================================================
echo -e "${cyan}Installing PHP repository...${NC}"

if [[ "$OS" == "ubuntu" ]]; then
    apt update -y
    apt install -y software-properties-common ca-certificates lsb-release apt-transport-https curl wget gnupg2
    
    # Try multiple methods to add the repository
    echo -e "${cyan}Attempting to add Ondrej PHP PPA...${NC}"
    
    # Method 1: Try with official codename
    if add-apt-repository -y "ppa:ondrej/php" 2>/dev/null; then
        echo -e "${green}✓ Added repository via add-apt-repository${NC}"
    else
        # Method 2: Try with fallback codename
        echo -e "${yellow}⚠️ Trying with fallback codename...${NC}"
        rm -f /etc/apt/sources.list.d/ondrej-php.list
        
        # Try the latest LTS codename
        for CODENAME in noble jammy focal; do
            echo "deb https://ppa.launchpadcontent.net/ondrej/php/ubuntu $CODENAME main" > /etc/apt/sources.list.d/ondrej-php.list
            echo "deb-src https://ppa.launchpadcontent.net/ondrej/php/ubuntu $CODENAME main" >> /etc/apt/sources.list.d/ondrej-php.list
            
            # Try to update with this codename
            if apt update 2>/dev/null | grep -q "Get:"; then
                echo -e "${green}✓ Repository added with codename: $CODENAME${NC}"
                break
            fi
            rm -f /etc/apt/sources.list.d/ondrej-php.list
        done
    fi
    
    # Method 3: Direct install from official packages if PPA fails
    if [[ ! -f /etc/apt/sources.list.d/ondrej-php.list ]] && ! grep -q "ondrej/php" /etc/apt/sources.list.d/* 2>/dev/null; then
        echo -e "${yellow}⚠️ PPA failed, installing default PHP from Ubuntu repos${NC}"
    fi

elif [[ "$OS" == "debian" ]]; then
    apt update -y
    apt install -y curl ca-certificates gnupg2 lsb-release apt-transport-https

    mkdir -p /etc/apt/keyrings

    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor \
        -o /etc/apt/keyrings/sury-php.gpg

    echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php.list
fi

apt update -y

# ============================================================
# DETECT LATEST PHP VERSION
# ============================================================
echo -e "${cyan}Detecting latest PHP version...${NC}"

# Try multiple methods to find PHP
PHP_VERSION=""

# Method 1: From apt-cache
PHP_VERSION=$(apt-cache search '^php[0-9]\.[0-9]+-fpm$' 2>/dev/null \
    | awk '{print $1}' \
    | sed 's/php//' \
    | sed 's/-fpm//' \
    | sort -V \
    | tail -n1)

# Method 2: If empty, try to find installed PHP
if [[ -z "$PHP_VERSION" ]]; then
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v 2>/dev/null | head -1 | grep -oP 'PHP \K[0-9]+\.[0-9]+')
    fi
fi

# Method 3: Fallback to latest available from Ubuntu repos
if [[ -z "$PHP_VERSION" ]]; then
    # Try to find any PHP package
    PHP_VERSION=$(apt-cache search '^php[0-9]\.[0-9]+$' 2>/dev/null \
        | grep -v 'fpm' \
        | awk '{print $1}' \
        | sed 's/php//' \
        | sort -V \
        | tail -n1)
fi

# Method 4: Final fallback
if [[ -z "$PHP_VERSION" ]]; then
    PHP_VERSION="8.3"
    echo -e "${yellow}⚠️ Could not detect PHP, using $PHP_VERSION as fallback${NC}"
fi

echo -e "${green}✓ PHP Version: ${PHP_VERSION}${NC}"

# ============================================================
# DISPLAY CONFIGURATION
# ============================================================
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " API Port      : ${green}$API_PORT${NC}"
echo -e " API Directory : ${green}$API_DIR${NC}"
echo -e " PHP Version   : ${green}$PHP_VERSION${NC}"
echo -e " OS            : ${green}$OS $VER${NC}"
echo -e " Codename      : ${green}$UBUNTU_CODENAME${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Cancelled${NC}"
    exit 0
fi

# ============================================================
# INSTALL PACKAGES
# ============================================================
echo -e "${cyan}[1/5] Installing packages...${NC}"

# Try to install with detected version
PACKAGES="nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip php${PHP_VERSION}-mysql php${PHP_VERSION}-sqlite3 php${PHP_VERSION}-bcmath php${PHP_VERSION}-intl php${PHP_VERSION}-opcache curl wget unzip jq"

echo -e "${cyan}Installing: ${PACKAGES}${NC}"

if ! apt install -y $PACKAGES 2>/dev/null; then
    echo -e "${yellow}⚠️ Version-specific packages failed, trying without versions...${NC}"
    
    # Try without version numbers (Ubuntu default)
    apt install -y nginx php-fpm php-cli php-common php-curl php-mbstring \
        php-xml php-zip php-mysql php-sqlite3 php-bcmath php-intl \
        php-opcache curl wget unzip jq
    
    # Try to detect installed PHP version
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v 2>/dev/null | head -1 | grep -oP 'PHP \K[0-9]+\.[0-9]+')
        echo -e "${green}✓ PHP installed: $PHP_VERSION${NC}"
    fi
fi

# ============================================================
# SETUP API DIRECTORY
# ============================================================
echo -e "${cyan}[2/5] Setting up API directory...${NC}"
mkdir -p $API_DIR
chown -R www-data:www-data $API_DIR

# ============================================================
# DOWNLOAD API FILES
# ============================================================
echo -e "${cyan}[3/5] Downloading API files...${NC}"

cd $API_DIR
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/api/api.php
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/api/ssh-api.sh
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/api/vless-api.sh
wget -q https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/api/vmess-api.sh

chmod +x *.sh
chown www-data:www-data *

# ============================================================
# CONFIGURE NGINX
# ============================================================
echo -e "${cyan}[4/5] Configuring Nginx...${NC}"

# Detect PHP-FPM socket
PHP_SOCKET=$(find /run/php -name "php*-fpm.sock" 2>/dev/null | sort -V | tail -n1)

# If no socket found, try to find via PHP version
if [[ -z "$PHP_SOCKET" ]]; then
    if [[ -n "$PHP_VERSION" ]]; then
        PHP_SOCKET="/var/run/php/php${PHP_VERSION}-fpm.sock"
    else
        PHP_SOCKET="/var/run/php/php-fpm.sock"
    fi
fi

echo -e "${green}✓ PHP-FPM Socket: ${PHP_SOCKET}${NC}"

cat > /etc/nginx/sites-available/api << EOF
server {
    listen $API_PORT;
    listen [::]:$API_PORT;
    root $API_DIR;
    index index.html index.php;
    server_name _;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCKET};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

ln -sf /etc/nginx/sites-available/api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t 2>/dev/null && systemctl restart nginx || echo -e "${yellow}⚠️ Nginx config test failed, check manually${NC}"

# ============================================================
# CONFIGURE PHP-FPM
# ============================================================
echo -e "${cyan}[5/5] Configuring PHP-FPM...${NC}"

# Find PHP-FPM service name
PHP_FPM_SERVICE=$(systemctl list-units --all 2>/dev/null | grep -o 'php[0-9]\.[0-9]*-fpm' | sort -V | tail -n1)

if [[ -z "$PHP_FPM_SERVICE" ]]; then
    # Try to find via php version
    if [[ -n "$PHP_VERSION" ]]; then
        PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
    else
        PHP_FPM_SERVICE="php-fpm"
    fi
fi

# Ensure PHP-FPM uses socket
PHP_FPM_CONF=$(find /etc/php -name "www.conf" 2>/dev/null | head -1)

if [[ -n "$PHP_FPM_CONF" && -f "$PHP_FPM_CONF" ]]; then
    sed -i 's/^listen = .*/listen = \/var\/run\/php\/php-fpm.sock/' $PHP_FPM_CONF
    sed -i 's/^;listen.owner = .*/listen.owner = www-data/' $PHP_FPM_CONF
    sed -i 's/^;listen.group = .*/listen.group = www-data/' $PHP_FPM_CONF
    sed -i 's/^;listen.mode = .*/listen.mode = 0660/' $PHP_FPM_CONF
fi

systemctl daemon-reload
systemctl enable $PHP_FPM_SERVICE 2>/dev/null || true
systemctl restart $PHP_FPM_SERVICE 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true

# ============================================================
# CONFIGURE FIREWALL
# ============================================================
echo -e "${cyan}Configuring firewall...${NC}"

if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow $API_PORT/tcp
    echo -e "${green}✓ Port $API_PORT opened in UFW${NC}"
fi

if command -v iptables &> /dev/null; then
    iptables -I INPUT -p tcp --dport $API_PORT -j ACCEPT
    if command -v iptables-save &> /dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    echo -e "${green}✓ Port $API_PORT opened in iptables${NC}"
fi

# ============================================================
# COMPLETE
# ============================================================
clear
echo -e "${green}✅ API Installation Complete!${NC}"
echo ""
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " API URL      : ${green}http://${IP}:${API_PORT}/api.php${NC}"
echo -e " API Token    : ${yellow}admin${NC}"
echo -e " PHP Version  : ${green}${PHP_VERSION}${NC}"
echo -e " API Directory: ${green}${API_DIR}${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${cyan}📚 Usage Examples${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${white}SSH:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.php?token=admin&type=ssh&username=test&password=12345&duration=7\"${NC}"
echo ""
echo -e " ${white}VLESS:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.php?token=admin&type=vless&username=test&duration=7\"${NC}"
echo ""
echo -e " ${white}VMESS:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.php?token=admin&type=vmess&username=test&duration=7\"${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${yellow}⚠️  Change default token in ${API_DIR}/api.php${NC}"
echo -e "${yellow}   sed -i 's/\"admin\"/\"your_new_token\"/' ${API_DIR}/api.php${NC}"
echo ""