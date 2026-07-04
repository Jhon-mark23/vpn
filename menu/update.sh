#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - UPDATE MANAGER
# ============================================================

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

# ---------- CONFIGURATION ----------
GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-update.log"

# ---------- FUNCTIONS ----------

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Success message
success_msg() {
    echo -e "${green}✓ $1${NC}"
    log "SUCCESS: $1"
}

# Error message
error_msg() {
    echo -e "${red}✗ $1${NC}"
    log "ERROR: $1"
}

# Download function (based on your working pattern)
dl() {
    local dest="/usr/bin/$1"
    local url="$GHBASE/$2"
    echo -e "${cyan}Downloading: $1${NC}"
    
    wget -q --show-progress -O "$dest" "$url" 2>&1
    if [ $? -eq 0 ]; then
        chmod +x "$dest"
        sed -i 's/\r$//' "$dest" 2>/dev/null
        success_msg "Installed: $1"
        return 0
    else
        error_msg "Failed to download: $1"
        return 1
    fi
}

# Create backup
create_backup() {
    echo -e "${yellow}Creating backup...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important files
    [ -f "/etc/passwd" ] && cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/shadow" ] && cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
    [ -f "/root/domain.txt" ] && cp /root/domain.txt "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/bin" ] && cp -r /usr/bin/menu "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/bin" ] && cp -r /usr/bin/ssh "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/bin" ] && cp -r /usr/bin/xray "$BACKUP_DIR/" 2>/dev/null
    
    success_msg "Backup created at: $BACKUP_DIR"
}

# ---------- UPDATE FUNCTIONS ----------

# Update ALL services
update_all() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}         🔄 UPDATING ALL SERVICES & MENU FILES               ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "This will update ALL services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    update_menu
    update_ssh
    update_xray
    update_dnstt
    update_sshws
    
    # Restart services
    echo -e "${cyan}Restarting services...${NC}"
    systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
    systemctl restart ssh 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    systemctl restart ws-dropbear 2>/dev/null
    systemctl restart ws-stunnel 2>/dev/null
    
    success_msg "All services updated successfully!"
    echo ""
}

# Update Menu only
update_menu() {
    echo -e "Downloading management scripts..."
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    
    rm -rf /usr/bin/menu

    dl() {
        wget -q -O "$1" "$GHBASE/$2" && chmod +x "$1" && sed -i 's/\r$//' "$1"
    }

    dl menu menu/menu.sh
    dl m-xray menu/m-xray.sh
    dl m-sshovpn menu/m-sshovpn.sh
    dl m-vmess menu/m-vmess.sh
    dl m-vless menu/m-vless.sh
    dl m-trojan menu/m-trojan.sh
    dl m-ssws menu/m-ssws.sh
    dl m-system menu/m-system.sh
    dl running menu/running.sh
    dl clearcache menu/clearcache.sh

    dl usernew ssh/usernew.sh
    dl trial ssh/trial.sh
    dl renew ssh/renew.sh
    dl hapus ssh/hapus.sh
    dl cek ssh/cek.sh
    dl member ssh/member.sh
    dl delete ssh/delete.sh
    dl autokill ssh/autokill.sh
    dl ceklim ssh/ceklim.sh
    dl tendang ssh/tendang.sh
    dl sshws ssh/sshws.sh
    dl add-host ssh/add-host.sh
    dl xp ssh/xp.sh
    dl speedtest ssh/speedtest_cli.py

    cd /
    echo -e "${purple}Management scripts downloaded (line endings fixed)"
}

# Update SSH only
update_ssh() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 UPDATING SSH SERVICES                        ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "This will update SSH services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Remove old ssh files
    echo -e "${yellow}Removing old ssh files...${NC}"
    rm -rf /usr/bin/ssh 2>/dev/null
    mkdir -p /usr/bin/ssh
    success_msg "Old ssh files removed"
    
    # Download SSH scripts
    echo -e "${cyan}Downloading SSH scripts...${NC}"
    cd /usr/bin || return
    
    dl usernew ssh/usernew.sh
    dl trial ssh/trial.sh
    dl renew ssh/renew.sh
    dl hapus ssh/hapus.sh
    dl cek ssh/cek.sh
    dl member ssh/member.sh
    dl delete ssh/delete.sh
    dl autokill ssh/autokill.sh
    dl ceklim ssh/ceklim.sh
    dl tendang ssh/tendang.sh
    dl sshws ssh/sshws.sh
    dl add-host ssh/add-host.sh
    dl xp ssh/xp.sh
    dl speedtest ssh/speedtest_cli.py
    
    chmod +x /usr/bin/ssh/*.sh 2>/dev/null
    chmod +x /usr/bin/ssh/*.py 2>/dev/null
    
    # Restart SSH services
    systemctl restart ssh 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    
    cd /
    success_msg "SSH services updated successfully!"
    echo ""
}

# Update Xray only
update_xray() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 UPDATING XRAY SERVICES                      ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "This will update Xray services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Remove old xray files
    echo -e "${yellow}Removing old xray files...${NC}"
    rm -rf /usr/bin/xray 2>/dev/null
    mkdir -p /usr/bin/xray
    success_msg "Old xray files removed"
    
    # Download Xray scripts
    echo -e "${cyan}Downloading Xray scripts...${NC}"
    cd /usr/bin || return
    
    dl ins-xray xray/ins-xray.sh
    dl add-ws xray/add-ws.sh
    dl add-vless xray/add-vless.sh
    dl add-tr xray/add-tr.sh
    dl add-ssws xray/add-ssws.sh
    dl del-ws xray/del-ws.sh
    dl del-vless xray/del-vless.sh
    dl del-tr xray/del-tr.sh
    dl del-ssws xray/del-ssws.sh
    dl renew-ws xray/renew-ws.sh
    dl renew-vless xray/renew-vless.sh
    dl renew-tr xray/renew-tr.sh
    dl renew-ssws xray/renew-ssws.sh
    dl cek-ws xray/cek-ws.sh
    dl cek-vless xray/cek-vless.sh
    dl cek-tr xray/cek-tr.sh
    dl cek-ssws xray/cek-ssws.sh
    dl trialvmess xray/trialvmess.sh
    dl trialvless xray/trialvless.sh
    dl trialtrojan xray/trialtrojan.sh
    dl trialssws xray/trialssws.sh
    dl certv2ray xray/certv2ray.sh
    
    chmod +x /usr/bin/xray/*.sh 2>/dev/null
    
    # Update Xray core
    if command -v xray &> /dev/null; then
        echo -e "${cyan}Updating Xray core...${NC}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        success_msg "Xray core updated"
    fi
    
    systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
    
    cd /
    success_msg "Xray services updated successfully!"
    echo ""
}

# Update DNSTT
update_dnstt() {
    echo -e "${cyan}Updating DNSTT...${NC}"
    
    rm -rf /usr/bin/dnstt 2>/dev/null
    mkdir -p /usr/bin/dnstt
    
    cd /usr/bin || return
    
    dl dnstt-client-linux-386 dnstt/dnstt-client-linux-386
    dl dnstt-client-linux-amd64 dnstt/dnstt-client-linux-amd64
    dl dnstt-client-linux-arm64 dnstt/dnstt-client-linux-arm64
    dl dnstt-client-linux-armv7 dnstt/dnstt-client-linux-armv7
    dl dnstt-server-linux-386 dnstt/dnstt-server-linux-386
    dl dnstt-server-linux-amd64 dnstt/dnstt-server-linux-amd64
    dl dnstt-server-linux-arm64 dnstt/dnstt-server-linux-arm64
    dl dnstt-server-linux-armv7 dnstt/dnstt-server-linux-armv7
    dl install-dnstt dnstt/install-dnstt.sh
    dl menu-dnstt dnstt/menu-dnstt.sh
    
    chmod +x /usr/bin/dnstt/*
    cd /
    success_msg "DNSTT updated"
}

# Update SSHWS
update_sshws() {
    echo -e "${cyan}Updating SSHWS...${NC}"
    
    rm -rf /usr/bin/sshws 2>/dev/null
    mkdir -p /usr/bin/sshws
    
    cd /usr/bin || return
    
    dl insshws sshws/insshws.sh
    dl socks-ssh sshws/socks-ssh.py
    dl socks sshws/socks.py
    
    chmod +x /usr/bin/sshws/*.sh 2>/dev/null
    chmod +x /usr/bin/sshws/*.py 2>/dev/null
    
    cd /
    success_msg "SSHWS updated"
}

# Check for updates
check_updates() {
    echo -e "${cyan}Checking for updates...${NC}"
    echo ""
    
    if [ -f "/usr/bin/menu/versi" ]; then
        current_version=$(cat /usr/bin/menu/versi 2>/dev/null || echo "unknown")
        echo -e "Current version: ${yellow}$current_version${NC}"
    else
        echo -e "Current version: ${red}Not installed${NC}"
    fi
    
    latest_version=$(curl -s "$GHBASE/menu/versi" 2>/dev/null || echo "unknown")
    echo -e "Latest version:  ${yellow}$latest_version${NC}"
    echo ""
    
    if [ "$current_version" != "$latest_version" ] && [ "$latest_version" != "unknown" ]; then
        echo -e "${green}✓ New version available!${NC}"
    else
        echo -e "${green}You have the latest version.${NC}"
    fi
    echo ""
}

# Restore from backup
restore_backup() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 RESTORE FROM BACKUP                         ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    backups=($(ls -dt /root/backup_* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${red}✗ No backups found!${NC}"
        return
    fi
    
    echo -e "${yellow}Available backups:${NC}"
    for i in "${!backups[@]}"; do
        backup_date=$(basename "${backups[$i]}" | sed 's/backup_//')
        echo -e "  $((i+1)). ${backup_date}"
    done
    echo ""
    
    read -p "Select backup to restore [1-${#backups[@]}]: " backup_choice
    backup_choice=$((backup_choice-1))
    
    if [ -z "${backups[$backup_choice]}" ]; then
        echo -e "${red}✗ Invalid selection!${NC}"
        return
    fi
    
    selected_backup="${backups[$backup_choice]}"
    echo -e "${yellow}Restoring from: $selected_backup${NC}"
    
    read -p "WARNING: This will overwrite current files. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    # Restore
    [ -d "$selected_backup/menu" ] && cp -rf "$selected_backup/menu" /usr/bin/ 2>/dev/null
    [ -d "$selected_backup/ssh" ] && cp -rf "$selected_backup/ssh" /usr/bin/ 2>/dev/null
    [ -d "$selected_backup/xray" ] && cp -rf "$selected_backup/xray" /usr/bin/ 2>/dev/null
    [ -f "$selected_backup/passwd" ] && cp "$selected_backup/passwd" /etc/ 2>/dev/null
    [ -f "$selected_backup/shadow" ] && cp "$selected_backup/shadow" /etc/ 2>/dev/null
    [ -f "$selected_backup/domain.txt" ] && cp "$selected_backup/domain.txt" /root/ 2>/dev/null
    
    chmod +x /usr/bin/menu/*.sh 2>/dev/null
    chmod +x /usr/bin/ssh/*.sh 2>/dev/null
    chmod +x /usr/bin/xray/*.sh 2>/dev/null
    
    success_msg "Backup restored successfully!"
}

# ---------- MAIN MENU ----------
main_menu() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}     ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ${purple}║${NC}"
    echo -e "${purple}║${white}     ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗${purple}║${NC}"
    echo -e "${purple}║${white}      ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${purple}║${NC}"
    echo -e "${purple}║${cyan}                    • UPDATE MANAGER •                     ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${cyan}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${cyan}│${white}  [1] UPDATE ALL SERVICES (SSH, Xray, Menu, DNSTT)     ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [2] UPDATE SSH ONLY                                ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [3] UPDATE XRAY ONLY                              ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [4] UPDATE MENU FILES ONLY                        ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [5] CHECK FOR UPDATES                             ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [6] RESTORE FROM BACKUP                           ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [0] EXIT                                          ${cyan}│${NC}"
    echo -e "${cyan}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Select option [0-6]: " choice
    echo ""
    
    case $choice in
        1) update_all ;;
        2) update_ssh ;;
        3) update_xray ;;
        4) update_menu ;;
        5) check_updates ;;
        6) restore_backup ;;
        0) echo -e "${green}Exiting...${NC}"; exit 0 ;;
        *) 
            echo -e "${red}✗ Invalid option! Please select 0-6.${NC}"
            echo ""
            read -n 1 -s -r -p "Press any key to continue..."
            clear
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    clear
    main_menu
}

# ---------- START SCRIPT ----------
# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}✗ This script must be run as root!${NC}"
    exit 1
fi

# Check internet connection
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${red}✗ No internet connection!${NC}"
    exit 1
fi

# Create log file
touch "$LOG_FILE"

# Main execution
main_menu