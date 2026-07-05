#!/bin/bash
# ============================================================
# MARCSCRIPT VPN SYSTEM - UPDATE MANAGER v3.1
# Modular Architecture • Nginx Unified Proxy • Fast Updates
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
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BWhite='\e[1;37m'
BPurple='\e[1;35m'
BCyan='\e[1;36m'
NC='\033[0m'

# ---------- CONFIGURATION ----------
GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/marcscript-update.log"
VERSION="3.1"

# ---------- FUNCTIONS ----------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

success_msg() {
    echo -e "${green}✓${NC} $1"
    log "SUCCESS: $1"
}

error_msg() {
    echo -e "${red}✗${NC} $1"
    log "ERROR: $1"
}

info_msg() {
    echo -e "${cyan}→${NC} $1"
}

dl() {
    local dest="$1"
    local url="$GHBASE/$2"
    
    wget -q -O "$dest" "$url" 2>/dev/null
    if [ $? -eq 0 ]; then
        chmod +x "$dest" 2>/dev/null
        sed -i 's/\r$//' "$dest" 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Create backup of all important files
create_backup() {
    info_msg "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup system configs
    cp /etc/xray/config.json "$BACKUP_DIR/" 2>/dev/null
    cp /etc/xray/domain "$BACKUP_DIR/" 2>/dev/null
    cp /etc/nginx/nginx.conf "$BACKUP_DIR/" 2>/dev/null
    cp -r /etc/nginx/conf.d "$BACKUP_DIR/" 2>/dev/null
    cp -r /etc/nginx/stream.d "$BACKUP_DIR/" 2>/dev/null
    cp /etc/stunnel/stunnel.conf "$BACKUP_DIR/" 2>/dev/null
    cp /etc/squid/squid.conf "$BACKUP_DIR/" 2>/dev/null
    cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null
    cp /etc/default/dropbear "$BACKUP_DIR/" 2>/dev/null
    
    # Backup scripts
    cp -r /usr/bin/menu "$BACKUP_DIR/" 2>/dev/null
    cp /usr/local/bin/ws-dropbear "$BACKUP_DIR/" 2>/dev/null
    cp /usr/local/bin/ws-stunnel "$BACKUP_DIR/" 2>/dev/null
    cp /usr/local/bin/xray "$BACKUP_DIR/" 2>/dev/null
    
    # Backup user data
    cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
    cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
    cp /root/domain.txt "$BACKUP_DIR/" 2>/dev/null
    
    success_msg "Backup saved: $BACKUP_DIR"
}

# Restart all services safely
restart_all_services() {
    info_msg "Restarting services..."
    local services=(
        "ssh" "dropbear" "stunnel4" "ws-proxy"
        "ws-dropbear" "ws-stunnel" "xray" "nginx" "squid"
        "fail2ban" "cron"
    )
    
    for svc in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            systemctl restart "$svc" 2>/dev/null && success_msg "Restarted $svc" || error_msg "Failed: $svc"
        fi
    done
    
    # BADVPN via systemd or screen
    for port in 7100 7200 7300 7400; do
        instance=$((port/100))
        if systemctl is-active --quiet badvpn-${instance} 2>/dev/null; then
            systemctl restart badvpn-${instance} 2>/dev/null
        elif screen -list 2>/dev/null | grep -q "badvpn${instance}"; then
            screen -S badvpn${instance} -X quit 2>/dev/null
            screen -dmS badvpn${instance} /usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:${port} --max-clients 50
        fi
    done
}

# ============================================================
# UPDATE FUNCTIONS
# ============================================================

# Update ALL
update_all() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}              🔄 UPDATE ALL COMPONENTS                    ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   This will update:"
    echo -e "   ${BYellow}•${NC} Menu & Management Scripts"
    echo -e "   ${BYellow}•${NC} SSH/Dropbear/Stunnel Scripts"
    echo -e "   ${BYellow}•${NC} Xray Core & Scripts"
    echo -e "   ${BYellow}•${NC} WebSocket Proxy Scripts"
    echo -e "   ${BYellow}•${NC} Nginx Reverse Proxy Config"
    echo -e "   ${BYellow}•${NC} DNSTT Scripts"
    echo ""
    
    read -p "Continue with full update? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Update cancelled.${NC}"
        return
    fi
    
    create_backup
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 1/6: Updating Menu & Management Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    update_menu
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 2/6: Updating SSH Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    update_ssh_scripts
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 3/6: Updating Xray Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    update_xray_scripts
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 4/6: Updating WebSocket Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    update_ws_scripts
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 5/6: Updating Nginx Config${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    update_nginx_config
    
    echo ""
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  STEP 6/6: Restarting All Services${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    restart_all_services
    
    echo ""
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BGreen}              ✅ ALL UPDATES COMPLETE!                    ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Update Menu & Management Scripts
update_menu() {
    info_msg "Downloading menu scripts..."
    local count=0
    local fail=0
    
    dl "/usr/bin/menu" "menu/menu.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-sshovpn" "menu/m-sshovpn.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-vmess" "menu/m-vmess.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-vless" "menu/m-vless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-trojan" "menu/m-trojan.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-ssws" "menu/m-ssws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/m-system" "menu/m-system.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/running" "menu/running.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/clearcache" "menu/clearcache.sh" && ((count++)) || ((fail++))
    dl "/usr/local/bin/vpn-status" "menu/vpn-status.sh" && ((count++)) || ((fail++))
    
    success_msg "Menu: $count updated, $fail failed"
}

# Update SSH Scripts
update_ssh_scripts() {
    info_msg "Downloading SSH scripts..."
    local count=0
    local fail=0
    
    dl "/usr/bin/usernew" "ssh/usernew.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/trial" "ssh/trial.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/renew" "ssh/renew.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/hapus" "ssh/hapus.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/cek" "ssh/cek.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/member" "ssh/member.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/delete" "ssh/delete.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/autokill" "ssh/autokill.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/ceklim" "ssh/ceklim.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/tendang" "ssh/tendang.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/sshws" "ssh/sshws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/add-host" "ssh/add-host.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/xp" "ssh/xp.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/speedtest" "ssh/speedtest_cli.py" && ((count++)) || ((fail++))
    
    success_msg "SSH: $count updated, $fail failed"
}

# Update Xray Scripts
update_xray_scripts() {
    info_msg "Downloading Xray scripts..."
    local count=0
    local fail=0
    
    dl "/usr/bin/add-ws" "xray/add-ws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/add-vless" "xray/add-vless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/add-tr" "xray/add-tr.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/add-ssws" "xray/add-ssws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/del-ws" "xray/del-ws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/del-vless" "xray/del-vless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/del-tr" "xray/del-tr.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/del-ssws" "xray/del-ssws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/renew-ws" "xray/renew-ws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/renew-vless" "xray/renew-vless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/renew-tr" "xray/renew-tr.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/renew-ssws" "xray/renew-ssws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/cek-ws" "xray/cek-ws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/cek-vless" "xray/cek-vless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/cek-tr" "xray/cek-tr.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/cek-ssws" "xray/cek-ssws.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/trialvmess" "xray/trialvmess.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/trialvless" "xray/trialvless.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/trialtrojan" "xray/trialtrojan.sh" && ((count++)) || ((fail++))
    dl "/usr/bin/trialssws" "xray/trialssws.sh" && ((count++)) || ((fail++))
    dl "/usr/local/bin/xray-info" "xray/xray-info.sh" && ((count++)) || ((fail++))
    
    # Update Xray core if installed
    if command -v xray &>/dev/null; then
        info_msg "Updating Xray core..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null && \
            success_msg "Xray core updated" || \
            error_msg "Xray core update failed"
    fi
    
    success_msg "Xray: $count scripts updated, $fail failed"
}

# Update WebSocket Scripts
update_ws_scripts() {
    info_msg "Downloading WebSocket scripts..."
    local count=0
    local fail=0
    
    dl "/usr/local/bin/ws-dropbear" "sshws/ws-dropbear.py" && ((count++)) || ((fail++))
    dl "/usr/local/bin/ws-stunnel" "sshws/ws-stunnel.py" && ((count++)) || ((fail++))
    dl "/usr/local/bin/proxy-status" "sshws/proxy-status.sh" && ((count++)) || ((fail++))
    dl "/usr/local/bin/proxy-restart" "sshws/proxy-restart.sh" && ((count++)) || ((fail++))
    
    success_msg "WebSocket: $count updated, $fail failed"
}

# Update Nginx Configuration
update_nginx_config() {
    info_msg "Updating Nginx reverse proxy config..."
    
    if [ -f /etc/nginx/nginx.conf ]; then
        # Backup current config
        cp /etc/nginx/nginx.conf "$BACKUP_DIR/nginx.conf"
        cp -r /etc/nginx/conf.d "$BACKUP_DIR/conf.d" 2>/dev/null
        cp -r /etc/nginx/stream.d "$BACKUP_DIR/stream.d" 2>/dev/null
        
        # Download latest nginx-setup.sh
        dl "/root/nginx-setup.sh" "nginx/nginx-setup.sh"
        
        if [ -f /root/nginx-setup.sh ]; then
            info_msg "Running nginx-setup.sh in auto mode..."
            echo "1" | bash /root/nginx-setup.sh 2>/dev/null && \
                success_msg "Nginx config updated" || \
                error_msg "Nginx config update failed"
            rm -f /root/nginx-setup.sh
        fi
    else
        info_msg "Nginx not installed - skipping"
    fi
}

# ============================================================
# INDIVIDUAL UPDATES
# ============================================================

update_menu_only() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  Updating Menu & Management Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    create_backup
    update_menu
    success_msg "Menu updated!"
}

update_ssh_only() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  Updating SSH Scripts${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    create_backup
    update_ssh_scripts
    systemctl restart ssh dropbear 2>/dev/null
    success_msg "SSH scripts updated!"
}

update_xray_only() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  Updating Xray Scripts & Core${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    create_backup
    update_xray_scripts
    systemctl restart xray 2>/dev/null
    success_msg "Xray updated!"
}

update_nginx_only() {
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}  Updating Nginx Configuration${NC}"
    echo -e "${BCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    create_backup
    update_nginx_config
    systemctl restart nginx 2>/dev/null
    success_msg "Nginx updated!"
}

# Check for updates
check_updates() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}              🔍 CHECK FOR UPDATES                       ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check local version
    if [ -f /opt/.ver ]; then
        current_version=$(cat /opt/.ver)
    else
        current_version="unknown"
    fi
    
    # Check remote version
    latest_version=$(curl -s --max-time 5 "$GHBASE/menu/versi" 2>/dev/null || echo "unknown")
    
    echo -e "   Current version : ${yellow}$current_version${NC}"
    echo -e "   Latest version  : ${green}$latest_version${NC}"
    echo -e "   Update Manager  : ${green}v${VERSION}${NC}"
    echo ""
    
    if [ "$current_version" != "$latest_version" ] && [ "$latest_version" != "unknown" ]; then
        echo -e "   ${green}✓ New version available! Run option 1 to update.${NC}"
    elif [ "$latest_version" = "unknown" ]; then
        echo -e "   ${yellow}⚠ Cannot check remote version (no internet?)${NC}"
    else
        echo -e "   ${green}✓ You have the latest version.${NC}"
    fi
    
    # Check individual components
    echo ""
    echo -e "   ${BWhite}Installed Components:${NC}"
    command -v xray &>/dev/null && echo -e "   ${green}✓${NC} Xray" || echo -e "   ${red}✗${NC} Xray"
    systemctl is-active --quiet nginx 2>/dev/null && echo -e "   ${green}✓${NC} Nginx" || echo -e "   ${red}✗${NC} Nginx"
    systemctl is-active --quiet squid 2>/dev/null && echo -e "   ${green}✓${NC} Squid" || echo -e "   ${red}✗${NC} Squid"
    systemctl is-active --quiet dropbear 2>/dev/null && echo -e "   ${green}✓${NC} Dropbear" || echo -e "   ${red}✗${NC} Dropbear"
    systemctl is-active --quiet stunnel4 2>/dev/null && echo -e "   ${green}✓${NC} Stunnel4" || echo -e "   ${red}✗${NC} Stunnel4"
    echo ""
}

# Restore from backup
restore_backup() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}              🔄 RESTORE FROM BACKUP                     ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local backups=($(ls -dt /root/backup_* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        error_msg "No backups found!"
        return
    fi
    
    echo -e "${yellow}Available backups:${NC}"
    for i in "${!backups[@]}"; do
        local backup_date=$(basename "${backups[$i]}" | sed 's/backup_//')
        local backup_size=$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)
        echo -e "  ${green}$((i+1))${NC}. ${backup_date} (${backup_size})"
    done
    echo ""
    
    read -p "Select backup [1-${#backups[@]}] or 0 to cancel: " choice
    
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    choice=$((choice-1))
    if [ -z "${backups[$choice]}" ]; then
        error_msg "Invalid selection!"
        return
    fi
    
    local selected="${backups[$choice]}"
    echo ""
    echo -e "${red}⚠ WARNING: This will overwrite current configuration!${NC}"
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Restore cancelled.${NC}"
        return
    fi
    
    info_msg "Restoring from: $selected"
    
    # Restore configs
    [ -f "$selected/config.json" ] && cp "$selected/config.json" /etc/xray/ && success_msg "Xray config restored"
    [ -f "$selected/nginx.conf" ] && cp "$selected/nginx.conf" /etc/nginx/ && success_msg "Nginx config restored"
    [ -d "$selected/conf.d" ] && cp -r "$selected/conf.d"/* /etc/nginx/conf.d/ && success_msg "Nginx conf.d restored"
    [ -d "$selected/stream.d" ] && cp -r "$selected/stream.d"/* /etc/nginx/stream.d/ && success_msg "Nginx stream.d restored"
    [ -f "$selected/stunnel.conf" ] && cp "$selected/stunnel.conf" /etc/stunnel/ && success_msg "Stunnel config restored"
    [ -f "$selected/squid.conf" ] && cp "$selected/squid.conf" /etc/squid/ && success_msg "Squid config restored"
    [ -f "$selected/sshd_config" ] && cp "$selected/sshd_config" /etc/ssh/ && success_msg "SSH config restored"
    [ -f "$selected/dropbear" ] && cp "$selected/dropbear" /etc/default/dropbear && success_msg "Dropbear config restored"
    [ -f "$selected/domain.txt" ] && cp "$selected/domain.txt" /root/ && success_msg "Domain restored"
    
    # Restart services
    restart_all_services
    
    success_msg "Backup restored successfully!"
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    clear
    echo -e "${BPurple}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BPurple}║${BWhite}     ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}     ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}      ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${BPurple}║${NC}"
    echo -e "${BPurple}║${BCyan}              • UPDATE MANAGER v${VERSION} •                   ${BPurple}║${NC}"
    echo -e "${BPurple}║${BWhite}        Modular • Nginx Proxy • No Conflicts             ${BPurple}║${NC}"
    echo -e "${BPurple}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BGreen}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BGreen}│${BWhite}  [1] UPDATE ALL (Menu + SSH + Xray + WS + Nginx)       ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [2] Update Menu & Management Scripts Only             ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [3] Update SSH Scripts Only                           ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [4] Update Xray Scripts & Core Only                   ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [5] Update Nginx Config Only                          ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [6] Check for Updates                                 ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [7] Restore from Backup                               ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [8] Restart All Services                              ${BGreen}│${NC}"
    echo -e "${BGreen}│${BWhite}  [0] Exit                                              ${BGreen}│${NC}"
    echo -e "${BGreen}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Select option [0-8]: " choice
    echo ""
    
    case $choice in
        1) update_all ;;
        2) update_menu_only ;;
        3) update_ssh_only ;;
        4) update_xray_only ;;
        5) update_nginx_only ;;
        6) check_updates ;;
        7) restore_backup ;;
        8) restart_all_services ;;
        0) clear; echo -e "${green}Exiting...${NC}"; exit 0 ;;
        *) 
            error_msg "Invalid option!"
            sleep 1
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    main_menu
}

# ============================================================
# START
# ============================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}✗ This script must be run as root!${NC}"
    exit 1
fi

touch "$LOG_FILE"
main_menu