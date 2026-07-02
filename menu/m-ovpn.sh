#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN MENU SHORTCUT
# ============================================================

# Colors matching main menu
purple='\033[0;35m'
cyan='\033[1;36m'
green='\033[0;32m'
red='\033[1;31m'
yellow='\033[1;33m'
NC='\033[0m'

# Check if OpenVPN is installed
if [ -f /root/ovpn/menu-ovpn.sh ]; then
    bash /root/ovpn/menu-ovpn.sh
elif [ -f /usr/local/bin/menu-ovpn ]; then
    bash /usr/local/bin/menu-ovpn
else
    clear
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${NC}              ${red}⚠ OPENVPN NOT INSTALLED ⚠${NC}                  ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " OpenVPN is not detected on this system."
    echo ""
    echo -e " ${green}Quick Install:${NC}"
    echo -e "  wget -qO- https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ovpn/install-ovpn.sh | bash"
    echo ""
    read -p " Install OpenVPN now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        wget -q -O /tmp/install-ovpn.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/main/ovpn/install-ovpn.sh
        bash /tmp/install-ovpn.sh
    fi
fi