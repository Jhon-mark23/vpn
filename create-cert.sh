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

# ---- Stop nginx (to free port 80) ----
systemctl stop nginx 2>/dev/null || true

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

# Method 1: Standalone
echo -e "[ ${green}INFO${NC} ] Trying standalone ACME verification..."
/root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 --force 2>/dev/null && {
    if [ -f /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]; then
        ISSUED=true
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
            echo -e "[ ${green}SUCCESS${NC} ] Certificate issued via webroot"
        fi
    } || true
    systemctl stop nginx 2>/dev/null || true
fi

# ---- Install certificate to central directory ----
if [ "$ISSUED" = true ]; then
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
    echo -e "[ ${yellow}INFO${NC} ] Self-signed certificate created in $CERT_DIR"
fi

# ---- Set correct permissions ----
chmod 600 "$CERT_DIR/privkey.pem"
chmod 644 "$CERT_DIR/fullchain.pem"

# ---- Prepare for Xray: symlink from /etc/xray ----
mkdir -p /etc/xray
ln -sf "$CERT_DIR/fullchain.pem" /etc/xray/xray.crt
ln -sf "$CERT_DIR/privkey.pem" /etc/xray/xray.key
chown -h www-data:www-data /etc/xray/xray.crt /etc/xray/xray.key 2>/dev/null || true
chmod 600 /etc/xray/xray.key 2>/dev/null || true

# ---- Prepare for Stunnel: combined PEM ----
mkdir -p /etc/stunnel
cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true

# ---- Auto‑renewal cron (every 30 days) ----
RENEW_SCRIPT="/usr/local/bin/cert-renew.sh"
cat > "$RENEW_SCRIPT" << 'RENEW_EOF'
#!/bin/bash
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then exit 1; fi
systemctl stop nginx 2>/dev/null
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --cert-file /etc/ssl/vpn/fullchain.pem \
    --key-file /etc/ssl/vpn/privkey.pem \
    --ecc 2>/dev/null
cat /etc/ssl/vpn/fullchain.pem /etc/ssl/vpn/privkey.pem > /etc/stunnel/stunnel.pem
systemctl start nginx 2>/dev/null
systemctl restart stunnel4 2>/dev/null
RENEW_EOF
chmod +x "$RENEW_SCRIPT"

if ! grep -q 'cert-renew.sh' /var/spool/cron/crontabs/root 2>/dev/null; then
    (crontab -l 2>/dev/null; echo "0 3 * * 1 /usr/local/bin/cert-renew.sh") | crontab - 2>/dev/null
fi

# ---- Restart nginx if it was running ----
systemctl start nginx 2>/dev/null || true

echo -e "[ ${green}DONE${NC} ] Certificate setup complete."
echo -e "Xray cert  : /etc/xray/xray.crt"
echo -e "Stunnel PEM: /etc/stunnel/stunnel.pem"