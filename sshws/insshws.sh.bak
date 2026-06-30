#!/bin/bash
# Install SSH Websocket - Compatible with Debian & Ubuntu
clear
cd

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "Cannot detect OS. Using Ubuntu defaults..."
        OS="ubuntu"
    fi
    echo -e "[ INFO ] Detected OS: $OS"
}

detect_os

# Pastikan python3 tersedia
apt-get install -y python3 python3-pip 2>/dev/null

# Fix: Create python symlink for Debian (if missing)
if [[ "$OS" == "debian" ]]; then
    if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
        ln -s /usr/bin/python3 /usr/bin/python
        echo "[ ok ] Created python symlink for Debian"
    fi
fi

# Install ws-dropbear dan ws-stunnel dari repo (binary python)
wget -O /usr/local/bin/ws-dropbear https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/ws-dropbear
wget -O /usr/local/bin/ws-stunnel https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/sshws/ws-stunnel

chmod +x /usr/local/bin/ws-dropbear
chmod +x /usr/local/bin/ws-stunnel

# Fix shebang untuk kedua OS - gunakan /usr/bin/env python3 yang lebih portable
# Hapus shebang yang ada jika salah
sed -i '1{/^#!/d}' /usr/local/bin/ws-stunnel 2>/dev/null
sed -i '1{/^#!/d}' /usr/local/bin/ws-dropbear 2>/dev/null

# Tambahkan shebang yang benar di awal file
sed -i '1i#!/usr/bin/env python3' /usr/local/bin/ws-stunnel
sed -i '1i#!/usr/bin/env python3' /usr/local/bin/ws-dropbear

# Buat systemd service ws-dropbear (port 80 - SSH WS HTTP)
cat > /etc/systemd/system/ws-dropbear.service <<-END
[Unit]
Description=Websocket-Dropbear (HTTP port 2095 internal)
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/env python3 /usr/local/bin/ws-dropbear 2095
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END

# Buat systemd service ws-stunnel (port 443 - SSH WSS HTTPS)
cat > /etc/systemd/system/ws-stunnel.service <<-END
[Unit]
Description=SSH Over Websocket-SSL (HTTPS port 443)
Documentation=https://google.com
After=network.target nss-lookup.target stunnel4.service

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/env python3 /usr/local/bin/ws-stunnel 700
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END

# Reload dan enable semua service
systemctl daemon-reload

systemctl enable ws-dropbear.service
systemctl stop ws-dropbear.service 2>/dev/null; sleep 1
systemctl start ws-dropbear.service

systemctl enable ws-stunnel.service
systemctl stop ws-stunnel.service 2>/dev/null; sleep 1
systemctl start ws-stunnel.service

# Cek status service
echo ""
echo "[ CHECK ] Service status:"
if systemctl is-active --quiet ws-dropbear.service; then
    echo "[ ok ] ws-dropbear (port 2095 internal) running"
else
    echo "[ FAIL ] ws-dropbear failed to start - checking logs..."
    journalctl -u ws-dropbear.service -n 5 --no-pager
fi

if systemctl is-active --quiet ws-stunnel.service; then
    echo "[ ok ] ws-stunnel (port 700 internal -> 443 via nginx) running"
else
    echo "[ FAIL ] ws-stunnel failed to start - checking logs..."
    journalctl -u ws-stunnel.service -n 5 --no-pager
fi

echo ""
echo "[ INFO ] SSH Websocket installation complete!"