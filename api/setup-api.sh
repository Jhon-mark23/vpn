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

# ============================================================
# GET GITHUB TOKEN
# ============================================================
echo -e "${cyan}Checking for GitHub token...${NC}"

# Try multiple locations for token
TOKEN_FILE="/root/token"
if [ -f "/root/token.txt" ]; then
    TOKEN_FILE="/root/token.txt"
fi

if [ -f "$TOKEN_FILE" ]; then
    GITHUB_TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
    echo -e "${green}✓ GitHub token found${NC}"
else
    echo -e "${yellow}⚠️ No GitHub token found!${NC}"
    echo -e "   This repository is private and requires authentication."
    echo -e "   Please create a GitHub Personal Access Token with 'repo' scope."
    echo ""
    read -p "   Enter your GitHub token: " GITHUB_TOKEN
    GITHUB_TOKEN=$(echo "$GITHUB_TOKEN" | tr -d '[:space:]')
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${red}✗ No token provided. Aborting.${NC}"
        exit 1
    fi
    echo -e "${green}✓ Token accepted${NC}"
fi

# Set GitHub API URL for private repo
GITHUB_API="https://api.github.com/repos/Jhon-mark23/vpn/contents"
GH_BASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/main"

# Try multiple IP services for redundancy
IP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || wget -qO- ifconfig.me 2>/dev/null || curl -sS ifconfig.me 2>/dev/null || echo "your-server-ip")

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
    if netstat -tulpn 2>/dev/null | grep -q ":$API_PORT "; then
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
# DOWNLOAD HELPER FUNCTION (FOR PRIVATE REPO)
# ============================================================
dl_private() {
    local dest="$1"
    local src="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=2
    
    echo -e "  📥 Downloading ${cyan}$src${NC} → ${white}$dest${NC}"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$dest")" 2>/dev/null
    
    while [ $retry_count -lt $max_retries ]; do
        # Try GitHub API to get raw content URL first
        local raw_url=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3.raw" \
            "$GITHUB_API/$src?ref=main" 2>/dev/null | head -1)
        
        if [ -z "$raw_url" ]; then
            # Fallback: try direct raw URL with token
            if command -v wget &>/dev/null; then
                wget --header="Authorization: token $GITHUB_TOKEN" \
                    --no-check-certificate --timeout=30 --tries=3 \
                    -q -O "$dest" "$GH_BASE/$src" 2>/dev/null
                local status=$?
            else
                curl -sf -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3.raw" \
                    --connect-timeout 30 --max-time 60 \
                    -o "$dest" "$GH_BASE/$src" 2>/dev/null
                local status=$?
            fi
        else
            # Download using the raw URL
            curl -sf -H "Authorization: token $GITHUB_TOKEN" \
                --connect-timeout 30 --max-time 60 \
                -o "$dest" "$raw_url" 2>/dev/null
            local status=$?
        fi
        
        if [ $status -eq 0 ] && [ -s "$dest" ]; then
            break
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo -e "  ${yellow}⚠️ Attempt $retry_count failed, retrying in ${wait_time}s...${NC}"
            sleep $wait_time
            wait_time=$((wait_time * 2))
        fi
    done
    
    # Validate download
    if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
        echo -e "${red}✗ FAILED to download $src after $max_retries attempts${NC}"
        return 1
    fi
    
    # Check if download looks like HTML (GitHub error page)
    if head -n 1 "$dest" 2>/dev/null | grep -qi "<!doctype\|html\|not found\|404\|Bad credentials"; then
        echo -e "${red}✗ Download of $src appears to be invalid${NC}"
        echo -e "  Possible issues:"
        echo -e "  - Token might not have 'repo' scope"
        echo -e "  - Token might be expired"
        echo -e "  - File might not exist in repository"
        echo -e "  - Repository might be inaccessible"
        rm -f "$dest"
        return 1
    fi
    
    # Make executable and fix line endings
    chmod +x "$dest" 2>/dev/null
    sed -i 's/\r$//' "$dest" 2>/dev/null
    
    local filesize=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null || echo "?")
    echo -e "  ${green}✓ Downloaded successfully (${filesize} bytes)${NC}"
    return 0
}

# ============================================================
# VERIFY GITHUB REPOSITORY ACCESS
# ============================================================
echo -e "${cyan}Verifying repository access...${NC}"

# Test token by checking a known file
TEST_RESPONSE=$(curl -sf -w "%{http_code}" -o /dev/null \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3.raw" \
    "$GITHUB_API/api/ssh-api.sh?ref=main" 2>/dev/null)

if [ "$TEST_RESPONSE" != "200" ]; then
    echo -e "${red}✗ Cannot access private repository${NC}"
    echo -e "  HTTP Status: $TEST_RESPONSE"
    echo -e "  Please check:"
    echo -e "  - Token has 'repo' scope"
    echo -e "  - Token is not expired"
    echo -e "  - Repository exists"
    exit 1
fi
echo -e "${green}✓ Private repository accessible${NC}"

# ============================================================
# INSTALL REQUIRED TOOLS
# ============================================================
echo -e "${cyan}Checking required tools...${NC}"
for tool in wget curl; do
    if ! command -v $tool &>/dev/null; then
        echo -e "  Installing $tool..."
        apt-get update -qq && apt-get install -y -qq $tool
    fi
done

# ============================================================
# INSTALL NODE.JS & PM2
# ============================================================
echo -e "${cyan}Installing Node.js...${NC}"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || {
        echo -e "${red}✗ Failed to add Node.js repository${NC}"
        exit 1
    }
    apt install -y nodejs || {
        echo -e "${red}✗ Failed to install Node.js${NC}"
        exit 1
    }
else
    echo -e "${green}✓ Node.js already installed${NC}"
fi
NODE_VERSION=$(node -v)
echo -e "${green}✓ Node.js version: $NODE_VERSION${NC}"

echo -e "${cyan}Installing PM2...${NC}"
npm install -g pm2 || {
    echo -e "${red}✗ Failed to install PM2${NC}"
    exit 1
}
echo -e "${green}✓ PM2 installed${NC}"

# ============================================================
# DOWNLOAD BASH SCRIPTS TO /usr/bin
# ============================================================
echo -e "${cyan}Downloading bash scripts to /usr/bin...${NC}"
mkdir -p /usr/bin

dl_private /usr/bin/ssh-api.sh api/ssh-api.sh || exit 1
dl_private /usr/bin/vless-api.sh api/vless-api.sh || exit 1
dl_private /usr/bin/vmess-api.sh api/vmess-api.sh || exit 1

# Verify they exist and are executable
echo -e "${cyan}Verifying downloaded scripts...${NC}"
for script in ssh-api.sh vless-api.sh vmess-api.sh; do
    if [ ! -f "/usr/bin/$script" ]; then
        echo -e "${red}✗ /usr/bin/$script is missing!${NC}"
        exit 1
    fi
    if [ ! -s "/usr/bin/$script" ]; then
        echo -e "${red}✗ /usr/bin/$script is empty!${NC}"
        exit 1
    fi
    if [ ! -x "/usr/bin/$script" ]; then
        echo -e "${yellow}⚠️ Making /usr/bin/$script executable${NC}"
        chmod +x "/usr/bin/$script"
    fi
    # Quick syntax check
    bash -n "/usr/bin/$script" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${red}✗ /usr/bin/$script has syntax errors!${NC}"
        exit 1
    fi
    echo -e "${green}✓ $script verified${NC}"
done

# ============================================================
# SETUP API DIRECTORY AND DOWNLOAD api.js
# ============================================================
echo -e "${cyan}Setting up API directory...${NC}"
mkdir -p $API_DIR
cd $API_DIR

dl_private $API_DIR/api.js api/api.js || exit 1

# Verify api.js is valid
if [ ! -f "$API_DIR/api.js" ] || [ ! -s "$API_DIR/api.js" ]; then
    echo -e "${red}✗ api.js is missing or empty!${NC}"
    exit 1
fi

# ============================================================
# CREATE PM2 ECOSYSTEM FILE
# ============================================================
echo -e "${cyan}Creating PM2 ecosystem file...${NC}"
cat > "$API_DIR/ecosystem.config.js" <<'EOF'
module.exports = {
  apps: [{
    name: 'vpn-api',
    script: 'api.js',
    cwd: '/var/www/api',
    env: {
      API_PORT: 1123
    },
    watch: false,
    autorestart: true,
    max_memory_restart: '200M',
    error_file: '/var/log/vpn-api-error.log',
    out_file: '/var/log/vpn-api-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true
  }]
};
EOF

# Update the port in the ecosystem file
sed -i "s/API_PORT: 1123/API_PORT: $API_PORT/" "$API_DIR/ecosystem.config.js"

# ============================================================
# START WITH PM2
# ============================================================
echo -e "${cyan}Starting API with PM2...${NC}"
cd $API_DIR
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
sleep 3

# Check if process is actually running
if pm2 show vpn-api 2>/dev/null | grep -q "online"; then
    echo -e "${green}✓ PM2 process is online${NC}"
else
    echo -e "${red}✗ PM2 process is not online!${NC}"
    echo -e "  Checking logs..."
    pm2 logs vpn-api --lines 20 --nostream 2>/dev/null
    exit 1
fi

# Test the endpoint
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://127.0.0.1:$API_PORT/api.js?token=admin&type=ssh&username=test&password=test&duration=1" 2>/dev/null)
if [ "$TEST_RESPONSE" = "200" ] || [ "$TEST_RESPONSE" = "403" ] || [ "$TEST_RESPONSE" = "400" ]; then
    echo -e "${green}✓ API responded with HTTP $TEST_RESPONSE (OK)${NC}"
else
    echo -e "${red}✗ API did not respond correctly (HTTP $TEST_RESPONSE)${NC}"
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
echo -e "${cyan}📝 For troubleshooting:${NC}"
echo -e "   View logs:  ${white}pm2 logs vpn-api --lines 50${NC}"
echo -e "   Restart:    ${white}pm2 restart vpn-api${NC}"
echo -e "   Stop:       ${white}pm2 stop vpn-api${NC}"
echo -e "   Full reset: ${white}pm2 delete vpn-api && rm -rf $API_DIR${NC}"