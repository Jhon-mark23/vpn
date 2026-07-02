#!/bin/bash
# ============================================================
# MARCSCRIPT OPENVPN MANAGER MENU
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}===========================================${NC}"
echo -e "${BLUE}   🔐 MARCSCRIPT OPENVPN MANAGER${NC}"
echo -e "${CYAN}===========================================${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} Create VPN User"
echo -e "  ${GREEN}2.${NC} Trial VPN User (3 days)"
echo -e "  ${GREEN}3.${NC} Renew VPN User"
echo -e "  ${GREEN}4.${NC} Delete VPN User"
echo -e "  ${GREEN}5.${NC} List All Users"
echo -e "  ${GREEN}6.${NC} Check User Details"
echo -e "  ${GREEN}7.${NC} Show Connected Users"
echo -e "  ${GREEN}8.${NC} Restart OpenVPN"
echo -e "  ${GREEN}9.${NC} View OpenVPN Logs"
echo -e "  ${GREEN}10.${NC} Check Expired Users"
echo -e "  ${RED}0.${NC} Back to Main Menu"
echo ""
echo -e "${CYAN}===========================================${NC}"
read -p "Select option [0-10]: " opt

case $opt in
    1)
        clear
        bash /root/ovpn/create-user.sh
        ;;
    2)
        clear
        # Trial user for 3 days
        TRIAL_USER="trial$(date +%s | tail -c 5)"
        TRIAL_PASS="trial$(date +%s | tail -c 7)"
        echo "Creating trial user..."
        echo -e "$TRIAL_USER\n$TRIAL_PASS\n3" | bash /root/ovpn/create-user.sh
        ;;
    3)
        clear
        bash /root/ovpn/renew-user.sh
        ;;
    4)
        clear
        bash /root/ovpn/delete-user.sh
        ;;
    5)
        clear
        bash /root/ovpn/list-user.sh
        ;;
    6)
        clear
        echo "==========================================="
        echo "   🔍 USER DETAILS"
        echo "==========================================="
        read -p "Username: " user
        if [ -f "/etc/openvpn/client-configs/$user/$user.info" ]; then
            cat "/etc/openvpn/client-configs/$user/$user.info"
        else
            echo "User not found!"
        fi
        ;;
    7)
        clear
        echo "==========================================="
        echo "   📡 CONNECTED USERS"
        echo "==========================================="
        if [ -f /var/log/openvpn/openvpn-tcp-status.log ]; then
            echo "TCP Connections:"
            grep "CLIENT_LIST" /var/log/openvpn/openvpn-tcp-status.log 2>/dev/null | head -20
        fi
        if [ -f /var/log/openvpn/openvpn-udp-status.log ]; then
            echo ""
            echo "UDP Connections:"
            grep "CLIENT_LIST" /var/log/openvpn/openvpn-udp-status.log 2>/dev/null | head -20
        fi
        ;;
    8)
        clear
        echo "Restarting OpenVPN services..."
        systemctl restart openvpn@server-tcp openvpn@server-udp
        sleep 2
        if systemctl is-active --quiet openvpn@server-tcp; then
            echo -e "${GREEN}✅ TCP Server: Running${NC}"
        else
            echo -e "${RED}❌ TCP Server: Failed${NC}"
        fi
        if systemctl is-active --quiet openvpn@server-udp; then
            echo -e "${GREEN}✅ UDP Server: Running${NC}"
        else
            echo -e "${RED}❌ UDP Server: Failed${NC}"
        fi
        ;;
    9)
        clear
        echo "==========================================="
        echo "   📜 OPENVPN LOGS (TCP)"
        echo "==========================================="
        tail -f /var/log/openvpn/openvpn-tcp.log
        ;;
    10)
        clear
        bash /root/ovpn/check-expired.sh
        ;;
    0)
        menu
        ;;
    *)
        echo -e "${RED}Invalid option!${NC}"
        sleep 2
        bash /root/ovpn/menu-ovpn.sh
        ;;
esac

echo ""
read -p "Press enter to continue..."
bash /root/ovpn/menu-ovpn.sh
