#!/bin/bash
# ============================================================
# CHECK EXPIRED OPENVPN USERS
# ============================================================

USER_DB="/etc/openvpn/client-configs/users.db"
EASYRSA_DIR="/etc/openvpn/easy-rsa"

if [ ! -f "$USER_DB" ]; then
    echo "No users found!"
    exit 0
fi

echo "Checking expired users..."
EXPIRED=0

while IFS=':' read -r user pass expire days status created; do
    if [ -n "$user" ] && [ "$status" = "active" ]; then
        expire_epoch=$(date -d "$expire" +%s 2>/dev/null)
        current_epoch=$(date +%s)
        
        if [ -n "$expire_epoch" ] && [ $expire_epoch -lt $current_epoch ]; then
            echo "User $user has expired! (Expired: $expire)"
            
            # Revoke certificate
            cd "$EASYRSA_DIR"
            ./easyrsa --batch revoke "$user" 2>/dev/null
            
            # Mark as expired in database
            sed -i "s/^$user:$pass:$expire:$days:active/$user:$pass:$expire:$days:expired/" "$USER_DB"
            
            ((EXPIRED++))
        fi
    fi
done < "$USER_DB"

# Update CRL
if [ $EXPIRED -gt 0 ]; then
    cd "$EASYRSA_DIR"
    ./easyrsa gen-crl
    cp "$EASYRSA_DIR/pki/crl.pem" /etc/openvpn/
    systemctl restart openvpn@server-tcp openvpn@server-udp
    echo "Revoked $EXPIRED expired users"
else
    echo "No expired users found"
fi
