#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - EXPIRED ACCOUNT PURGE & MONITOR
# ============================================================

MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS..."
clear

# ---------- COLOURS ----------
purple='\033[0;35m'
blue='\033[0;34m'
green='\033[0;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
red='\033[1;31m'
white='\033[1;37m'
NC='\033[0m'

hariini=$(date +%d-%m-%Y)
todaystime=$(date +%s)

# Banner Implementation
echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${purple}║${white}     ███╗   ███╗ █████╗ ██████╗  ██████╗███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔════╝${purple}║${NC}"
echo -e "${purple}║${white}     ██╔████╔██║███████║██████╔╝██║     ███████╗${purple}║${NC}"
echo -e "${purple}║${white}     ██║╚██╔╝██║██╔══██║██╔══██╗██║     ╚════██║${purple}║${NC}"
echo -e "${purple}║${white}     ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗███████║${purple}║${NC}"
echo -e "${purple}║${white}     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝${purple}║${NC}"
echo -e "${purple}║${cyan}                   • USER MONITOR & AUTO-CLEAN •               ${purple}║${NC}"
echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# SECTION 1: LIST EXISTING SSH USERS
# ============================================================
echo -e "${cyan} [📡] CURRENT SSH VPN USER DATABASE:${NC}"
echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "${white}%-18s %-22s %-15s${NC}\n" "  Username" "Expiry Date" "Status"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"

# Parse standard users filtering out system accounts
cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/userlist.txt
while IFS=: read -r user days; do
    [ -z "$user" ] && continue
    
    # Calculate Date
    sec=$(( days * 86400 ))
    exp_date=$(date -d @$sec +"%b %d, %Y" 2>/dev/null || echo "No Expiry")
    
    if [ "$sec" -lt "$todaystime" ]; then
        status_msg="${red}Expired${NC}"
    else
        status_msg="${green}Active${NC}"
    fi
    
    printf "  %-16s %-22s %-15s\n" "$user" "$exp_date" "$status_msg"
done < /tmp/userlist.txt

echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================================
# SECTION 2: AUTO-PURGE EXPIRED ACCOUNTS
# ============================================================
echo -e "${yellow} [⚙️] PROCESSING AUTO-PURGE SEQUENCE...${NC}"
echo -e "${purple}──────────────────────────────────────────────────────────────${NC}"

cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/expirelist.txt
totalaccounts=$(cat /tmp/expirelist.txt | wc -l)
deleted_count=0

for ((i=1; i<=$totalaccounts; i++))
do
    tuserval=$(head -n $i /tmp/expirelist.txt | tail -n 1)
    raw_username=$(echo "$tuserval" | cut -f1 -d:)
    username=$(echo "$raw_username" | tr -d '[:space:]') # Clean layout spaces
    userexp=$(echo "$tuserval" | cut -f2 -d:)
    userexpireinseconds=$(( userexp * 86400 ))
    
    tglexp=$(date -d @$userexpireinseconds 2>/dev/null)             
    tgl=$(echo "$tglexp" | awk '{print $3}')
    [ ${#tgl} -lt 2 ] && tgl="0$tgl"
    
    bulantahun=$(echo "$tglexp" | awk '{print $2,$6}')
    
    # Check if expired
    if [ $userexpireinseconds -lt $todaystime ]; then
        echo "Expired- Username : $username expired at: $tgl $bulantahun and removed : $hariini" >> /usr/local/bin/deleteduser
        echo -e " ${red}✗${NC} User ${red}$username${NC} ($tgl $bulantahun) has been removed."
        userdel -f "$username" 2>/dev/null
        ((deleted_count++))
    fi
done

if [ "$deleted_count" -eq 0 ]; then
    echo -e " ${green}✓${NC} System is clean! No expired users found."
else
    echo -e " ${green}✓${NC} Successfully cleaned up ${yellow}$deleted_count${NC} expired user(s)."
fi

echo -e "${purple}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

rm -f /tmp/expirelist.txt /tmp/userlist.txt
read -n 1 -s -r -p "Press any key to return to system menu..."
menu
