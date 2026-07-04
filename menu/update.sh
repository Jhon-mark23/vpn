#!/bin/bash
# ============================================================
# MARCSCRIPT UPDATE/REINSTALL SCRIPT
# Located at: menu/update.sh
# ============================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success(){ echo -e "${BLUE}[SUCCESS]${NC} $1"; }

# ============================================================
# CHECK ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# ============================================================
# CREATE BACKUP
# ============================================================
create_backup() {
    BACKUP_DIR="/root/backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    print_info "Creating backup in $BACKUP_DIR..."
    
    # Backup configs
    [ -d /etc/xray ] && cp -r /etc/xray "$BACKUP_DIR/" 2>/dev/null
    [ -d /etc/stunnel ] && cp -r /etc/stunnel "$BACKUP_DIR/" 2>/dev/null
    [ -d /etc/nginx ] && cp -r /etc/nginx "$BACKUP_DIR/" 2>/dev/null
    [ -d /etc/squid ] && cp -r /etc/squid "$BACKUP_DIR/" 2>/dev/null
    [ -f /etc/ssh/sshd_config ] && cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null
    [ -f /root/domain ] && cp /root/domain "$BACKUP_DIR/" 2>/dev/null
    [ -f /etc/xray/domain ] && cp /etc/xray/domain "$BACKUP_DIR/" 2>/dev/null
    [ -f /etc/passwd ] && cp /etc/passwd "$BACKUP_DIR/" 2>/dev/null
    [ -f /etc/shadow ] && cp /etc/shadow "$BACKUP_DIR/" 2>/dev/null
    
    print_success "Backup completed at $BACKUP_DIR"
}

# ============================================================
# DOWNLOAD AND RUN SETUP
# ============================================================
run_full_setup() {
    print_info "Downloading latest setup script..."
    cd /root
    
    # Remove old setup
    rm -f setup.sh
    
    # Download new setup
    wget -q -O setup.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh
    if [ $? -ne 0 ]; then
        print_error "Failed to download setup.sh"
        return 1
    fi
    
    chmod +x setup.sh
    sed -i -e 's/\r$//' setup.sh
    
    print_info "Running setup script..."
    bash setup.sh
    return $?
}

# ============================================================
# UPDATE MENU FILES ONLY
# ============================================================
update_menu() {
    print_info "Updating menu scripts only..."
    
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    
    # Menu scripts
    wget -q -O menu "$GHBASE/menu/menu.sh"
    wget -q -O running "$GHBASE/menu/running.sh"
    wget -q -O clearcache "$GHBASE/menu/clearcache.sh"
    wget -q -O m-system "$GHBASE/menu/m-system.sh"
    wget -q -O m-domain "$GHBASE/menu/m-domain.sh"
    wget -q -O m-dns "$GHBASE/menu/m-dns.sh"
    wget -q -O m-tcp "$GHBASE/menu/tcp.sh"
    wget -q -O auto-reboot "$GHBASE/menu/auto-reboot.sh"
    wget -q -O restart "$GHBASE/menu/restart.sh"
    wget -q -O bw "$GHBASE/menu/bw.sh"
    wget -q -O m-vmess "$GHBASE/menu/m-vmess.sh"
    wget -q -O m-vless "$GHBASE/menu/m-vless.sh"
    wget -q -O m-trojan "$GHBASE/menu/m-trojan.sh"
    wget -q -O m-ssws "$GHBASE/menu/m-ssws.sh"
    wget -q -O m-sshovpn "$GHBASE/menu/m-sshovpn.sh"
    wget -q -O m-webmin "$GHBASE/menu/m-webmin.sh"
    wget -q -O m-xray "$GHBASE/menu/m-xray.sh"
    wget -q -O update "$GHBASE/menu/update.sh"
    
    chmod +x menu running clearcache m-system m-domain m-dns m-tcp auto-reboot restart bw
    chmod +x m-vmess m-vless m-trojan m-ssws m-sshovpn m-webmin m-xray update
    
    print_success "Menu scripts updated (18 scripts)"
}

# ============================================================
# UPDATE SSH FILES ONLY
# ============================================================
update_ssh() {
    print_info "Updating SSH scripts only..."
    
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    
    # SSH scripts
    wget -q -O usernew "$GHBASE/ssh/usernew.sh"
    wget -q -O trial "$GHBASE/ssh/trial.sh"
    wget -q -O renew "$GHBASE/ssh/renew.sh"
    wget -q -O hapus "$GHBASE/ssh/hapus.sh"
    wget -q -O cek "$GHBASE/ssh/cek.sh"
    wget -q -O member "$GHBASE/ssh/member.sh"
    wget -q -O delete "$GHBASE/ssh/delete.sh"
    wget -q -O autokill "$GHBASE/ssh/autokill.sh"
    wget -q -O ceklim "$GHBASE/ssh/ceklim.sh"
    wget -q -O tendang "$GHBASE/ssh/tendang.sh"
    wget -q -O add-host "$GHBASE/ssh/add-host.sh"
    wget -q -O xp "$GHBASE/ssh/xp.sh"
    wget -q -O fix-cek "$GHBASE/ssh/fix-cek.sh"
    wget -q -O speedtest "$GHBASE/ssh/speedtest_cli.py"
    wget -q -O ssh-vpn "$GHBASE/ssh/ssh-vpn.sh"
    wget -q -O newudpgw "$GHBASE/ssh/newudpgw"
    
    # SSHWS files (if separate directory)
    wget -q -O insshws "$GHBASE/sshws/insshws.sh" 2>/dev/null
    wget -q -O socks-ssh "$GHBASE/sshws/socks-ssh.py" 2>/dev/null
    
    chmod +x usernew trial renew hapus cek member delete autokill ceklim tendang add-host xp fix-cek speedtest ssh-vpn newudpgw
    chmod +x insshws socks-ssh 2>/dev/null
    
    print_success "SSH scripts updated (17 scripts)"
}

# ============================================================
# UPDATE XRAY FILES ONLY
# ============================================================
update_xray() {
    print_info "Updating Xray scripts only..."
    
    GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
    cd /usr/bin
    
    # VMess/WS scripts
    wget -q -O add-ws "$GHBASE/xray/add-ws.sh"
    wget -q -O trialvmess "$GHBASE/xray/trialvmess.sh"
    wget -q -O renew-ws "$GHBASE/xray/renew-ws.sh"
    wget -q -O del-ws "$GHBASE/xray/del-ws.sh"
    wget -q -O cek-ws "$GHBASE/xray/cek-ws.sh"
    
    # VLess scripts
    wget -q -O add-vless "$GHBASE/xray/add-vless.sh"
    wget -q -O trialvless "$GHBASE/xray/trialvless.sh"
    wget -q -O renew-vless "$GHBASE/xray/renew-vless.sh"
    wget -q -O del-vless "$GHBASE/xray/del-vless.sh"
    wget -q -O cek-vless "$GHBASE/xray/cek-vless.sh"
    
    # Trojan scripts
    wget -q -O add-tr "$GHBASE/xray/add-tr.sh"
    wget -q -O trialtrojan "$GHBASE/xray/trialtrojan.sh"
    wget -q -O renew-tr "$GHBASE/xray/renew-tr.sh"
    wget -q -O del-tr "$GHBASE/xray/del-tr.sh"
    wget -q -O cek-tr "$GHBASE/xray/cek-tr.sh"
    
    # Shadowsocks scripts
    wget -q -O add-ssws "$GHBASE/xray/add-ssws.sh"
    wget -q -O trialssws "$GHBASE/xray/trialssws.sh"
    wget -q -O renew-ssws "$GHBASE/xray/renew-ssws.sh"
    wget -q -O del-ssws "$GHBASE/xray/del-ssws.sh"
    wget -q -O cek-ssws "$GHBASE/xray/cek-ssws.sh"
    
    # Certificate script
    wget -q -O certv2ray "$GHBASE/xray/certv2ray.sh"
    wget -q -O ins-xray "$GHBASE/xray/ins-xray.sh"
    
    chmod +x add-ws trialvmess renew-ws del-ws cek-ws
    chmod +x add-vless trialvless renew-vless del-vless cek-vless
    chmod +x add-tr trialtrojan renew-tr del-tr cek-tr
    chmod +x add-ssws trialssws renew-ssws del-ssws cek-ssws
    chmod +x certv2ray ins-xray
    
    print_success "Xray scripts updated (22 scripts)"
}

# ============================================================
# SHOW SUMMARY
# ============================================================
show_summary() {
    local update_type="$1"
    local backup_loc="$2"
    
    clear
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${GREEN}                  ✅ UPDATE COMPLETED!                     ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}                   📋 UPDATE SUMMARY${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    case "$update_type" in
        "1")
            echo -e "${GREEN}  ✅ Full System Update     : Complete${NC}"
            echo -e "${GREEN}  ✅ Setup Script           : Updated${NC}"
            echo -e "${GREEN}  ✅ Menu Scripts           : Updated (18 scripts)${NC}"
            echo -e "${GREEN}  ✅ SSH Scripts            : Updated (17 scripts)${NC}"
            echo -e "${GREEN}  ✅ Xray Scripts           : Updated (22 scripts)${NC}"
            ;;
        "2")
            echo -e "${GREEN}  ✅ SSH Scripts Only       : Updated (17 scripts)${NC}"
            echo -e "${YELLOW}  ⚠️  Menu & Xray unchanged  : Skipped${NC}"
            ;;
        "3")
            echo -e "${GREEN}  ✅ Xray Scripts Only      : Updated (22 scripts)${NC}"
            echo -e "${YELLOW}  ⚠️  Menu & SSH unchanged   : Skipped${NC}"
            ;;
        "4")
            echo -e "${GREEN}  ✅ Menu Scripts Only      : Updated (18 scripts)${NC}"
            echo -e "${YELLOW}  ⚠️  SSH & Xray unchanged   : Skipped${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}  📁 Backup Location   : $backup_loc${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}                   🔧 MANAGEMENT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}menu${NC}         - Main menu"
    echo -e "  ${GREEN}usernew${NC}     - Create SSH user"
    echo -e "  ${GREEN}running${NC}     - Check service status"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}           THANK YOU FOR USING MARCSCRIPT!              ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# MAIN MENU
# ============================================================
clear
echo ""
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${CYAN}                   🔄 UPDATE SYSTEM                        ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}Select update option:${NC}"
echo ""
echo -e "  ${GREEN}1)${NC} Update ${WHITE}ALL SERVICES${NC}      - Full system update (setup + scripts)"
echo -e "  ${GREEN}2)${NC} Update ${WHITE}SSH ONLY${NC}          - Update SSH/SSHWS scripts only"
echo -e "  ${GREEN}3)${NC} Update ${WHITE}XRAY ONLY${NC}         - Update Xray/V2Ray scripts only"
echo -e "  ${GREEN}4)${NC} Update ${WHITE}MENU ONLY${NC}         - Update menu files only"
echo -e "  ${RED}0)${NC} ${RED}Cancel${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}⚠️  Backup will be created before any update${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "  Enter your choice [0-4]: " choice

case $choice in
    0)
        echo -e "${YELLOW}Update cancelled by user${NC}"
        exit 0
        ;;
    1)
        # FULL UPDATE
        create_backup
        run_full_setup
        if [ $? -eq 0 ]; then
            update_menu
            update_ssh
            update_xray
            show_summary "1" "$BACKUP_DIR"
        else
            print_error "Full setup failed. Please check your connection and try again."
            exit 1
        fi
        ;;
    2)
        # SSH ONLY
        create_backup
        update_ssh
        show_summary "2" "$BACKUP_DIR"
        ;;
    3)
        # XRAY ONLY
        create_backup
        update_xray
        show_summary "3" "$BACKUP_DIR"
        ;;
    4)
        # MENU ONLY
        create_backup
        update_menu
        show_summary "4" "$BACKUP_DIR"
        ;;
    *)
        echo -e "${RED}Invalid choice! Please select 0-4${NC}"
        exit 1
        ;;
esac

exit 0