#!/bin/bash
# ============================================================
# CREATE-CERT.SH - Unified certificate for Stunnel & Xray
# ============================================================
# Tries Let's Encrypt via acme.sh, falls back to OpenSSL
# Outputs:
#   /etc/ssl/vpn/fullchain.pem    (certificate)
#   /etc/ssl/vpn/privkey.pem      (private key)
#   /etc/xray/xray.crt            (symlink)
#   /etc/xray/xray.key            (symlink)
#   /etc/stunnel/stunnel.pem      (combined cert+key)
# ============================================================

set -e
green='\e[0;32m'
yell='\e[1;33m'
red='\e[1;31m'
NC='\e[0m'

# ---- Read domain ----
DOMAIN=""
if [ -f /root/domain ]; then
    DOMAIN=$(cat /root/domain)
elif [ -n "$1" ]; then
    DOMAIN="$1"
else
    echo -e "[ ${red}ERROR${NC} ] No domain provided. Place domain in /root/domain or pass as argument."
    exit 1
fi
echo -e "[ ${green}INFO${NC} ] Using domain: ${DOMAIN}"

# ---- Prepare common directory ----
CERT_DIR="/etc/ssl/vpn"
mkdir -p "$CERT_DIR"

# ---- Check if Nginx is running ----
NGINX_WAS_RUNNING=false
if systemctl is-active --quiet nginx 2>/dev/null; then
    NGINX_WAS_RUNNING=true
    echo -e "[ ${green}INFO${NC} ] Stopping nginx to free port 80..."
    systemctl stop nginx 2>/dev/null || true
fi

# ---- Check if Stunnel4 is installed ----
STUNNEL_INSTALLED=false
if systemctl list-unit-files 2>/dev/null | grep -q stunnel4; then
    STUNNEL_INSTALLED=true
fi

# ---- Install acme.sh if missing ----
if [ ! -f /root/.acme.sh/acme.sh ]; then
    echo -e "[ ${green}INFO${NC} ] Installing acme.sh..."
    curl -s https://get.acme.sh | sh -s email=admin@$DOMAIN >/dev/null 2>&1 || {
        echo -e "[ ${yell}WARNING${NC} ] Official acme.sh install failed, using alternative..."
        curl -s https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
        chmod +x /root/.acme.sh/acme.sh
    }
fi

# Setup acme.sh
/root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1

# ---- Attempt certificate issuance ----
ISSUED=false
CERT_SOURCE=""

# Method 1: Standalone
echo -e "[ ${green}INFO${NC} ] Trying standalone ACME verification..."
/root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 --force 2>/dev/null && {
    if [ -f /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]; then
        ISSUED=true
        CERT_SOURCE="Let's Encrypt"
        echo -e "[ ${green}SUCCESS${NC} ] Certificate issued via standalone"
    fi
} || true

# Method 2: Webroot
if [ "$ISSUED" = false ]; then
    echo -e "[ ${yell}WARNING${NC} ] Standalone failed, trying webroot method..."
    mkdir -p /home/vps/public_html
    systemctl start nginx 2>/dev/null || true
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --webroot /home/vps/public_html -k ec-256 2>/dev/null && {
        if [ -f /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]; then
            ISSUED=true
            CERT_SOURCE="Let's Encrypt"
            echo -e "[ ${green}SUCCESS${NC} ] Certificate issued via webroot"
        fi
    } || true
    systemctl stop nginx 2>/dev/null || true
fi

# ---- Install certificate to central directory ----
if [ "$ISSUED" = true ] && [ "$CERT_SOURCE" = "Let's Encrypt" ]; then
    /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --cert-file "$CERT_DIR/fullchain.pem" \
        --key-file "$CERT_DIR/privkey.pem" \
        --ecc 2>/dev/null
    echo -e "[ ${green}OK${NC} ] Let's Encrypt certificate installed to $CERT_DIR"
else
    # Fallback: self-signed
    echo -e "[ ${yell}WARNING${NC} ] ACME issuance failed. Generating self-signed certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/privkey.pem" \
        -out "$CERT_DIR/fullchain.pem" \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=VPN/CN=$DOMAIN" 2>/dev/null
    CERT_SOURCE="Self-Signed"
    echo -e "[ ${yell}INFO${NC} ] Self-signed certificate created in $CERT_DIR"
fi

# ---- Set correct permissions ----
chmod 600 "$CERT_DIR/privkey.pem"
chmod 644 "$CERT_DIR/fullchain.pem"
chown www-data:www-data "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" 2>/dev/null || true

# ---- Prepare for Xray: symlink from /etc/xray ----
mkdir -p /etc/xray
ln -sf "$CERT_DIR/fullchain.pem" /etc/xray/xray.crt
ln -sf "$CERT_DIR/privkey.pem" /etc/xray/xray.key
chmod 600 /etc/xray/xray.key 2>/dev/null || true

# ---- Prepare for Stunnel: combined PEM ----
mkdir -p /etc/stunnel
cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

if [ "$STUNNEL_INSTALLED" = true ] && id "stunnel4" &>/dev/null; then
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem
fi

# ---- Restart services ----
if [ "$NGINX_WAS_RUNNING" = true ]; then
    echo -e "[ ${green}INFO${NC} ] Restarting nginx..."
    systemctl start nginx 2>/dev/null || true
fi

# Restart Xray if installed
if systemctl list-unit-files 2>/dev/null | grep -q xray; then
    echo -e "[ ${green}INFO${NC} ] Restarting Xray..."
    systemctl restart xray 2>/dev/null || true
fi

# Restart Stunnel4 if installed
if [ "$STUNNEL_INSTALLED" = true ]; then
    echo -e "[ ${green}INFO${NC} ] Restarting Stunnel4..."
    systemctl restart stunnel4 2>/dev/null || true
fi

# ============================================================
# AUTO-RENEWAL CRON - EVERY 3 DAYS
# ============================================================
if [ "$CERT_SOURCE" = "Let's Encrypt" ]; then
    RENEW_SCRIPT="/usr/local/bin/cert-renew.sh"
    cat > "$RENEW_SCRIPT" << 'RENEW_EOF'
#!/bin/bash
# ============================================================
# CERTIFICATE AUTO-RENEWAL - RUNS EVERY 3 DAYS
# ============================================================

DOMAIN=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    echo "[ERROR] Domain not found"
    exit 1
fi

echo "[$(date)] Starting certificate renewal for $DOMAIN..."

# Stop nginx to free port 80
systemctl stop nginx 2>/dev/null

# Renew certificate
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh

# Reinstall to central directory
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --cert-file /etc/ssl/vpn/fullchain.pem \
    --key-file /etc/ssl/vpn/privkey.pem \
    --ecc 2>/dev/null

# Update Stunnel4
cat /etc/ssl/vpn/fullchain.pem /etc/ssl/vpn/privkey.pem > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

if id "stunnel4" &>/dev/null; then
    chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem
fi

# Restart services
systemctl start nginx 2>/dev/null
systemctl restart stunnel4 2>/dev/null
systemctl restart xray 2>/dev/null

echo "[$(date)] Certificate renewal completed"
RENEW_EOF

    chmod +x "$RENEW_SCRIPT"

    # Remove old cron jobs
    crontab -l 2>/dev/null | grep -v 'cert-renew.sh' | crontab - 2>/dev/null || true

    # ============================================================
    # CRON: EVERY 3 DAYS AT 3:00 AM
    # Format: Minute Hour Day Month DayOfWeek
    # ============================================================
    (crontab -l 2>/dev/null; echo "0 3 */3 * * /usr/local/bin/cert-renew.sh >> /var/log/cert-renew.log 2>&1") | crontab - 2>/dev/null

    echo -e "[ ${green}OK${NC} ] Auto-renewal cron installed (every 3 days at 3:00 AM)"
    echo -e "[ ${green}INFO${NC} ] Log file: /var/log/cert-renew.log"

else
    echo -e "[ ${yell}WARNING${NC} ] Self-signed certificate - no auto-renewal configured"
fi

# ---- Show final info ----
echo ""
echo -e "[ ${green}DONE${NC} ] Certificate setup complete."
echo -e "═══════════════════════════════════════════════════════════════"
echo -e "  📁 Certificate Location : $CERT_DIR"
echo -e "  📁 Xray symlink        : /etc/xray/xray.crt"
echo -e "  📁 Stunnel PEM         : /etc/stunnel/stunnel.pem"
echo -e "  📁 Source              : $CERT_SOURCE"
echo -e "  🔄 Auto-Renewal       : Every 3 days at 3:00 AM"
echo -e "  📋 Log file           : /var/log/cert-renew.log"
echo -e "═══════════════════════════════════════════════════════════════"