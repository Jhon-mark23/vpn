#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - UPDATE MANAGER
# Version: 2.0 (Private Repo + Token Auth)
# ============================================================

clear

# ---------- GITHUB TOKEN ----------
gtoken=$(cat /root/token 2>/dev/null || cat /root/token.txt 2>/dev/null)
if [[ -z "$gtoken" ]]; then
    echo -e "\033[1;31mERROR: GitHub token not found!\033[0m"
    echo -e "Place token in /root/token or /root/token.txt"
    exit 1
fi

GITHUB_TOKEN="$gtoken"
REPO_API="https://api.github.com/repos/Jhon-mark23/vpn/contents"
REPO_REF="ref=main"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
RAW_HEADER="Accept: application/vnd.github.raw"

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
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-update.log"
STATUS_FILE="/root/update-status.txt"

# Initialize logs
> "$LOG_FILE"
> "$STATUS_FILE"

# ---------- FUNCTIONS ----------

# Download from private repo
download_private() {
    local remote_path="$1"
    local output_file="$2"
    curl -sS \
        -H "$AUTH_HEADER" \
        -H "$RAW_HEADER" \
        "${REPO_API}/${remote_path}?${REPO_REF}" \
        -o "$output_file"
    return $?
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Success message
success_msg() {
    echo -e "${green}✓ $1${NC}"
    log "SUCCESS: $1"
    echo "SUCCESS: $1" >> "$STATUS_FILE"
}

# Error message
error_msg() {
    echo -e "${red}✗ $1${NC}"
    log "ERROR: $1"
    echo "ERROR: $1" >> "$STATUS_FILE"
}

# Info message
info_msg() {
    echo -e "${cyan}ℹ $1${NC}"
    log "INFO: $1"
}

# Download function for scripts
dl() {
    local dest="$1"
    local remote_path="$2"
    local name=$(basename "$dest")
    
    echo -ne "${cyan}Downloading: $name ... ${NC}"
    
    download_private "$remote_path" "$dest" 2>/dev/null
    if [ $? -eq 0 ] && [ -s "$dest" ]; then
        chmod +x "$dest" 2>/dev/null
        sed -i 's/\r$//' "$dest" 2>/dev/null
        echo -e "${green}OK${NC}"
        log "DOWNLOADED: $remote_path -> $dest"
        return 0
    else
        echo -e "${red}FAILED${NC}"
        error_msg "Failed to download: $name"
        return 1
    fi
}

# Create backup
create_backup() {
    info_msg "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup important files
    [ -f "/etc/passwd" ] && cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/shadow" ] && cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
    [ -f "/root/domain.txt" ] && cp /root/domain.txt "$BACKUP_DIR/" 2>/dev/null
    [ -f "/root/domain" ] && cp /root/domain "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/xray/domain" ] && cp /etc/xray/domain "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/ssh/sshd_config" ] && cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/stunnel/stunnel.conf" ] && cp /etc/stunnel/stunnel.conf "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/xray/config.json" ] && cp /etc/xray/config.json "$BACKUP_DIR/" 2>/dev/null
    [ -f "/etc/nginx/conf.d/xray.conf" ] && cp /etc/nginx/conf.d/xray.conf "$BACKUP_DIR/" 2>/dev/null
    
    # Backup scripts directory
    [ -d "/usr/bin" ] && tar -czf "$BACKUP_DIR/scripts-backup.tar.gz" /usr/bin/menu /usr/bin/usernew /usr/bin/trial /usr/bin/renew /usr/bin/hapus /usr/bin/cek /usr/bin/member /usr/bin/add-ws /usr/bin/add-vless /usr/bin/add-tr /usr/bin/add-ssws 2>/dev/null
    
    success_msg "Backup created at: $BACKUP_DIR"
    echo "BACKUP: $BACKUP_DIR" >> "$STATUS_FILE"
}

# ---------- UPDATE FUNCTIONS ----------

# Update ALL services (full reinstall)
update_all() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 FULL SYSTEM REINSTALL                       ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "This will REINSTALL everything. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    info_msg "Downloading setup script..."
    download_private "setup.sh" "/root/setup.sh"
    chmod +x /root/setup.sh
    sed -i 's/\r$//' /root/setup.sh
    
    info_msg "Starting full installation..."
    screen -S setup /root/setup.sh
    
    success_msg "Full reinstall initiated in screen session 'setup'"
    echo "Use: screen -r setup  to view progress"
}

# Update Menu scripts only
update_menu() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 UPDATING MENU SCRIPTS                      ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    cd /usr/bin || return
    
    # Main menu
    dl "/usr/bin/menu" "menu/menu.sh"
    
    # Sub menus
    dl "/usr/bin/m-xray" "menu/m-xray.sh"
    dl "/usr/bin/m-sshovpn" "menu/m-sshovpn.sh"
    dl "/usr/bin/m-vmess" "menu/m-vmess.sh"
    dl "/usr/bin/m-vless" "menu/m-vless.sh"
    dl "/usr/bin/m-trojan" "menu/m-trojan.sh"
    dl "/usr/bin/m-ssws" "menu/m-ssws.sh"
    dl "/usr/bin/m-system" "menu/m-system.sh"
    dl "/usr/bin/running" "menu/running.sh"
    dl "/usr/bin/clearcache" "menu/clearcache.sh"
    
    # SSH management scripts
    dl "/usr/bin/usernew" "ssh/usernew.sh"
    dl "/usr/bin/trial" "ssh/trial.sh"
    dl "/usr/bin/renew" "ssh/renew.sh"
    dl "/usr/bin/hapus" "ssh/hapus.sh"
    dl "/usr/bin/cek" "ssh/cek.sh"
    dl "/usr/bin/member" "ssh/member.sh"
    dl "/usr/bin/delete" "ssh/delete.sh"
    dl "/usr/bin/autokill" "ssh/autokill.sh"
    dl "/usr/bin/ceklim" "ssh/ceklim.sh"
    dl "/usr/bin/tendang" "ssh/tendang.sh"
    dl "/usr/bin/sshws" "ssh/sshws.sh"
    dl "/usr/bin/add-host" "ssh/add-host.sh"
    dl "/usr/bin/xp" "ssh/xp.sh"
    dl "/usr/bin/speedtest" "ssh/speedtest_cli.py"
    
    # Xray management scripts
    dl "/usr/bin/add-ws" "xray/add-ws.sh"
    dl "/usr/bin/add-vless" "xray/add-vless.sh"
    dl "/usr/bin/add-tr" "xray/add-tr.sh"
    dl "/usr/bin/add-ssws" "xray/add-ssws.sh"
    dl "/usr/bin/del-ws" "xray/del-ws.sh"
    dl "/usr/bin/del-vless" "xray/del-vless.sh"
    dl "/usr/bin/del-tr" "xray/del-tr.sh"
    dl "/usr/bin/del-ssws" "xray/del-ssws.sh"
    dl "/usr/bin/renew-ws" "xray/renew-ws.sh"
    dl "/usr/bin/renew-vless" "xray/renew-vless.sh"
    dl "/usr/bin/renew-tr" "xray/renew-tr.sh"
    dl "/usr/bin/renew-ssws" "xray/renew-ssws.sh"
    dl "/usr/bin/cek-ws" "xray/cek-ws.sh"
    dl "/usr/bin/cek-vless" "xray/cek-vless.sh"
    dl "/usr/bin/cek-tr" "xray/cek-tr.sh"
    dl "/usr/bin/cek-ssws" "xray/cek-ssws.sh"
    dl "/usr/bin/trialvmess" "xray/trialvmess.sh"
    dl "/usr/bin/trialvless" "xray/trialvless.sh"
    dl "/usr/bin/trialtrojan" "xray/trialtrojan.sh"
    dl "/usr/bin/trialssws" "xray/trialssws.sh"
    
    cd /
    success_msg "Menu scripts updated"
}

# Update SSH services
update_ssh() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 UPDATING SSH SERVICES                       ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "This will update SSH services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Download SSH installer and re-run
    info_msg "Downloading SSH-VPN installer..."
    download_private "ssh/ssh-vpn.sh" "/root/ssh-vpn.sh"
    chmod +x /root/ssh-vpn.sh
    sed -i 's/\r$//' /root/ssh-vpn.sh
    
    info_msg "Running SSH-VPN installer..."
    bash /root/ssh-vpn.sh
    
    # Also update SSH management scripts
    cd /usr/bin || return
    dl "/usr/bin/usernew" "ssh/usernew.sh"
    dl "/usr/bin/trial" "ssh/trial.sh"
    dl "/usr/bin/renew" "ssh/renew.sh"
    dl "/usr/bin/hapus" "ssh/hapus.sh"
    dl "/usr/bin/cek" "ssh/cek.sh"
    dl "/usr/bin/member" "ssh/member.sh"
    dl "/usr/bin/delete" "ssh/delete.sh"
    dl "/usr/bin/autokill" "ssh/autokill.sh"
    dl "/usr/bin/ceklim" "ssh/ceklim.sh"
    dl "/usr/bin/tendang" "ssh/tendang.sh"
    dl "/usr/bin/add-host" "ssh/add-host.sh"
    dl "/usr/bin/xp" "ssh/xp.sh"
    
    # Restart SSH
    systemctl restart ssh 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    
    cd /
    success_msg "SSH services updated"
}

# Update Xray services
update_xray() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 UPDATING XRAY SERVICES                      ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "This will update Xray services. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Download Xray installer and re-run
    info_msg "Downloading Xray installer..."
    download_private "xray/ins-xray.sh" "/root/ins-xray.sh"
    chmod +x /root/ins-xray.sh
    sed -i 's/\r$//' /root/ins-xray.sh
    
    info_msg "Running Xray installer..."
    bash /root/ins-xray.sh
    
    # Also update Xray management scripts
    cd /usr/bin || return
    dl "/usr/bin/add-ws" "xray/add-ws.sh"
    dl "/usr/bin/add-vless" "xray/add-vless.sh"
    dl "/usr/bin/add-tr" "xray/add-tr.sh"
    dl "/usr/bin/add-ssws" "xray/add-ssws.sh"
    dl "/usr/bin/del-ws" "xray/del-ws.sh"
    dl "/usr/bin/del-vless" "xray/del-vless.sh"
    dl "/usr/bin/del-tr" "xray/del-tr.sh"
    dl "/usr/bin/del-ssws" "xray/del-ssws.sh"
    dl "/usr/bin/renew-ws" "xray/renew-ws.sh"
    dl "/usr/bin/renew-vless" "xray/renew-vless.sh"
    dl "/usr/bin/renew-tr" "xray/renew-tr.sh"
    dl "/usr/bin/renew-ssws" "xray/renew-ssws.sh"
    dl "/usr/bin/cek-ws" "xray/cek-ws.sh"
    dl "/usr/bin/cek-vless" "xray/cek-vless.sh"
    dl "/usr/bin/cek-tr" "xray/cek-tr.sh"
    dl "/usr/bin/cek-ssws" "xray/cek-ssws.sh"
    dl "/usr/bin/trialvmess" "xray/trialvmess.sh"
    dl "/usr/bin/trialvless" "xray/trialvless.sh"
    dl "/usr/bin/trialtrojan" "xray/trialtrojan.sh"
    dl "/usr/bin/trialssws" "xray/trialssws.sh"
    
    # Update Xray core
    if command -v xray &> /dev/null; then
        info_msg "Updating Xray core..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        success_msg "Xray core updated"
    fi
    
    systemctl restart xray 2>/dev/null
    
    cd /
    success_msg "Xray services updated"
}

# Update Python WS Proxy
update_wsproxy() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}           🔄 UPDATING PYTHON WS PROXY                       ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "This will update Python WS Proxy. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Download WS Proxy installer
    info_msg "Downloading WS Proxy installer..."
    download_private "sshws/insshws.sh" "/root/insshws.sh"
    chmod +x /root/insshws.sh
    sed -i 's/\r$//' /root/insshws.sh
    
    info_msg "Running WS Proxy installer..."
    bash /root/insshws.sh
    
    success_msg "Python WS Proxy updated"
}

# Update DNSTT
update_dnstt() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 UPDATING DNSTT SERVICES                     ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "This will update DNSTT. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    # Download DNSTT installer
    info_msg "Downloading DNSTT installer..."
    download_private "dnstt/install-dnstt.sh" "/root/install-dnstt.sh"
    chmod +x /root/install-dnstt.sh
    sed -i 's/\r$//' /root/install-dnstt.sh
    
    info_msg "Running DNSTT installer..."
    bash /root/install-dnstt.sh
    
    # Download DNSTT binaries based on architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        armv7l)  ARCH_TYPE="armv7" ;;
        *)       ARCH_TYPE="amd64" ;;
    esac
    
    info_msg "Updating DNSTT binaries for $ARCH_TYPE..."
    mkdir -p /etc/slowdns
    download_private "dnstt/dnstt-server-linux-${ARCH_TYPE}" "/etc/slowdns/sldns-server"
    download_private "dnstt/dnstt-client-linux-${ARCH_TYPE}" "/etc/slowdns/sldns-client"
    chmod +x /etc/slowdns/sldns-server /etc/slowdns/sldns-client 2>/dev/null
    
    systemctl restart server-sldns 2>/dev/null
    
    success_msg "DNSTT updated"
}

# Check for updates
check_updates() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔍 CHECKING FOR UPDATES                        ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    info_msg "Checking version..."
    
    # Current version
    if [ -f "/opt/.ver" ]; then
        current_version=$(cat /opt/.ver 2>/dev/null)
        echo -e "Current version: ${yellow}$current_version${NC}"
    else
        echo -e "Current version: ${red}Unknown${NC}"
    fi
    
    # Latest version from private repo
    latest_version=$(curl -sS -H "$AUTH_HEADER" -H "$RAW_HEADER" "${REPO_API}/menu/versi?${REPO_REF}" 2>/dev/null)
    
    if [[ -n "$latest_version" ]]; then
        echo -e "Latest version:  ${green}$latest_version${NC}"
        
        if [[ "$current_version" != "$latest_version" ]]; then
            echo ""
            echo -e "${green}✓ New version available!${NC}"
            echo -e "  Current: ${yellow}$current_version${NC}"
            echo -e "  Latest:  ${green}$latest_version${NC}"
        else
            echo ""
            echo -e "${green}✓ You have the latest version.${NC}"
        fi
    else
        echo -e "Latest version:  ${red}Unable to check${NC}"
        echo -e "${yellow}Check your GitHub token and internet connection.${NC}"
    fi
    
    # Check service status
    echo ""
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${cyan}   SERVICE STATUS${NC}"
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    svc_status() {
        if systemctl is-active --quiet "$1" 2>/dev/null; then
            echo -e " ${green}●${NC} $1 ${green}Running${NC}"
        else
            echo -e " ${red}●${NC} $1 ${red}Not Running${NC}"
        fi
    }
    
    svc_status "ssh"
    svc_status "stunnel4"
    svc_status "nginx"
    svc_status "xray"
    svc_status "fail2ban"
    svc_status "ws-8080"
    svc_status "ws-9443"
    svc_status "ws-9445"
    svc_status "server-sldns"
    
    echo ""
}

# Restore from backup
restore_backup() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              🔄 RESTORE FROM BACKUP                         ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Find backups
    backups=($(ls -dt /root/backup_* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        error_msg "No backups found!"
        return
    fi
    
    echo -e "${yellow}Available backups:${NC}"
    for i in "${!backups[@]}"; do
        backup_date=$(basename "${backups[$i]}" | sed 's/backup_//')
        backup_size=$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)
        echo -e "  ${green}$((i+1)).${NC} ${backup_date} ${cyan}(${backup_size})${NC}"
    done
    echo ""
    
    read -p "Select backup to restore [1-${#backups[@]}] or 0 to cancel: " backup_choice
    
    if [[ "$backup_choice" == "0" ]]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    backup_choice=$((backup_choice-1))
    
    if [ -z "${backups[$backup_choice]}" ]; then
        error_msg "Invalid selection!"
        return
    fi
    
    selected_backup="${backups[$backup_choice]}"
    echo ""
    echo -e "${yellow}Restoring from: $selected_backup${NC}"
    echo ""
    
    read -p "WARNING: This will overwrite current files. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    # Restore scripts from tar backup
    if [ -f "$selected_backup/scripts-backup.tar.gz" ]; then
        info_msg "Restoring scripts..."
        tar -xzf "$selected_backup/scripts-backup.tar.gz" -C / 2>/dev/null
        chmod +x /usr/bin/menu 2>/dev/null
    fi
    
    # Restore configs
    [ -f "$selected_backup/sshd_config" ] && cp "$selected_backup/sshd_config" /etc/ssh/sshd_config && systemctl restart ssh
    [ -f "$selected_backup/stunnel.conf" ] && cp "$selected_backup/stunnel.conf" /etc/stunnel/stunnel.conf
    [ -f "$selected_backup/config.json" ] && cp "$selected_backup/config.json" /etc/xray/config.json && systemctl restart xray
    [ -f "$selected_backup/xray.conf" ] && cp "$selected_backup/xray.conf" /etc/nginx/conf.d/xray.conf
    [ -f "$selected_backup/domain.txt" ] && cp "$selected_backup/domain.txt" /root/
    [ -f "$selected_backup/domain" ] && cp "$selected_backup/domain" /root/
    [ -f "$selected_backup/passwd" ] && cp "$selected_backup/passwd" /etc/
    [ -f "$selected_backup/shadow" ] && cp "$selected_backup/shadow" /etc/
    
    systemctl restart nginx 2>/dev/null
    
    success_msg "Backup restored from: $(basename $selected_backup)"
}

# View update logs
view_logs() {
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}              📋 UPDATE LOGS                                 ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        echo -e "${cyan}Update Log ($LOG_FILE):${NC}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        tail -50 "$LOG_FILE"
    else
        echo -e "${yellow}No update log found.${NC}"
    fi
    
    echo ""
    echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -f "$STATUS_FILE" ]; then
        echo ""
        echo -e "${cyan}Status Summary ($STATUS_FILE):${NC}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        cat "$STATUS_FILE"
    fi
    
    echo ""
}

# ---------- MAIN MENU ----------
main_menu() {
    clear
    echo -e "${purple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${purple}║${white}     ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ${purple}║${NC}"
    echo -e "${purple}║${white}     ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ${purple}║${NC}"
    echo -e "${purple}║${white}     ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗${purple}║${NC}"
    echo -e "${purple}║${white}      ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${purple}║${NC}"
    echo -e "${purple}║${cyan}                    • UPDATE MANAGER v2.0 •                  ${purple}║${NC}"
    echo -e "${purple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${cyan}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${cyan}│${white}  [1]  UPDATE ALL (Full Reinstall)                      ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [2]  UPDATE SSH Services Only                        ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [3]  UPDATE Xray Services Only                       ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [4]  UPDATE Python WS Proxy Only                     ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [5]  UPDATE DNSTT Services Only                      ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [6]  UPDATE Menu Scripts Only                        ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [7]  CHECK FOR UPDATES & Service Status              ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [8]  RESTORE FROM BACKUP                             ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [9]  VIEW UPDATE LOGS                                ${cyan}│${NC}"
    echo -e "${cyan}│${white}  [0]  EXIT                                            ${cyan}│${NC}"
    echo -e "${cyan}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Select option [0-9]: " choice
    echo ""
    
    case $choice in
        1) update_all ;;
        2) update_ssh ;;
        3) update_xray ;;
        4) update_wsproxy ;;
        5) update_dnstt ;;
        6) update_menu ;;
        7) check_updates ;;
        8) restore_backup ;;
        9) view_logs ;;
        0) 
            echo -e "${green}Exiting...${NC}"
            echo "UPDATE SESSION ENDED: $(date)" >> "$LOG_FILE"
            exit 0 
            ;;
        *) 
            error_msg "Invalid option! Please select 0-9."
            sleep 2
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
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

# Create log files
mkdir -p /var/log
touch "$LOG_FILE"
touch "$STATUS_FILE"
echo "UPDATE SESSION STARTED: $(date)" >> "$LOG_FILE"
echo "UPDATE SESSION: $(date)" > "$STATUS_FILE"

# Main execution
main_menu