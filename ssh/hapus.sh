#!/bin/bash
MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS"
clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[0;41;36m               DELETE USER                \E[0m"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
read -p "Username SSH to Delete : " Pengguna

# Validasi input tidak kosong
if [[ -z "$Pengguna" ]]; then
    echo -e "Failure: Username cannot be empty."
    read -n 1 -s -r -p "Press any key to back on menu"
    menu
    exit
fi

if getent passwd "$Pengguna" > /dev/null 2>&1; then
    # Kill semua proses aktif milik user (agar userdel tidak gagal saat user sedang login)
    echo -e "Terminating active sessions for $Pengguna..."
    pkill -KILL -u "$Pengguna" > /dev/null 2>&1
    sleep 1

    # Hapus user dengan flag -f (force) agar tetap berhasil meski ada proses tersisa
    userdel -f "$Pengguna" > /dev/null 2>&1

    # Verifikasi apakah user benar-benar sudah terhapus
    if ! getent passwd "$Pengguna" > /dev/null 2>&1; then
        echo -e "Success: User \e[32m$Pengguna\e[0m has been removed."
    else
        echo -e "Failure: Could not remove user \e[31m$Pengguna\e[0m. Please try again."
    fi
else
    echo -e "Failure: User \e[31m$Pengguna\e[0m does not exist."
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
