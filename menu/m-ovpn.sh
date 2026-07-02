#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN3 MENU SHORTCUT
# Called from main menu option [06]
# Routes to OpenVPN3 management submenu
# ============================================================

# Colors matching main menu
purple='\033[0;35m'
cyan='\033[1;36m'
green='\033[0;32m'
red='\033[1;31m'
yellow='\033[1;33m'
white='\033[1;37m'
NC='\033[0m'

# ============================================================
# OPENVPN3 STATUS ENGINE
# ============================================================
check_ovpn_installed() {
    if systemctl is-active --quiet openvpn@server-tcp 2>/dev/null; then
        return 0
    elif [ -f /etc/openvpn/server-tcp.conf ]; then
        return 0
    elif [ -x /usr/local/bin/ovpncli ]; then
        return 0
    else
        return 1
    fi
}

check_ovpn_running() {
    if systemctl is-active --quiet openvpn@server-tcp 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================================================
# MAIN ROUTING
# ============================================================
if check_ovpn_installed; then
    # OpenVPN is installed - route to menu
    if [ -f /root/ovpn/menu-ovpn.sh ]; then
        bash /root/ovpn/menu-ovpn.sh
    elif [ -f /usr/local/bin/menu-ovpn ]; then
        bash /usr/local/bin/menu-ovpn
    elif command -v menu-ovpn &>/dev/null; then
        menu-ovpn
    else
        # Menu script missing but OpenVPN installed
        clear
        echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${purple}║${yellow}              🔐 OPENVPN3 - MENU MISSING                      ${purple}║${NC}"
        echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " OpenVPN3 is installed but the menu script is missing."
        echo ""
        echo -e " ${cyan}Quick Fix:${NC}"
        echo -e "  ${yellow}cd /root/ovpn && wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ovpn/menu-ovpn.sh${NC}"
        echo -e "  ${yellow}chmod +x menu-ovpn.sh && bash menu-ovpn.sh${NC}"
        echo ""
        echo -e " ${cyan}Manual Commands:${NC}"
        echo -e "  Create User : ${yellow}bash /root/ovpn/create-user.sh${NC}"
        echo -e "  List Users  : ${yellow}bash /root/ovpn/list-user.sh${NC}"
        echo ""
        
        # Show quick status
        if check_ovpn_running; then
            OVPN_TCP=$(grep "^port " /etc/openvpn/server-tcp.conf 2>/dev/null | awk '{print $2}')
            OVPN_UDP=$(grep "^port " /etc/openvpn/server-udp.conf 2>/dev/null | awk '{print $2}')
            OVPN_USERS=$(grep -c ":active" /etc/openvpn/client-configs/users.db 2>/dev/null || echo "0")
            echo -e " ${green}● OpenVPN3 Running${NC} | TCP:${OVPN_TCP:-1194} UDP:${OVPN_UDP:-2200} | Users: ${OVPN_USERS}"
        else
            echo -e " ${red}● OpenVPN3 Not Running${NC} | Check: systemctl start openvpn@server-tcp"
        fi
        echo ""
        read -p " Press enter to return to main menu..."
        menu
    fi
else
    # OpenVPN not installed - show installation options
    clear
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${yellow}              🔐 OPENVPN3 - NOT INSTALLED                     ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " ${cyan}📡 OpenVPN3 Features:${NC}"
    echo -e "  • TCP Port: ${green}1194${NC} (standard OpenVPN)"
    echo -e "  • UDP Port: ${green}2200${NC}"
    echo -e "  • Pre-compiled OpenVPN3 binary"
    echo -e "  • No port conflicts with SSH/Xray/Dropbear"
    echo -e "  • User management with expiration dates"
    echo -e "  • Auto-expiration check every hour"
    echo -e "  • Certificate revocation support"
    echo ""
    echo -e " ${cyan}📊 Service Compatibility:${NC}"
    echo -e "  SSH       : 22, 80, 2222    ${green}✓ No conflict${NC}"
    echo -e "  Dropbear  : 109, 143        ${green}✓ No conflict${NC}"
    echo -e "  Stunnel   : 443, 8443-8445  ${green}✓ No conflict${NC}"
    echo -e "  Xray      : 80, 443         ${green}✓ No conflict${NC}"
    echo -e "  WebSocket : 8080, 8082      ${green}✓ No conflict${NC}"
    echo -e "  Squid     : 3128, 8082, 8888 ${green}✓ No conflict${NC}"
    echo -e "  OpenVPN   : 1194, 2200      ${yellow}→ New ports${NC}"
    echo ""
    echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${cyan}⚡ Installation Options:${NC}"
    echo ""
    echo -e " ${green}[1]${NC} Quick Install (Recommended)"
    echo -e "     ${yellow}wget -qO- https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ovpn/install-ovpn.sh | bash${NC}"
    echo ""
    echo -e " ${green}[2]${NC} Manual Install"
    echo -e "     ${yellow}wget https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ovpn/install-ovpn.sh${NC}"
    echo -e "     ${yellow}bash install-ovpn.sh${NC}"
    echo ""
    echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p " Install OpenVPN3 now? [1=Quick / 2=Manual / n=Cancel]: " install_opt
    echo ""
    
    case $install_opt in
        1)
            echo -e " [ ${cyan}•${NC} ] Downloading and installing OpenVPN3..."
            wget -q -O /tmp/install-ovpn.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ovpn/install-ovpn.sh
            if [ $? -eq 0 ]; then
                chmod +x /tmp/install-ovpn.sh
                bash /tmp/install-ovpn.sh
                echo ""
                echo -e " [ ${green}✓${NC} ] Installation completed!"
                read -p " Press enter to continue..."
                menu
            else
                echo -e " [ ${red}✗${NC} ] Failed to download installer!"
                echo -e " Check your internet connection."
                sleep 3
                menu
            fi
            ;;
        2)
            echo -e " [ ${cyan}•${NC} ] Downloading installer for manual execution..."
            wget -q -O /root/install-ovpn.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/ovpn/install-ovpn.sh
            if [ $? -eq 0 ]; then
                chmod +x /root/install-ovpn.sh
                echo -e " [ ${green}✓${NC} ] Installer saved to /root/install-ovpn.sh"
                echo -e " Run: ${yellow}bash /root/install-ovpn.sh${NC}"
                echo ""
                read -p " Run installer now? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    bash /root/install-ovpn.sh
                    menu
                else
                    menu
                fi
            else
                echo -e " [ ${red}✗${NC} ] Download failed!"
                sleep 3
                menu
            fi
            ;;
        n|N|*)
            echo -e " ${yellow}Installation cancelled.${NC}"
            sleep 1
            menu
            ;;
    esac
fi