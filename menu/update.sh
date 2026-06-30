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

print_success "Backup completed at $BACKUP_DIR"

# ============================================================
# DOWNLOAD AND RUN SETUP
# ============================================================
print_info "Downloading latest setup script..."
cd /root

# Remove old setup
rm -f setup.sh

# Download new setup
wget -q -O setup.sh https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main/setup.sh
if [ $? -ne 0 ]; then
    print_error "Failed to download setup.sh"
    exit 1
fi

chmod +x setup.sh
sed -i -e 's/\r$//' setup.sh

print_info "Running setup script..."
bash setup.sh

# ============================================================
# UPDATE ALL SCRIPTS
# ============================================================
print_info "Updating all scripts..."

GHBASE="https://raw.githubusercontent.com/Jhon-mark23/vpn/refs/heads/main"
cd /usr/bin

# Menu scripts
print_info "Updating menu scripts..."
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

chmod +x menu running clearcache m-system m-domain m-dns m-tcp auto-reboot restart bw
chmod +x m-vmess m-vless m-trojan m-ssws m-sshovpn

# SSH scripts
print_info "Updating SSH scripts..."
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
wget -q -O sshws "$GHBASE/ssh/sshws.sh"
wget -q -O add-host "$GHBASE/ssh/add-host.sh"
wget -q -O xp "$GHBASE/ssh/xp.sh"
wget -q -O fix-cek "$GHBASE/ssh/fix-cek.sh"
wget -q -O speedtest "$GHBASE/ssh/speedtest_cli.py"

chmod +x usernew trial renew hapus cek member delete autokill ceklim tendang sshws add-host xp fix-cek speedtest

# Xray scripts
print_info "Updating Xray scripts..."
wget -q -O add-ws "$GHBASE/xray/add-ws.sh"
wget -q -O trialvmess "$GHBASE/xray/trialvmess.sh"
wget -q -O renew-ws "$GHBASE/xray/renew-ws.sh"
wget -q -O del-ws "$GHBASE/xray/del-ws.sh"
wget -q -O cek-ws "$GHBASE/xray/cek-ws.sh"

wget -q -O add-vless "$GHBASE/xray/add-vless.sh"
wget -q -O trialvless "$GHBASE/xray/trialvless.sh"
wget -q -O renew-vless "$GHBASE/xray/renew-vless.sh"
wget -q -O del-vless "$GHBASE/xray/del-vless.sh"
wget -q -O cek-vless "$GHBASE/xray/cek-vless.sh"

wget -q -O add-tr "$GHBASE/xray/add-tr.sh"
wget -q -O trialtrojan "$GHBASE/xray/trialtrojan.sh"
wget -q -O del-tr "$GHBASE/xray/del-tr.sh"
wget -q -O renew-tr "$GHBASE/xray/renew-tr.sh"
wget -q -O cek-tr "$GHBASE/xray/cek-tr.sh"

wget -q -O add-ssws "$GHBASE/xray/add-ssws.sh"
wget -q -O trialssws "$GHBASE/xray/trialssws.sh"
wget -q -O del-ssws "$GHBASE/xray/del-ssws.sh"
wget -q -O renew-ssws "$GHBASE/xray/renew-ssws.sh"
wget -q -O cek-ssws "$GHBASE/xray/cek-ssws.sh"

chmod +x add-ws trialvmess renew-ws del-ws cek-ws
chmod +x add-vless trialvless renew-vless del-vless cek-vless
chmod +x add-tr trialtrojan del-tr renew-tr cek-tr
chmod +x add-ssws trialssws del-ssws renew-ssws cek-ssws

# Certificate script
wget -q -O certv2ray "$GHBASE/xray/certv2ray.sh"
chmod +x certv2ray

print_success "All scripts updated"

# ============================================================
# FINALIZE
# ============================================================
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
echo -e "${GREEN}  ✅ Setup Script       : Updated${NC}"
echo -e "${GREEN}  ✅ Menu Scripts       : Updated (15 scripts)${NC}"
echo -e "${GREEN}  ✅ SSH Scripts        : Updated (15 scripts)${NC}"
echo -e "${GREEN}  ✅ Xray Scripts       : Updated (21 scripts)${NC}"
echo -e "${GREEN}  ✅ Management Scripts : Updated${NC}"
echo ""
echo -e "${YELLOW}  📁 Backup Location   : $BACKUP_DIR${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                   🔧 MANAGEMENT${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}menu${NC}         - Main menu"
echo -e "  ${GREEN}create${NC}       - Create SSH user"
echo -e "  ${GREEN}vpn-status${NC}   - Check service status"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}           THANK YOU FOR USING MARCSCRIPT!              ${PURPLE}║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

exit 0