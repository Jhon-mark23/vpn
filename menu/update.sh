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
REPO_URL="https://raw.githubusercontent.com/yourusername/marcscript/main"  # CHANGE THIS
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-update.log"
INSTALL_DIR="/usr/local/marcscript"

# ---------- FUNCTIONS ----------

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    echo -e "${red}✗ ERROR: $1${NC}"
    log "ERROR: $1"
    exit 1
}

# Success message
success_msg() {
    echo -e "${green}✓ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning_msg() {
    echo -e "${yellow}⚠ $1${NC}"
    log "WARNING: $1"
}

# Create backup
create_backup() {
    echo -e "${yellow}Creating backup...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important directories
    [ -d "/etc/xray" ] && cp -r /etc/xray "$BACKUP_DIR/" 2>/dev/null
    [ -d "/etc/v2ray" ] && cp -r /etc/v2ray "$BACKUP_DIR/" 2>/dev/null
    [ -d "/etc/ssh" ] && cp -r /etc/ssh "$BACKUP_DIR/" 2>/dev/null
    [ -d "/etc/dropbear" ] && cp -r /etc/dropbear "$BACKUP_DIR/" 2>/dev/null
    [ -d "/etc/nginx" ] && cp -r /etc/nginx "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/passwd" ] && cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/shadow" ] && cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
    [ -f "/root/domain.txt" ] && cp /root/domain.txt "$BACKUP_DIR/" 2>/dev/null
    
    # Backup all scripts
    [ -d "/usr/local/bin/ssh" ] && cp -r /usr/local/bin/ssh "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/local/bin/xray" ] && cp -r /usr/local/bin/xray "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/local/bin/menu" ] && cp -r /usr/local/bin/menu "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/local/bin/dnstt" ] && cp -r /usr/local/bin/dnstt "$BACKUP_DIR/" 2>/dev/null
    [ -d "/usr/local/bin/sshws" ] && cp -r /usr/local/bin/sshws "$BACKUP_DIR/" 2>/dev/null
    
    success_msg "Backup created at: $BACKUP_DIR"
}

# Download file with progress
download_file() {
    local url="$1"
    local dest="$2"
    local filename=$(basename "$dest")
    
    echo -e "${cyan}Downloading: $filename${NC}"
    wget -q --show-progress -O "$dest" "$url" || {
        echo -e "${red}✗ Failed to download: $filename${NC}"
        return 1
    }
    chmod +x "$dest" 2>/dev/null
    success_msg "Installed: $filename"
    return 0
}

# Delete old files before installation
delete_old_files() {
    local target_dir="$1"
    local pattern="$2"
    
    if [ -d "$target_dir" ]; then
        echo -e "${yellow}Removing old files from: $target_dir${NC}"
        if [ -n "$pattern" ]; then
            # Delete specific pattern
            find "$target_dir" -name "$pattern" -type f -delete 2>/dev/null
        else
            # Delete all files in directory
            rm -rf "$target_dir"/* 2>/dev/null
        fi
        success_msg "Old files removed from: $target_dir"
    else
        mkdir -p "$target_dir"
        success_msg "Created directory: $target_dir"
    fi
}

# Update ALL services
update_all() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}         🔄 UPDATING ALL SERVICES & MENU FILES               ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Confirm update
    read -p "This will update ALL services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Update each component
    update_ssh
    update_xray
    update_menu
    update_dnstt
    update_sshws
    update_main_scripts
    
    # Restart services
    echo -e "${cyan}Restarting services...${NC}"
    systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
    systemctl restart ssh 2>/dev/null
    systemctl restart dropbear 2>/dev/null
    systemctl restart ws-dropbear 2>/dev/null
    systemctl restart ws-stunnel 2>/dev/null
    systemctl restart nginx 2>/dev/null
    
    success_msg "All services updated successfully!"
    echo ""
}

# Update main scripts
update_main_scripts() {
    echo -e "${cyan}Updating main scripts...${NC}"
    mkdir -p /usr/local/bin
    
    # Delete old main scripts
    local main_scripts=("setup.sh" "setup-ssh.sh" "create-cert.sh" "push.sh")
    for script in "${main_scripts[@]}"; do
        [ -f "/usr/local/bin/$script" ] && rm -f "/usr/local/bin/$script"
    done
    
    # Download new main scripts
    download_file "$REPO_URL/setup.sh" "/usr/local/bin/setup.sh"
    download_file "$REPO_URL/setup-ssh.sh" "/usr/local/bin/setup-ssh.sh"
    download_file "$REPO_URL/create-cert.sh" "/usr/local/bin/create-cert.sh"
    download_file "$REPO_URL/push.sh" "/usr/local/bin/push.sh"
}

# Update SSH only
update_ssh() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 UPDATING SSH SERVICES                        ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Confirm update
    read -p "This will update SSH services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Delete old SSH files
    delete_old_files "/usr/local/bin/ssh" "*.sh"
    delete_old_files "/usr/local/bin/ssh" "*.py"
    delete_old_files "/usr/local/bin/ssh" "*.js"
    
    # Download SSH scripts
    local ssh_files=(
        "usernew.sh"
        "trial.sh"
        "delete.sh"
        "hapus.sh"
        "renew.sh"
        "cek.sh"
        "ceklim.sh"
        "member.sh"
        "xp.sh"
        "autokill.sh"
        "tendang.sh"
        "add-host.sh"
        "password"
        "newudpgw"
        "ssh-vpn.sh"
        "fix-cek.sh"
    )
    
    for file in "${ssh_files[@]}"; do
        download_file "$REPO_URL/ssh/$file" "/usr/local/bin/ssh/$file"
    done
    
    # Download utilities
    download_file "$REPO_URL/ssh/speedtest_cli.py" "/usr/local/bin/speedtest_cli.py"
    download_file "$REPO_URL/ssh/nginx.conf" "/etc/nginx/nginx.conf"
    download_file "$REPO_URL/ssh/proxy3.js" "/usr/local/bin/proxy3.js"
    download_file "$REPO_URL/ssh/cf" "/usr/local/bin/cf"
    
    # Update permissions
    chmod +x /usr/local/bin/ssh/*.sh 2>/dev/null
    chmod +x /usr/local/bin/ssh/*.py 2>/dev/null
    chmod +x /usr/local/bin/ssh/* 2>/dev/null
    
    # Restart SSH services
    systemctl restart ssh
    systemctl restart dropbear
    
    success_msg "SSH services updated successfully!"
    echo ""
}

# Update Xray only
update_xray() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 UPDATING XRAY SERVICES                      ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Confirm update
    read -p "This will update Xray services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Delete old Xray files
    delete_old_files "/usr/local/bin/xray" "*.sh"
    
    # Download Xray scripts
    local xray_files=(
        "ins-xray.sh"
        "add-ws.sh"
        "add-vless.sh"
        "add-tr.sh"
        "add-ssws.sh"
        "del-ws.sh"
        "del-vless.sh"
        "del-tr.sh"
        "del-ssws.sh"
        "renew-ws.sh"
        "renew-vless.sh"
        "renew-tr.sh"
        "renew-ssws.sh"
        "cek-ws.sh"
        "cek-vless.sh"
        "cek-tr.sh"
        "cek-ssws.sh"
        "trialvmess.sh"
        "trialvless.sh"
        "trialtrojan.sh"
        "trialssws.sh"
        "certv2ray.sh"
    )
    
    for file in "${xray_files[@]}"; do
        download_file "$REPO_URL/xray/$file" "/usr/local/bin/xray/$file"
    done
    
    # Update permissions
    chmod +x /usr/local/bin/xray/*.sh
    
    # Update Xray core if needed
    if command -v xray &> /dev/null; then
        echo -e "${cyan}Checking Xray core version...${NC}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        success_msg "Xray core updated"
    fi
    
    # Restart Xray
    systemctl restart xray 2>/dev/null || systemctl restart v2ray 2>/dev/null
    
    success_msg "Xray services updated successfully!"
    echo ""
}

# Update Menu only
update_menu() {
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${cyan}              🔄 UPDATING MENU FILES                         ${NC}"
    echo -e "${purple}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Confirm update
    read -p "This will update Menu files. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Delete old menu files
    delete_old_files "/usr/local/bin/menu" "*.sh"
    [ -f "/usr/local/bin/menu/versi" ] && rm -f "/usr/local/bin/menu/versi"
    
    # Download menu scripts
    local menu_files=(
        "menu.sh"
        "m-sshovpn.sh"
        "m-ssws.sh"
        "m-vmess.sh"
        "m-vless.sh"
        "m-trojan.sh"
        "m-xray.sh"
        "m-system.sh"
        "m-domain.sh"
        "m-dns.sh"
        "m-webmin.sh"
        "auto-reboot.sh"
        "restart.sh"
        "running.sh"
        "bw.sh"
        "clearcache.sh"
        "update.sh"
        "tcp.sh"
        "versi"
    )
    
    for file in "${menu_files[@]}"; do
        download_file "$REPO_URL/menu/$file" "/usr/local/bin/menu/$file"
    done
    
    # Update permissions
    chmod +x /usr/local/bin/menu/*.sh
    
    # Delete old main menu symlink
    [ -L "/usr/local/bin/menu" ] && rm -f /usr/local/bin/menu
    [ -f "/usr/local/bin/menu.sh" ] && rm -f /usr/local/bin/menu.sh
    
    # Update main menu symlink
    if [ -f "/usr/local/bin/menu/menu.sh" ]; then
        ln -sf /usr/local/bin/menu/menu.sh /usr/local/bin/menu
        chmod +x /usr/local/bin/menu
        ln -sf /usr/local/bin/menu/menu.sh /usr/local/bin/menu.sh
        chmod +x /usr/local/bin/menu.sh
    fi
    
    success_msg "Menu files updated successfully!"
    echo ""
}

# Update DNSTT
update_dnstt() {
    echo -e "${cyan}Updating DNSTT...${NC}"
    
    # Delete old DNSTT files
    delete_old_files "/usr/local/bin/dnstt" "*"
    
    local dnstt_files=(
        "dnstt-client-linux-386"
        "dnstt-client-linux-amd64"
        "dnstt-client-linux-arm64"
        "dnstt-client-linux-armv7"
        "dnstt-server-linux-386"
        "dnstt-server-linux-amd64"
        "dnstt-server-linux-arm64"
        "dnstt-server-linux-armv7"
        "install-dnstt.sh"
        "menu-dnstt.sh"
    )
    
    for file in "${dnstt_files[@]}"; do
        download_file "$REPO_URL/dnstt/$file" "/usr/local/bin/dnstt/$file"
    done
    
    chmod +x /usr/local/bin/dnstt/*
    success_msg "DNSTT updated"
}

# Update SSHWS
update_sshws() {
    echo -e "${cyan}Updating SSHWS...${NC}"
    
    # Delete old SSHWS files
    delete_old_files "/usr/local/bin/sshws" "*"
    
    local sshws_files=(
        "insshws.sh"
        "socks-ssh.py"
        "socks.py"
        "ws-dropbear.service"
        "ws-stunnel.service"
    )
    
    for file in "${sshws_files[@]}"; do
        download_file "$REPO_URL/sshws/$file" "/usr/local/bin/sshws/$file"
    done
    
    chmod +x /usr/local/bin/sshws/*.sh 2>/dev/null
    chmod +x /usr/local/bin/sshws/*.py 2>/dev/null
    
    # Delete old systemd services
    [ -f "/etc/systemd/system/ws-dropbear.service" ] && rm -f /etc/systemd/system/ws-dropbear.service
    [ -f "/etc/systemd/system/ws-stunnel.service" ] && rm -f /etc/systemd/system/ws-stunnel.service
    
    # Copy new systemd services
    if [ -f "/usr/local/bin/sshws/ws-dropbear.service" ]; then
        cp /usr/local/bin/sshws/ws-dropbear.service /etc/systemd/system/
    fi
    if [ -f "/usr/local/bin/sshws/ws-stunnel.service" ]; then
        cp /usr/local/bin/sshws/ws-stunnel.service /etc/systemd/system/
    fi
    
    systemctl daemon-reload
    systemctl restart ws-dropbear 2>/dev/null
    systemctl restart ws-stunnel 2>/dev/null
    
    success_msg "SSHWS updated"
}

# Check for updates
check_updates() {
    echo -e "${cyan}Checking for updates...${NC}"
    echo ""
    
    # Check current versions
    if [ -f "/usr/local/bin/menu/versi" ]; then
        current_version=$(cat /usr/local/bin/menu/versi 2>/dev/null || echo "unknown")
        echo -e "Current version: ${yellow}$current_version${NC}"
    else
        echo -e "Current version: ${red}Not installed${NC}"
    fi
    
    # Check latest version from repo
    latest_version=$(curl -s "$REPO_URL/menu/versi" 2>/dev/null || echo "unknown")
    echo -e "Latest version:  ${yellow}$latest_version${NC}"
    echo ""
    
    if [ "$current_version" != "$latest_version" ] && [ "$latest_version" != "unknown" ] && [ "$current_version" != "Not installed" ]; then
        echo -e "${green}✓ New version available!${NC}"
    elif [ "$current_version" = "Not installed" ]; then
        echo -e "${yellow}No installation detected. Please run update.${NC}"
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
    
    # List available backups
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
    
    # Confirm restore
    read -p "WARNING: This will overwrite current files. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    # Restore files
    [ -d "$selected_backup/xray" ] && cp -rf "$selected_backup/xray" /etc/ 2>/dev/null
    [ -d "$selected_backup/v2ray" ] && cp -rf "$selected_backup/v2ray" /etc/ 2>/dev/null
    [ -d "$selected_backup/ssh" ] && cp -rf "$selected_backup/ssh" /usr/local/bin/ 2>/dev/null
    [ -d "$selected_backup/xray" ] && cp -rf "$selected_backup/xray" /usr/local/bin/ 2>/dev/null
    [ -d "$selected_backup/menu" ] && cp -rf "$selected_backup/menu" /usr/local/bin/ 2>/dev/null
    [ -d "$selected_backup/dnstt" ] && cp -rf "$selected_backup/dnstt" /usr/local/bin/ 2>/dev/null
    [ -d "$selected_backup/sshws" ] && cp -rf "$selected_backup/sshws" /usr/local/bin/ 2>/dev/null
    [ -f "$selected_backup/passwd" ] && cp "$selected_backup/passwd" /etc/ 2>/dev/null
    [ -f "$selected_backup/shadow" ] && cp "$selected_backup/shadow" /etc/ 2>/dev/null
    [ -f "$selected_backup/domain.txt" ] && cp "$selected_backup/domain.txt" /root/ 2>/dev/null
    
    # Restore permissions
    chmod +x /usr/local/bin/ssh/*.sh 2>/dev/null
    chmod +x /usr/local/bin/xray/*.sh 2>/dev/null
    chmod +x /usr/local/bin/menu/*.sh 2>/dev/null
    
    success_msg "Backup restored successfully!"
    echo -e "${yellow}Please restart services if needed.${NC}"
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
        1)
            update_all
            ;;
        2)
            update_ssh
            ;;
        3)
            update_xray
            ;;
        4)
            update_menu
            ;;
        5)
            check_updates
            ;;
        6)
            restore_backup
            ;;
        0)
            echo -e "${green}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${red}✗ Invalid option! Please select 0-6.${NC}"
            echo ""
            read -n 1 -s -r -p "Press any key to continue..."
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    main_menu
}

# ---------- INITIAL SETUP ----------
setup_repository() {
    # Create directories
    mkdir -p /usr/local/bin/{ssh,xray,menu,dnstt,sshws}
    mkdir -p /etc/marcscript
    mkdir -p /etc/nginx
    
    # Create log file
    touch "$LOG_FILE"
    
    # Set permissions
    chmod 755 /usr/local/bin/{ssh,xray,menu,dnstt,sshws} 2>/dev/null
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
        echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
        export PATH=$PATH:/usr/local/bin
    fi
}

# ---------- START SCRIPT ----------
setup_repository

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}✗ This script must be run as root!${NC}"
    exit 1
fi

# Check internet connection
if ! ping -c 1 google.com &> /dev/null; then
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${red}✗ No internet connection!${NC}"
        exit 1
    fi
fi

# Main execution
main_menu