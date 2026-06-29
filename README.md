

🚀 AUTO INSTALL SCRIPT SSH & XRAY MULTIPORT

Base Script by: eddyme23
Modified by: marc

---

📢 NOTICE

Please read thoroughly before starting the installation!

---

💻 OS SUPPORT & SPECIFICATIONS

<p align="center">

  <img src="https://companieslogo.com/img/orig/debian_BIG-7a652e6a.png?t=1720244494" alt="Debian Logo" width="180"/> 
  <img src="https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png" alt="Ubuntu Logo" width="180"/>
  <br/>
  <img src="https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <img src="https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <br/>
  <img src="https://img.shields.io/badge/Debian-11%20Bullseye-A81D33?style=for-the-badge&logo=debian&logoColor=white"/>
  <img src="https://img.shields.io/badge/Debian-12%20Bookworm-A81D33?style=for-the-badge&logo=debian&logoColor=white"/>
</p>

⚡ CPU: Minimum 1 Core
🧠 RAM: Minimum 1GB
🌐 Domain: Must Point to VPS IP

CLOUDFLARE DOMAIN SETTINGS

· SSL/TLS : FULL
· SSL/TLS Recommender : OFF
· GRPC : ON
· WEBSOCKET : ON
· Always Use HTTPS : OFF
· UNDER ATTACK MODE : OFF

---

📊 COMPLETE SERVICE & PORT LIST

Service Name Port / Protocol
🔑 OpenSSH 22, 9696
🛡️ Dropbear 109, 143
🔒 Stunnel4 (SSL) 222, 777
🌐 SSH WS (HTTP) 80
🔐 SSH WSS (HTTPS) 443
🚀 Xray Vmess WS 80 (None TLS) / 443 (TLS)
🚀 Xray Vless WS 80 (None TLS) / 443 (TLS)
🚀 Xray Trojan WS 80 (None TLS) / 443 (TLS)
🚀 Xray Shadowsocks WS 80 (None TLS) / 443 (TLS)
🧬 Xray Vmess gRPC 443
🧬 Xray Vless gRPC 443
🧬 Xray Trojan gRPC 443
🧬 Xray Shadowsocks gRPC 443
⚙️ Nginx 81
🎮 Badvpn UDPGW 7100 - 7400

---

🛠️ INSTALLATION (BASH SCRIPT)

Login to your VPS as root (sudo su), then copy and run the following command:

```bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 && apt update && apt install -y bzip2 gzip coreutils screen curl unzip && wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh && chmod +x setup.sh && sed -i -e 's/\r$//' setup.sh && screen -S setup ./setup.sh
```

✅ You can copy the code above by clicking the copy icon in the top-right corner of the code block.

---

✨ MAIN FEATURES

· 💨 VPS Speedtest by Ookla
· 🔄 Auto Reboot & Restart All Services
· 🧹 Auto Delete Expired Users
· 📊 Bandwidth & Service Monitoring
· 🚀 BBRPLUS v1.4.0 (Speed Optimization)
· 🌐 DNS Changer

---

🔧 COMPATIBILITY UPDATE

✅ Now supports:

· Ubuntu 22.04 LTS
· Ubuntu 24.04 LTS
· Debian 11 (Bullseye)
· Debian 12 (Bookworm)

---

📝 CHANGELOG

Date Update
2026-06-29 Added Debian 11 & 12 support
2026-06-29 Philippines timezone (Asia/Manila)
2026-06-29 Full English translation
2026-06-29 Improved SSL certificate handling for Debian

---

© 2026 Marc - MARCSCRIPT