#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS"
clear
# SEARCH MENU
echo -e "\e[33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[0;100;33m       • SSH MENU •         \E[0m"
echo -e "\e[33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e ""
echo -e " [\e[36m•1\e[0m] Create SSH & WS Account "
echo -e " [\e[36m•2\e[0m] Trial SSH & WS Account "
echo -e " [\e[36m•3\e[0m] Renew SSH & WS Account "
echo -e " [\e[36m•4\e[0m] Delete SSH & WS Account "
echo -e " [\e[36m•5\e[0m] Check User Login SSH & WS "
echo -e " [\e[36m•6\e[0m] List Member SSH & OpenVPN "
echo -e " [\e[36m•7\e[0m] Delete Expired SSH & WS Users "
echo -e " [\e[36m•8\e[0m] Set up Autokill SSH "
echo -e " [\e[36m•9\e[0m] Check Users with Multi Login "
echo -e " [\e[36m•10\e[0m] List of Created Accounts "
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
1) clear ; usernew ; exit ;;
2) clear ; trial ; exit ;;
3) clear ; renew ; exit ;;
4) clear ; hapus ; exit ;;
5) clear ; cek ; exit ;;
6) clear ; member ; exit ;;
7) clear ; delete ; exit ;;
8) clear ; autokill ; exit ;;
9) clear ; ceklim ; exit ;;
10) clear ; cat /etc/log-create-ssh.log ; exit ;;
0) clear ; menu ; exit ;;
x) exit ;;
*) echo "You pressed wrong key " ; sleep 1 ; m-sshovpn ;;
esac