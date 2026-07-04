#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS"
clear
echo -e "\e[33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[0;100;33m       • XRAY MENU •         \E[0m"
echo -e "\e[33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e ""
echo -e " [\e[36m•1\e[0m] VLESS MENU "
echo -e " [\e[36m•2\e[0m] VLESS MENU "
echo -e ""
echo -e " [\e[31m•0\e[0m] \e[31mBACK TO MENU\033[0m"
echo -e ""
echo -e   "Press x or [ Ctrl+C ] • To-Exit"
echo ""
echo -e "\e[33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e ""
read -p " Select menu :  "  opt
echo -e ""
case $opt in
1) clear ; m-vless ; exit ;;
2) clear ; m-vmess  ; exit ;;
0) clear ; menu ; exit ;;
x) exit ;;
*) echo ") salah tekan " ; sleep 1 ; m-xray ;;
esac
