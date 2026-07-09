#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com)
echo "Checking VPS..."
clear

echo "=========================================="
echo "          VLESS MENU                      "
echo "=========================================="
echo ""
echo "[1] Create Account Vless"
echo "[2] Trial Account Vless"
echo "[3] Extending Account Vless"
echo "[4] Delete Account Vless"
echo "[5] Check User Login Vless"
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
1) clear; add-vless ;;
2) clear; trialvless ;;
3) clear; renew-vless ;;
4) clear; del-vless ;;
5) clear; cek-vless ;;
6) clear; cat /etc/log-create-vless.log ;;
0) clear; menu ;;
x|X) exit ;;
*) echo -e "\nInvalid selection!"; sleep 1; m-sshovpn ;;
esac