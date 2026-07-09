#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

echo "=========================================="
echo "          VMESS MENU                      "
echo "=========================================="
echo ""
echo "[1] Create Account Vmess"
echo "[2] Trial Account Vmess"
echo "[3] Extending Account Vmess"
echo "[4] Delete Account Vmess"
echo "[5] Check User Login Vmess"
echo "[6] User List Created Account"
echo ""
echo "[0] Back to Menu"
echo ""
echo "Press x or Ctrl+C to Exit"
echo ""
echo "=========================================="
echo ""

read -p "Select menu: " opt

case $opt in
1) clear; add-ws ;;
2) clear; trialvmess ;;
3) clear; renew-ws ;;
4) clear; del-ws ;;
5) clear; cek-ws ;;
6) clear; cat /etc/log-create-vmess.log ;;
0) clear; menu ;;
x|X) exit ;;
*) echo -e "\nInvalid selection!"; sleep 1; m-sshovpn ;;
esac