# 🚀 AUTO INSTALL SCRIPT SSH & XRAY MULTIPORT

**Creadted by:** marc

---

## 📢 NOTICE

Please read thoroughly before starting the installation!

---

## 💻 OS SUPPORT & SPECIFICATIONS

<p align="center">

  <img src="https://companieslogo.com/img/orig/debian_BIG-7a652e6a.png?t=1720244494" alt="Debian Logo" width="180"/> 
  <img src="https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png" alt="Ubuntu Logo" width="180"/>
  <br/>
  <img src="https://img.shields.io/badge/Ubuntu-26%20-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <br/>
  <img src="https://img.shields.io/badge/Debian-13%20-A81D33?style=for-the-badge&logo=debian&logoColor=white"/>
</p>

- ⚡ **CPU:** Minimum 1 Core
- 🧠 **RAM:** Minimum 1GB
- 🌐 **Domain:** Must Point to VPS IP
- ## 🛠️ INSTALLATION

Login to your VPS as **root**, then run:

```bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 && apt update && apt install -y bzip2 gzip coreutils screen curl unzip && wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh && chmod +x setup.sh && sed -i -e 's/\r$//' setup.sh && screen -S setup ./setup.sh
```

----
## 📊 COMPLETE SERVICE & PORT LIST

### SSH & VPN Services (Direct / SSL / WebSocket)

| Service | Port(s) | Description |
|---------|---------|-------------|
| 🔑 OpenSSH | 22, 2222 | Direct SSH with legacy algorithm support |
| 🛡️ Dropbear | 109, 143 | Lightweight SSH daemon |
| 🔒 Stunnel4 (SSL) | 8443, 8444 | SSH wrapped in TLS (max compatibility) |
| 🌐 SSH WebSocket (WS) | 8080, 8082 | SSH over WebSocket (Node.js proxy) |
| 🔐 SSH WebSocket SSL (WSS) | 8445 | WebSocket over TLS (Stunnel → WS proxy) |
| 🐙 Squid Proxy | 3128, 8082, 8888 | HTTP proxy for payload manipulation |
| 🎮 BADVPN UDPGW | 7100–7400 | UDP gateway for games / VoIP |

### Xray Services (Nginx reverse proxy)

| Protocol | Transport | TLS Port | Non‑TLS Port | Path / Service Name |
|----------|-----------|----------|--------------|---------------------|
| 🚀 VMess | WebSocket | 443 | 80 | `/vmess` |
| 🚀 VMess | gRPC | 443 | — | `vmess-grpc` |
| 🚀 VLess | WebSocket | 443 | 80 | `/vless` |
| 🚀 VLess | gRPC | 443 | — | `vless-grpc` |
| 🚀 Trojan | WebSocket | 443 | 80 | `/trojan-ws` |
| 🚀 Trojan | gRPC | 443 | — | `trojan-grpc` |
| 🚀 Shadowsocks | WebSocket | 443 | 80 | `/ss-ws` |
| 🚀 Shadowsocks | gRPC | 443 | — | `ss-grpc` |


