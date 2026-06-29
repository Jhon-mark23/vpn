#!/bin/bash
# ==================================================
# SSH-VPN Install Script - Compatible with Debian & Ubuntu
# Optimized for 1GB RAM / 1 CPU VPS
# ==================================================

# Suppress all interactive apt dialogs
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo "Cannot detect OS. Exiting..."
        exit 1
    fi
    
    echo -e "[ INFO ] Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo -e "[ ERROR ] This script only supports Ubuntu or Debian"
        exit 1
    fi
}

detect_os

# Disable popups "Pending kernel upgrade" and "Daemons using outdated libraries"
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null || true
    sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf 2>/dev/null || true
fi

apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt install netfilter-persistent -y
apt-get remove --purge ufw firewalld -y
apt install -y screen curl jq bzip2 gzip vnstat coreutils rsyslog iftop zip unzip git apt-transport-https build-essential -y

# Initializing variables
MYIP=$(wget -qO- ipv4.icanhazip.com)
MYIP2="s/xxxxxxxxx/$MYIP/g"
NET=$(ip -o $ANU -4 route show to default | awk '{print $5}')
source /etc/os-release
ver=$VERSION_ID

# Company details (Philippines)
country=PH
state="Metro Manila"
locality=Manila
organization=none
organizationalunit=none
commonname=none
email=none

# Simple password minimal
curl -sS https://raw.githubusercontent.com/fahrialimudin/xray/main/ssh/password | openssl aes-256-cbc -d -a -pass pass:scvps07gg -pbkdf2 > /etc/pam.d/common-password
chmod +x /etc/pam.d/common-password

cd

# Edit file /etc/systemd/system/rc-local.service
cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
END

cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
# By default this script does nothing.
exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local
systemctl start rc-local.service

# Disable IPv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

# Update
apt update -y
apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get remove --purge ufw firewalld -y
apt-get remove --purge exim4 -y

apt -y install jq
apt -y install wget curl
apt -y install net-tools

# Set time to Philippines (GMT +8)
ln -fs /usr/share/zoneinfo/Asia/Manila /etc/localtime

# Set locale
sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config

install_ssl(){
    # Fix: Different certbot package names for Debian/Ubuntu
    if [[ "$OS" == "ubuntu" ]]; then
        apt-get install -y nginx certbot python3-certbot-nginx
    elif [[ "$OS" == "debian" ]]; then
        apt-get install -y nginx certbot python3-certbot-nginx
        # Debian might need certbot from backports or snap
        if [ $? -ne 0 ]; then
            apt-get install -y certbot python3-certbot-nginx -t bullseye-backports 2>/dev/null || \
            apt-get install -y certbot python3-certbot-nginx -t bookworm-backports 2>/dev/null || \
            apt-get install -y certbot -y
        fi
    fi
    sleep 3s
    systemctl stop nginx.service
    echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
    sleep 3s
}

# Install web server
apt -y install nginx
cd
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
wget -O /etc/nginx/nginx.conf "https://raw.githubusercontent.com/fahrialimudin/xray/main/ssh/nginx.conf"
mkdir -p /home/vps/public_html
mkdir -p /etc/nginx/conf.d

# ============================================================
# NGINX OPTIMIZATION - Reduce worker & connections to save RAM
# ============================================================
sed -i 's/worker_processes\s*auto/worker_processes 1/' /etc/nginx/nginx.conf
sed -i 's/worker_processes\s*[0-9]*/worker_processes 1/' /etc/nginx/nginx.conf

# Create temporary nginx config so nginx can start before ins-xray.sh
cat > /etc/nginx/conf.d/xray.conf <<-NGINXTMP
server {
    listen 81;
    server_name _;
    root /home/vps/public_html;
    index index.html;
}
server {
    listen 80 default_server;
    server_name _;
    root /home/vps/public_html;
    location / {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
NGINXTMP
systemctl restart nginx

# ============================================================
# INSTALL BADVPN - OPTIMIZED: max-clients 50 per instance
# ============================================================
cd
wget -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/fahrialimudin/xray/main/ssh/newudpgw"
chmod +x /usr/bin/badvpn-udpgw

sed -i '$ i\screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50' /etc/rc.local
sed -i '$ i\screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50' /etc/rc.local
sed -i '$ i\screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50' /etc/rc.local
sed -i '$ i\screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50' /etc/rc.local

screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50
screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50
screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50
screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50

cd
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i '/^Port [0-9]/d' /etc/ssh/sshd_config
echo "Port 22" >> /etc/ssh/sshd_config
echo "Port 9696" >> /etc/ssh/sshd_config
systemctl restart ssh

echo "=== Install Dropbear ==="
apt -y install dropbear
cat > /etc/default/dropbear <<-DROPBEAR
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 143"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR
systemctl enable dropbear
echo "/bin/false" >> /etc/shells
echo "/usr/sbin/nologin" >> /etc/shells
systemctl restart ssh
systemctl restart dropbear

# ============================================================
# INSTALL STUNNEL4 - FIXED FOR BOTH OS
# ============================================================
cd
echo "=== Install Stunnel4 ==="
apt install stunnel4 -y

mkdir -p /var/log/stunnel4
mkdir -p /etc/stunnel
mkdir -p /var/run/stunnel4

# Fix: Different user handling for Debian/Ubuntu
if ! id "stunnel4" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin stunnel4 2>/dev/null || true
fi

chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null || chown root:root /var/log/stunnel4
chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || chown root:root /var/run/stunnel4
chmod 755 /var/run/stunnel4

# Generate SSL certificate for stunnel
cd /tmp
openssl genrsa -out /tmp/stunnel-key.pem 2048 2>/dev/null
openssl req -new -x509 \
    -key /tmp/stunnel-key.pem \
    -out /tmp/stunnel-cert.pem \
    -days 3650 \
    -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email" \
    2>/dev/null
cat /tmp/stunnel-key.pem /tmp/stunnel-cert.pem > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null || true
rm -f /tmp/stunnel-key.pem /tmp/stunnel-cert.pem
cd

cat > /etc/stunnel/stunnel.conf <<-END
; Stunnel4 Config - Debian/Ubuntu Compatible
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
output = /var/log/stunnel4/stunnel.log
pid = /var/run/stunnel4/stunnel4.pid

[ssh-ssl]
accept = 222
connect = 127.0.0.1:22

[dropbear-ssl]
accept = 777
connect = 127.0.0.1:109

[ws-stunnel]
accept = 2096
connect = 127.0.0.1:700
END

cat > /etc/default/stunnel4 <<-STUNNEL
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
BANNER="/etc/issue.net"
PPP_RESTART=0
OUTPUT=/var/log/stunnel4/stunnel.log
STUNNEL

# Fix systemd for both OS
mkdir -p /etc/systemd/system/stunnel4.service.d/
cat > /etc/systemd/system/stunnel4.service.d/override.conf <<-EOF
[Service]
RuntimeDirectory=stunnel4
RuntimeDirectoryMode=0755
ExecStartPre=/bin/mkdir -p /var/run/stunnel4
ExecStartPre=/bin/chown stunnel4:stunnel4 /var/run/stunnel4
EOF

systemctl daemon-reload
systemctl enable stunnel4
systemctl stop stunnel4 2>/dev/null; sleep 1
systemctl start stunnel4

# ============================================================
# INSTALL FAIL2BAN - OPTIMIZED
# ============================================================
apt -y install fail2ban

mkdir -p /etc/fail2ban
cat > /etc/fail2ban/jail.local <<-F2B
[DEFAULT]
findtime  = 600
bantime   = 3600
maxretry  = 5
backend   = polling

[sshd]
enabled   = true
port      = ssh,9696,222,777
logpath   = %(sshd_log)s
maxretry  = 5
F2B

systemctl enable fail2ban
systemctl enable nginx
systemctl enable cron
systemctl enable vnstat

# ============================================================
# KERNEL SYSCTL OPTIMIZATION
# ============================================================
cat >> /etc/sysctl.conf <<-SYSCTL

# === VPS 1GB RAM OPTIMIZATION ===
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 51200
SYSCTL
sysctl -p >/dev/null 2>&1

# ============================================================
# ADD 512MB SWAP
# ============================================================
if [ ! -f /swapfile ]; then
    # Fix: Use dd instead of fallocate for older Debian
    if command -v fallocate &> /dev/null; then
        fallocate -l 512M /swapfile
    else
        dd if=/dev/zero of=/swapfile bs=1M count=512 status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "[ ok ] Swap 512MB created"
fi

# Block torrent traffic
iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP
iptables -A FORWARD -m string --algo bm --string "torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce" -j DROP
iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# Download menu scripts from GitHub
GHBASE="https://raw.githubusercontent.com/fahrialimudin/xray/main"

cd /usr/bin
wget -O menu        "$GHBASE/menu/menu.sh"
wget -O m-vmess     "$GHBASE/menu/m-vmess.sh"
wget -O m-vless     "$GHBASE/menu/m-vless.sh"
wget -O running     "$GHBASE/menu/running.sh"
wget -O clearcache  "$GHBASE/menu/clearcache.sh"
wget -O m-ssws      "$GHBASE/menu/m-ssws.sh"
wget -O m-trojan    "$GHBASE/menu/m-trojan.sh"
wget -O m-sshovpn   "$GHBASE/menu/m-sshovpn.sh"
wget -O usernew     "$GHBASE/ssh/usernew.sh"
wget -O trial       "$GHBASE/ssh/trial.sh"
wget -O renew       "$GHBASE/ssh/renew.sh"
wget -O hapus       "$GHBASE/ssh/hapus.sh"
wget -O cek         "$GHBASE/ssh/cek.sh"
wget -O member      "$GHBASE/ssh/member.sh"
wget -O delete      "$GHBASE/ssh/delete.sh"
wget -O autokill    "$GHBASE/ssh/autokill.sh"
wget -O ceklim      "$GHBASE/ssh/ceklim.sh"
wget -O tendang     "$GHBASE/ssh/tendang.sh"
wget -O sshws       "$GHBASE/ssh/sshws.sh"
wget -O m-system    "$GHBASE/menu/m-system.sh"
wget -O m-domain    "$GHBASE/menu/m-domain.sh"
wget -O add-host    "$GHBASE/ssh/add-host.sh"
wget -O certv2ray   "$GHBASE/xray/certv2ray.sh"
wget -O speedtest   "$GHBASE/ssh/speedtest_cli.py"
wget -O auto-reboot "$GHBASE/menu/auto-reboot.sh"
wget -O restart     "$GHBASE/menu/restart.sh"
wget -O bw          "$GHBASE/menu/bw.sh"
wget -O m-tcp       "$GHBASE/menu/tcp.sh"
wget -O xp          "$GHBASE/ssh/xp.sh"
wget -O m-dns       "$GHBASE/menu/m-dns.sh"
wget -O fix-cek     "$GHBASE/ssh/fix-cek.sh"

chmod +x menu m-vmess m-vless running clearcache m-ssws m-trojan
chmod +x m-sshovpn usernew trial renew hapus cek member delete autokill ceklim tendang sshws
chmod +x m-system m-domain add-host certv2ray speedtest auto-reboot restart bw m-tcp xp m-dns fix-cek
cd

cat > /etc/cron.d/re_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
END

cat > /etc/cron.d/xp_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
END

cat > /home/re_otm <<-END
7
END

systemctl restart cron >/dev/null 2>&1
systemctl reload cron >/dev/null 2>&1

echo "[ INFO ] Clearing trash"
apt autoclean -y >/dev/null 2>&1
if dpkg -s unscd >/dev/null 2>&1; then
    apt -y remove --purge unscd >/dev/null 2>&1
fi
apt-get -y --purge remove samba* >/dev/null 2>&1
apt-get -y --purge remove apache2* >/dev/null 2>&1
apt-get -y --purge remove bind9* >/dev/null 2>&1
apt-get -y remove sendmail* >/dev/null 2>&1
apt autoremove -y >/dev/null 2>&1

cd
chown -R www-data:www-data /home/vps/public_html
echo "[SERVICE] Restart All services"
systemctl restart nginx >/dev/null 2>&1; echo "[ ok ] Restarting nginx"
systemctl restart cron >/dev/null 2>&1; echo "[ ok ] Restarting cron"
systemctl restart ssh >/dev/null 2>&1; echo "[ ok ] Restarting ssh"
systemctl restart dropbear >/dev/null 2>&1; echo "[ ok ] Restarting dropbear"
systemctl restart fail2ban >/dev/null 2>&1; echo "[ ok ] Restarting fail2ban"
systemctl restart stunnel4 >/dev/null 2>&1; echo "[ ok ] Restarting stunnel4"
systemctl restart vnstat >/dev/null 2>&1; echo "[ ok ] Restarting vnstat"

screen -dmS badvpn1 badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 50
screen -dmS badvpn2 badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 50
screen -dmS badvpn3 badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 50
screen -dmS badvpn4 badvpn-udpgw --listen-addr 127.0.0.1:7400 --max-clients 50

history -c
echo "unset HISTFILE" >> /etc/profile

rm -f /root/key.pem
rm -f /root/cert.pem
rm -f /root/ssh-vpn.sh
rm -f /root/bbr.sh

clear