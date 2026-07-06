#!/bin/bash
# ============================================================
# VPN API INSTALLER - NODE.JS VERSION (CLEANUP + PORT HANDLING)
# ============================================================

clear

# ---------- COLOURS ----------
green='\033[0;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

echo -e "${cyan}🚀 Installing VPN API Server (Node.js)...${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}✗ Run as root!${NC}" 
   exit 1
fi

# ============================================================
# DETECT OS
# ============================================================
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    CODENAME=$(source /etc/os-release && echo "$VERSION_CODENAME" 2>/dev/null)
else
    echo -e "${red}✗ Unsupported OS${NC}"
    exit 1
fi

echo -e "${green}✓ OS: $OS $VER ($CODENAME)${NC}"

API_PORT=1123
API_DIR="/var/www/api"
GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
IP=$(wget -qO- ipv4.icanhazip.com || curl -sS ifconfig.me)

# ============================================================
# CLEANUP OLD INSTALLATION
# ============================================================
echo -e "${cyan}Cleaning up previous installation...${NC}"

# Stop and delete PM2 process if exists
if command -v pm2 &>/dev/null; then
    pm2 stop vpn-api 2>/dev/null
    pm2 delete vpn-api 2>/dev/null
    pm2 save 2>/dev/null
fi

# Remove old API directory and scripts
rm -rf "$API_DIR"
rm -f /usr/bin/ssh-api.sh /usr/bin/vless-api.sh /usr/bin/vmess-api.sh

# Check if port is in use
if command -v netstat &>/dev/null; then
    if netstat -tulpn | grep -q ":$API_PORT "; then
        echo -e "${yellow}⚠️ Port $API_PORT is currently in use.${NC}"
        echo -e "   You may want to stop the process using it before installing."
        echo -e "   To force kill: fuser -k $API_PORT/tcp"
        read -p "   Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${red}Installation aborted.${NC}"
            exit 1
        fi
    fi
fi

# ============================================================
# DOWNLOAD HELPER FUNCTION
# ============================================================
dl() {
    local dest="$1"
    local src="$2"
    echo "  Downloading $src → $dest"
    wget -q -O "$dest" "$GHBASE/$src" && \
        chmod +x "$dest" && \
        sed -i 's/\r$//' "$dest"
    if [ $? -ne 0 ]; then
        echo -e "${red}✗ Failed to download $src${NC}"
        return 1
    fi
    echo -e "${green}✓ Downloaded $src${NC}"
}

# ============================================================
# INSTALL NODE.JS & PM2
# ============================================================
echo -e "${cyan}Installing Node.js...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
NODE_VERSION=$(node -v)
echo -e "${green}✓ Node.js installed: $NODE_VERSION${NC}"

echo -e "${cyan}Installing PM2...${NC}"
npm install -g pm2

# ============================================================
# DOWNLOAD BASH SCRIPTS TO /usr/bin
# ============================================================
echo -e "${cyan}Downloading bash scripts to /usr/bin...${NC}"
mkdir -p /usr/bin

dl /usr/bin/ssh-api.sh   api/ssh-api.sh
dl /usr/bin/vless-api.sh api/vless-api.sh
dl /usr/bin/vmess-api.sh api/vmess-api.sh

# Verify they exist and are not empty
for script in ssh-api.sh vless-api.sh vmess-api.sh; do
    if [ ! -s "/usr/bin/$script" ]; then
        echo -e "${red}✗ /usr/bin/$script is empty or missing!${NC}"
        exit 1
    fi
done

# ============================================================
# SETUP API DIRECTORY AND DOWNLOAD api.js
# ============================================================
echo -e "${cyan}Setting up API directory...${NC}"
mkdir -p $API_DIR
cd $API_DIR

dl $API_DIR/api.js api/api.js

# Verify api.js is not empty
if [ ! -s "$API_DIR/api.js" ]; then
    echo -e "${red}✗ api.js is empty or missing!${NC}"
    exit 1
fi

# ============================================================
# CREATE PM2 ECOSYSTEM FILE
# ============================================================
cat > ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: 'vpn-api',
    script: '$API_DIR/api.js',
    env: {
      API_PORT: $API_PORT
    },
    watch: false,
    autorestart: true,
    max_memory_restart: '200M',
    error_file: '/var/log/vpn-api-error.log',
    out_file: '/var/log/vpn-api-out.log'
  }]
};
EOF

# ============================================================
# START WITH PM2
# ============================================================
echo -e "${cyan}Starting API with PM2...${NC}"
pm2 start ecosystem.config.js
if [ $? -ne 0 ]; then
    echo -e "${red}✗ Failed to start API with PM2. Check logs: pm2 logs vpn-api${NC}"
    exit 1
fi
pm2 save
pm2 startup | tail -n 1 | bash

# ============================================================
# TEST API
# ============================================================
echo -e "${cyan}Testing API...${NC}"
sleep 2  # Give it a moment to start
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$API_PORT/api.js?token=admin&type=ssh&username=test&password=test&duration=1")
if [ "$TEST_RESPONSE" = "200" ] || [ "$TEST_RESPONSE" = "403" ] || [ "$TEST_RESPONSE" = "400" ]; then
    echo -e "${green}✓ API responded with HTTP $TEST_RESPONSE (OK)${NC}"
else
    echo -e "${red}✗ API did not respond correctly (HTTP $TEST_RESPONSE)${NC}"
    echo -e "   Check logs: pm2 logs vpn-api"
    echo -e "   Try to restart: pm2 restart vpn-api"
fi

# ============================================================
# CONFIGURE FIREWALL
# ============================================================
echo -e "${cyan}Configuring firewall...${NC}"
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow $API_PORT/tcp
    echo -e "${green}✓ Port $API_PORT opened in UFW${NC}"
fi
if command -v iptables &>/dev/null; then
    iptables -I INPUT -p tcp --dport $API_PORT -j ACCEPT
    if command -v iptables-save &>/dev/null; then
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
echo -e " API URL      : ${green}http://${IP}:${API_PORT}/api.js${NC}"
echo -e " API Token    : ${yellow}admin${NC}"
echo -e " Node.js      : ${green}$NODE_VERSION${NC}"
echo -e " Scripts      : ${green}/usr/bin/{ssh,vless,vmess}-api.sh${NC}"
echo -e " API Directory: ${green}${API_DIR}${NC}"
echo -e " PM2 process  : ${green}pm2 show vpn-api${NC}"
echo -e " Logs         : ${green}pm2 logs vpn-api${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${cyan}📚 Usage Examples${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${white}SSH:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.js?token=admin&type=ssh&username=test&password=12345&duration=7\"${NC}"
echo ""
echo -e " ${white}VLESS:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.js?token=admin&type=vless&username=test&duration=7\"${NC}"
echo ""
echo -e " ${white}VMESS:${NC}"
echo -e " ${green}curl \"http://${IP}:${API_PORT}/api.js?token=admin&type=vmess&username=test&duration=7\"${NC}"
echo -e "${yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${yellow}⚠️  Change default token in ${API_DIR}/api.js${NC}"
echo -e "${yellow}   sed -i \"s/API_TOKEN = 'admin'/API_TOKEN = 'your_new_token'/\" ${API_DIR}/api.js${NC}"
echo -e "${yellow}   Then restart: pm2 restart vpn-api${NC}"
echo ""