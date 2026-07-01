#!/bin/bash
# ============================================================
# MARCSCRIPT SHARED CERTIFICATE GENERATOR
# Creates one certificate for both Stunnel4 and Xray
# No conflicts - same cert for all SSL services
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success(){ echo -e "${BLUE}[SUCCESS]${NC} $1"; }

# ============================================================
# SHOW BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ██████╗███████╗██████╗ ████████╗██╗███████╗██╗  ██╗${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}    ██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║██╔════╝██║  ██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}    ██║     █████╗  ██████╔╝   ██║   ██║███████╗███████║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}    ██║     ██╔══╝  ██╔══██╗   ██║   ██║╚════██║██╔══██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}    ╚██████╗███████╗██║  ██║   ██║   ██║███████║██║  ██║${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     ╚═════╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚══════╝╚═╝  ╚═╝${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}           SHARED CERTIFICATE GENERATOR                 ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                                                          ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

show_banner

# ============================================================
# GET DOMAIN
# ============================================================
if [ -f /root/domain ]; then
    DOMAIN=$(cat /root/domain)
    print_info "Using domain from /root/domain: $DOMAIN"
elif [ -f /etc/xray/domain ]; then
    DOMAIN=$(cat /etc/xray/domain)
    print_info "Using domain from /etc/xray/domain: $DOMAIN"
else
    print_info "No domain found. Please enter your domain:"
    read -rp "Domain: " DOMAIN
    DOMAIN="${DOMAIN//[[:space:]]/}"
    echo "$DOMAIN" > /root/domain
fi

echo ""
print_info "Domain: $DOMAIN"
echo ""

# ============================================================
# CREATE DIRECTORY STRUCTURE
# ============================================================
mkdir -p /etc/stunnel
mkdir -p /etc/xray
mkdir -p /root/.acme.sh
mkdir -p /home/vps/public_html

# ============================================================
# OPTION 1: TRY LET'S ENCRYPT (if available)
# ============================================================
CERT_SOURCE=""
CERT_ISSUED=false

print_info "Checking for Let's Encrypt certificate..."

# Check if acme.sh is installed
if [ -f /root/.acme.sh/acme.sh ]; then
    print_info "acme.sh found, attempting to issue certificate..."
    
    # Stop nginx for standalone
    systemctl stop nginx 2>/dev/null || true
    
    # Try to issue certificate
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 2>/dev/null
    
    if [ -f /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]; then
        CERT_ISSUED=true
        CERT_SOURCE="Let's Encrypt"
        print_success "Let's Encrypt certificate issued"
        
        # Install certificate
        /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
            --fullchainpath /etc/xray/xray.crt \
            --keypath /etc/xray/xray.key --ecc 2>/dev/null
    fi
fi

# ============================================================
# OPTION 2: GENERATE SELF-SIGNED CERTIFICATE (Fallback)
# ============================================================
if [ "$CERT_ISSUED" = false ]; then
    print_warn "Let's Encrypt failed or not available, generating self-signed..."
    
    # Generate with SAN (Subject Alternative Name)
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
O = MarcScript
CN = DOMAIN_PLACEHOLDER

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = DOMAIN_PLACEHOLDER
DNS.2 = *.DOMAIN_PLACEHOLDER
EOF

    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /tmp/openssl.cnf
    
    # Generate certificate with SAN
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -config /tmp/openssl.cnf \
        -extensions v3_req 2>/dev/null
    
    rm -f /tmp/openssl.cnf
    
    # If SAN fails, fallback to simple
    if [ ! -f /etc/xray/xray.crt ]; then
        print_warn "SAN generation failed, using simple certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/xray/xray.key -out /etc/xray/xray.crt \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=MarcScript/CN=$DOMAIN" 2>/dev/null
    fi
    
    if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
        CERT_ISSUED=true
        CERT_SOURCE="Self-Signed"
        print_success "Self-signed certificate created"
    fi
fi

# ============================================================
# VERIFY CERTIFICATE EXISTS
# ============================================================
if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
    print_error "Certificate generation failed!"
    exit 1
fi

# ============================================================
# SHARE CERTIFICATE WITH STUNNEL4
# ============================================================
print_info "Sharing certificate with Stunnel4..."

# Create combined PEM for Stunnel4
cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

# Set ownership
chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
chown www-data:www-data /etc/xray/xray.crt /etc/xray/xray.key 2>/dev/null || true

print_success "Certificate shared with Stunnel4"

# ============================================================
# UPDATE STUNNEL4 CONFIG (if exists)
# ============================================================
if [ -f /etc/stunnel/stunnel.conf ]; then
    print_info "Updating Stunnel4 config to use shared certificate..."
    
    # Check if certificate path is correct
    if ! grep -q "cert = /etc/stunnel/stunnel.pem" /etc/stunnel/stunnel.conf; then
        # Backup config
        cp /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.conf.bak
        
        # Update cert path
        sed -i 's|cert = .*|cert = /etc/stunnel/stunnel.pem|g' /etc/stunnel/stunnel.conf
        print_success "Stunnel4 config updated"
    fi
    
    # Restart Stunnel4
    systemctl restart stunnel4 2>/dev/null || true
fi

# ============================================================
# UPDATE NGINX CONFIG (if exists)
# ============================================================
if [ -f /etc/nginx/conf.d/xray.conf ]; then
    print_info "Updating Nginx config to use shared certificate..."
    
    # Check if certificate path is correct
    if ! grep -q "ssl_certificate /etc/xray/xray.crt" /etc/nginx/conf.d/xray.conf; then
        # Backup config
        cp /etc/nginx/conf.d/xray.conf /etc/nginx/conf.d/xray.conf.bak
        
        # Update cert paths
        sed -i 's|ssl_certificate .*|ssl_certificate /etc/xray/xray.crt;|g' /etc/nginx/conf.d/xray.conf
        sed -i 's|ssl_certificate_key .*|ssl_certificate_key /etc/xray/xray.key;|g' /etc/nginx/conf.d/xray.conf
        print_success "Nginx config updated"
    fi
    
    # Test and restart Nginx
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true
fi

# ============================================================
# RESTART XRAY
# ============================================================
if systemctl is-active --quiet xray; then
    print_info "Restarting Xray..."
    systemctl restart xray 2>/dev/null || true
fi

# ============================================================
# SETUP AUTO-RENEWAL (Only for Let's Encrypt)
# ============================================================
if [ "$CERT_SOURCE" = "Let's Encrypt" ]; then
    print_info "Setting up auto-renewal..."
    
    cat > /usr/local/bin/ssl_renew.sh <<'EOF'
#!/bin/bash
systemctl stop nginx 2>/dev/null
/root/.acme.sh/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
# Copy renewed certificate to Stunnel4
if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
    cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    systemctl restart stunnel4 2>/dev/null
fi
systemctl start nginx 2>/dev/null
systemctl restart xray 2>/dev/null
EOF
    chmod +x /usr/local/bin/ssl_renew.sh
    
    if ! crontab -l 2>/dev/null | grep -q ssl_renew.sh; then
        (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/ssl_renew.sh") | crontab -
    fi
    
    print_success "Auto-renewal configured (daily at 3:00 AM)"
fi

# ============================================================
# SHOW CERTIFICATE INFO
# ============================================================
clear
show_banner

echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${GREEN}              ✅ CERTIFICATE GENERATED!                   ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                   📋 CERTIFICATE INFO${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}  Domain          :${NC} $DOMAIN"
echo -e "${GREEN}  Certificate     :${NC} /etc/xray/xray.crt"
echo -e "${GREEN}  Private Key     :${NC} /etc/xray/xray.key"
echo -e "${GREEN}  Stunnel PEM     :${NC} /etc/stunnel/stunnel.pem"
echo -e "${GREEN}  Source          :${NC} $CERT_SOURCE"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                   📁 SERVICES USING THIS CERT${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}  ✅ Xray          :${NC} /etc/xray/xray.crt + /etc/xray/xray.key"
echo -e "${GREEN}  ✅ Stunnel4      :${NC} /etc/stunnel/stunnel.pem"
echo -e "${GREEN}  ✅ Nginx         :${NC} /etc/xray/xray.crt (if configured)"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                   🔧 COMMANDS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}View certificate${NC} : openssl x509 -in /etc/xray/xray.crt -text -noout"
echo -e "  ${GREEN}Check expiry${NC}    : openssl x509 -in /etc/xray/xray.crt -noout -enddate"
echo -e "  ${GREEN}Renew manually${NC}  : bash /usr/local/bin/ssl_renew.sh"
echo ""

# ============================================================
# VERIFY SERVICES
# ============================================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                   🔍 SERVICE STATUS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check Xray
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}  ✅ Xray          : Running${NC}"
else
    echo -e "${RED}  ❌ Xray          : Not Running${NC}"
fi

# Check Stunnel4
if systemctl is-active --quiet stunnel4; then
    echo -e "${GREEN}  ✅ Stunnel4      : Running${NC}"
else
    echo -e "${RED}  ❌ Stunnel4      : Not Running${NC}"
fi

# Check Nginx
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}  ✅ Nginx         : Running${NC}"
else
    echo -e "${RED}  ❌ Nginx         : Not Running${NC}"
fi

echo ""
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}           CERTIFICATE SHARED SUCCESSFULLY!             ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_success "Certificate generation completed!"
print_info "All SSL services now use the same certificate"

exit 0