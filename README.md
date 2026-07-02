<div align="center">

# 🚀 MARCSCRIPT SSH & XRAY MULTIPORT 🚀

<img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&size=26&pause=1000&color=00E5FF&center=true&vCenter=true&width=700&lines=SSH+%2B+SSL;SSH+%2B+WebSocket;SSH+%2B+WS+SSL;VMESS+%7C+VLESS+%7C+TROJAN+%7C+SHADOWSOCKS;Fast+%7C+Secure+%7C+Stable"/>

<p>

![OS](https://img.shields.io/badge/Linux-Ubuntu%2026.04-orange?style=for-the-badge&logo=ubuntu)
![OS](https://img.shields.io/badge/Linux-Debian%2013-red?style=for-the-badge&logo=debian)
![Version](https://img.shields.io/badge/Version-v2.0-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Stable-brightgreen?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-success?style=for-the-badge)

</p>

### ⚡ One Command Installation • SSH • XRAY • WEBSOCKET • SSL • GRPC

Created with ❤️ by **Marc**

</div>

---

# 📢 NOTICE

> Please read the documentation carefully before installing.

---

# 💻 SYSTEM REQUIREMENTS

| Item | Minimum |
|------|----------|
| 🖥 CPU | 1 Core |
| 🧠 RAM | 1 GB |
| 💾 Storage | 10 GB |
| 🌐 Domain | Pointed to VPS IP |
| 👤 User | root |

---

# 🖥 SUPPORTED OS

<div align="center">

<img src="https://companieslogo.com/img/orig/debian_BIG-7a652e6a.png?t=1720244494" width="170">
&nbsp;&nbsp;&nbsp;
<img src="https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png" width="170">

</div>

---

# ⚡ INSTALLATION

Login as **root**

```bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && \
sysctl -w net.ipv6.conf.default.disable_ipv6=1 && \
apt update && \
apt install -y bzip2 gzip coreutils screen curl unzip && \
wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh && \
chmod +x setup.sh && \
sed -i 's/\r$//' setup.sh && \
screen -S setup ./setup.sh && \
clear && rm setup.sh
```

---

# 🌐 SSH SERVICES

| Service | Port |
|---------|------|
| 🔑 OpenSSH | 22 |
| 🔒 SSH + SSL | 8443,8444 |
| 🌐 SSH + WS | 8080,8082 |
| 🔐 SSH + WS + SSL | 8445 |
| 🎮 BadVPN UDPGW | 7100-7400 |

---

# 🚀 XRAY SERVICES

| Protocol | TLS | Non TLS | Path |
|----------|-----|----------|------|
| VMess WS | 443 | 80 | `/vmess` |
| VMess gRPC | 443 | — | `vmess-grpc` |
| VLESS WS | 443 | 80 | `/vless` |
| VLESS gRPC | 443 | — | `vless-grpc` |
| Trojan WS | 443 | 80 | `/trojan-ws` |
| Trojan gRPC | 443 | — | `trojan-grpc` |
| Shadowsocks WS | 443 | 80 | `/ss-ws` |
| Shadowsocks gRPC | 443 | — | `ss-grpc` |

---

# ⭐ FEATURES

- OpenSSH
- Stunnel4 SSL
- SSH WebSocket
- SSH WS SSL
- Xray-Core
- VMess
- VLESS
- Trojan
- Shadowsocks
- gRPC Support
- WebSocket Support
- Nginx Reverse Proxy
- Automatic SSL Certificate
- Auto Restart Services
- Auto Backup
- Auto Renew SSL

---


---

<div align="center">

## 🚀 MARCSCRIPT VPN

### Fast ⚡ Stable 🚀 Secure 🔒

⭐ Don't forget to **Star** this repository if it helps you.

</div>