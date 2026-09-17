#!/bin/bash

set -e

# ============================================================
# FirewallFalcon Manager — Installer
# Repozytorium: https://github.com/taifunss/moj-manager
# ============================================================

REPO="taifunss/moj-manager"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"

MENU_URL="${RAW_BASE}/menu.sh"
SSHD_URL="${RAW_BASE}/ssh"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Sprawdź root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Ten skrypt musi być uruchomiony jako root.${NC}"
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   🦅 FirewallFalcon Manager Installer    ║${NC}"
echo -e "${BLUE}║   github.com/${REPO}  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo

# Sprawdź zależności
echo -e "${BLUE}🔍 Sprawdzanie zależności...${NC}"
for cmd in wget curl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${YELLOW}⚙️ Instaluję: $cmd${NC}"
        apt-get update -qq && apt-get install -y $cmd -qq || {
            echo -e "${RED}❌ Nie udało się zainstalować $cmd.${NC}"
            exit 1
        }
    fi
done
echo -e "${GREEN}✅ Zależności OK.${NC}"

# Pobierz menu
echo -e "\n${BLUE}📥 Pobieranie FirewallFalcon menu z ${REPO}...${NC}"
wget -4 -q -O /usr/local/bin/menu "$MENU_URL" || {
    echo -e "${RED}❌ Nie udało się pobrać menu.sh.${NC}"
    echo -e "${YELLOW}   Sprawdź czy plik istnieje: ${MENU_URL}${NC}"
    exit 1
}
chmod +x /usr/local/bin/menu
echo -e "${GREEN}✅ Menu zainstalowane w /usr/local/bin/menu${NC}"

# Konfiguracja SSH
echo -e "\n${BLUE}🔧 Konfiguracja SSH...${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)"

# Backup
cp "$SSHD_CONFIG" "$BACKUP"
echo -e "${GREEN}✅ Backup sshd_config: $BACKUP${NC}"

# Pobierz konfigurację SSH
wget -4 -q -O "$SSHD_CONFIG" "$SSHD_URL" || {
    echo -e "${YELLOW}⚠️ Nie udało się pobrać konfiguracji SSH — przywracam backup.${NC}"
    cp "$BACKUP" "$SSHD_CONFIG"
}
chmod 600 "$SSHD_CONFIG"

# Walidacja SSH
if ! sshd -t 2>/dev/null; then
    echo -e "${RED}❌ Konfiguracja SSH jest nieprawidłowa — przywracam backup.${NC}"
    cp "$BACKUP" "$SSHD_CONFIG"
else
    echo -e "${GREEN}✅ Konfiguracja SSH zwalidowana.${NC}"
fi

# Restart SSH
restart_ssh() {
    if command -v systemctl &>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || return 1
    elif command -v service &>/dev/null; then
        service sshd restart 2>/dev/null || service ssh restart 2>/dev/null || return 1
    else
        return 1
    fi
}

echo -e "\n${BLUE}🔄 Restartowanie SSH...${NC}"
if restart_ssh; then
    echo -e "${GREEN}✅ SSH zrestartowany.${NC}"
else
    echo -e "${YELLOW}⚠️ Nie udało się zrestartować SSH automatycznie.${NC}"
fi

# Uruchom setup FirewallFalcon
echo -e "\n${BLUE}⚙️ Uruchamianie setup FirewallFalcon...${NC}"
bash /usr/local/bin/menu --install-setup

echo -e "\n${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Instalacja zakończona pomyślnie!    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo -e "\n   Wpisz ${YELLOW}menu${NC} aby uruchomić FirewallFalcon Manager.\n"
