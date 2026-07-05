#!/bin/bash
# ============================================================
# SSH BANNER MANAGER
# ============================================================

BANNER_FILE="/etc/ssh/ssh_banner"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

while true; do
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}         SSH BANNER MANAGER${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e " ${GREEN}1${NC} : Edit Banner"
    echo -e " ${GREEN}2${NC} : Replace Banner"
    echo -e " ${GREEN}3${NC} : Restart SSH"
    echo -e " ${GREEN}4${NC} : Exit"
    echo ""
    read -p "Select option [1-4]: " choice

    case $choice in
        1)
            echo -e "\n${YELLOW}Opening editor...${NC}"
            sleep 1
            nano "$BANNER_FILE"
            echo -e "\n${GREEN}✅ Banner saved!${NC}"
            sleep 1
            ;;
        2)
            echo -e "\n${YELLOW}Enter new banner text (type 'DONE' on new line to finish):${NC}"
            temp_file="/tmp/new_banner.txt"
            > "$temp_file"
            while IFS= read -r line; do
                if [[ "$line" == "DONE" ]]; then
                    break
                fi
                echo "$line" >> "$temp_file"
            done
            if [ -s "$temp_file" ]; then
                cp "$temp_file" "$BANNER_FILE"
                echo -e "\n${GREEN}✅ Banner replaced!${NC}"
            else
                echo -e "\n${RED}❌ No text entered.${NC}"
            fi
            rm -f "$temp_file"
            sleep 1
            ;;
        3)
            echo -e "\n${YELLOW}Restarting SSH...${NC}"
            systemctl restart ssh
            sleep 1
            if systemctl is-active --quiet ssh; then
                echo -e "${GREEN}✅ SSH restarted successfully!${NC}"
            else
                echo -e "${RED}❌ SSH failed to restart!${NC}"
            fi
            sleep 2
            ;;
        4)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option!${NC}"
            sleep 1
            ;;
    esac
done