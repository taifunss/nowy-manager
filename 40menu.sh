#!/bin/bash

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# Premium Color Palette
C_RED=$'\033[38;5;196m'      # Bright Red
C_GREEN=$'\033[38;5;46m'     # Neon Green
C_YELLOW=$'\033[38;5;226m'   # Bright Yellow
C_BLUE=$'\033[38;5;39m'      # Deep Sky Blue
C_PURPLE=$'\033[38;5;135m'   # Light Purple
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;208m'   # Orange

# Semantic Aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

DB_DIR="/etc/firewallfalcon"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"
BADVPN_SERVICE_FILE="/etc/systemd/system/badvpn.service"
BADVPN_BUILD_DIR="/root/badvpn-build"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"
SSL_CERT_DIR="/etc/firewallfalcon/ssl"
SSL_CERT_FILE="$SSL_CERT_DIR/firewallfalcon.pem"
SSL_CERT_CHAIN_FILE="$SSL_CERT_DIR/firewallfalcon.crt"
SSL_CERT_KEY_FILE="$SSL_CERT_DIR/firewallfalcon.key"
EDGE_CERT_INFO_FILE="$DB_DIR/edge_cert.conf"
NGINX_PORTS_FILE="$DB_DIR/nginx_ports.conf"
EDGE_PUBLIC_HTTP_PORT="80"
EDGE_PUBLIC_TLS_PORT="443"
NGINX_INTERNAL_HTTP_PORT="8880"
NGINX_INTERNAL_TLS_PORT="8443"
HAPROXY_INTERNAL_DECRYPT_PORT="10443"
DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="/etc/firewallfalcon/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"
UDP_CUSTOM_DIR="/root/udp"
UDP_CUSTOM_SERVICE_FILE="/etc/systemd/system/udp-custom.service"
SSH_BANNER_FILE="/etc/bannerssh"
FALCONPROXY_SERVICE_FILE="/etc/systemd/system/falconproxy.service"
FALCONPROXY_BINARY="/usr/local/bin/falconproxy"
FALCONPROXY_CONFIG_FILE="$DB_DIR/falconproxy_config.conf"
LIMITER_SCRIPT="/usr/local/bin/firewallfalcon-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/firewallfalcon-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
STATS_DIR="$DB_DIR/stats"
BANDWIDTH_SCRIPT="/usr/local/bin/firewallfalcon-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/firewallfalcon-bandwidth.service"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/firewallfalcon-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/firewallfalcon-login-info.sh"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/firewallfalcon.conf"

# --- ZiVPN Variables ---
ZIVPN_DIR="/etc/zivpn"
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE_FILE="/etc/systemd/system/zivpn.service"
ZIVPN_CONFIG_FILE="$ZIVPN_DIR/config.json"
ZIVPN_CERT_FILE="$ZIVPN_DIR/zivpn.crt"
ZIVPN_KEY_FILE="$ZIVPN_DIR/zivpn.key"

DESEC_TOKEN="V55cFY8zTictLCPfviiuX5DHjs15"
DESEC_DOMAIN="manager.firewallfalcon.qzz.io"
# Jeśli istnieje plik z tokenem, wczytaj z niego (nadpisuje powyższe)
_DESEC_CONF="/etc/firewallfalcon/desec.conf"
if [[ -f "$_DESEC_CONF" ]]; then
    source "$_DESEC_CONF"
fi

SELECTED_USER=""
UNINSTALL_MODE="interactive"
BANNER_CACHE_TTL=15
BANNER_CACHE_TS=0
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE=""
BANNER_CACHE_CPU_LOAD=""
BANNER_CACHE_ONLINE_USERS=0
BANNER_CACHE_TOTAL_USERS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
FF_USERS_GROUP="ffusers"
declare -A SSH_SESSION_COUNTS=()
declare -A SSH_SESSION_PIDS=()

if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
   exit 1
fi

# Mandatory Dependency Check (Added jq and curl)
check_environment() {
    # Mandatory Dependency Check (Added jq and curl)
    for cmd in bc jq curl wget; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${C_YELLOW}⚠️ Warning: '$cmd' not found. Installing...${C_RESET}"
            apt-get update > /dev/null 2>&1 && apt-get install -y $cmd || {
                echo -e "${C_RED}❌ Error: Failed to install '$cmd'. Please install it manually.${C_RESET}"
                exit 1
            }
        fi
    done
}

ensure_firewallfalcon_dirs() {
    mkdir -p "$DB_DIR" "$SSL_CERT_DIR" "$BANDWIDTH_DIR" "$STATS_DIR" /etc/ssh/sshd_config.d
    touch "$DB_FILE"
    chmod 600 "$DB_FILE"
    chmod 700 "$DB_DIR"
}

ensure_firewallfalcon_system_group() {
    getent group "$FF_USERS_GROUP" >/dev/null 2>&1 || groupadd "$FF_USERS_GROUP" >/dev/null 2>&1 || true
}

db_has_user() {
    [[ -f "$DB_FILE" ]] || return 1
    awk -F: -v target="$1" '$1 == target { found=1; exit } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

# Bezpieczna aktualizacja linii w DB — odporna na znaki specjalne w hasłach (/,&,\)
db_update_user() {
    local username="$1" new_pass="$2" new_expiry="$3" new_limit="$4" new_bw="$5"
    [[ -f "$DB_FILE" ]] || return 1
    local tmp
    tmp=$(mktemp) || return 1
    awk -F: -v u="$username" -v p="$new_pass" -v e="$new_expiry" -v l="$new_limit" -v b="$new_bw" '
        $1 == u { print u ":" p ":" e ":" l ":" b; next }
        { print }
    ' "$DB_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp"
    sync "$tmp" 2>/dev/null || true
    mv "$tmp" "$DB_FILE" || { rm -f "$tmp"; return 1; }
}

is_firewallfalcon_orphan_user() {
    local username="$1"
    local passwd_line system_user _ uid _ home shell

    passwd_line=$(getent passwd "$username" 2>/dev/null) || return 1
    IFS=: read -r system_user _ uid _ _ home shell <<< "$passwd_line"
    [[ "$uid" =~ ^[0-9]+$ ]] || return 1
    db_has_user "$username" && return 1

    if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$FF_USERS_GROUP"; then
        return 0
    fi

    (( uid >= 1000 )) || return 1
    [[ "$home" == "/home/$username" || "$home" == /home/* ]] || return 1

    case "$shell" in
        /usr/sbin/nologin|/usr/bin/false|/bin/false) return 0 ;;
    esac

    return 1
}

get_firewallfalcon_orphan_users() {
    local username
    while IFS=: read -r username _rest; do
        [[ -n "$username" ]] || continue
        if is_firewallfalcon_orphan_user "$username"; then
            echo "$username"
        fi
    done < /etc/passwd
}

get_firewallfalcon_known_users() {
    local username
    local -A seen_users=()

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r username _rest; do
            [[ -n "$username" && "$username" != \#* ]] || continue
            seen_users["$username"]=1
        done < "$DB_FILE"
    fi

    while IFS= read -r username; do
        [[ -n "$username" ]] && seen_users["$username"]=1
    done < <(get_firewallfalcon_orphan_users)

    (( ${#seen_users[@]} > 0 )) || return 0
    printf "%s\n" "${!seen_users[@]}" | sort
}

delete_firewallfalcon_user_accounts() {
    local -a users_to_delete=("$@")
    local username

    [[ ${#users_to_delete[@]} -gt 0 ]] || return 0

    for username in "${users_to_delete[@]}"; do
        [[ -n "$username" ]] || continue
        killall -u "$username" -9 &>/dev/null
        if id "$username" &>/dev/null; then
            if userdel -r "$username" &>/dev/null; then
                echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted."
            else
                echo -e " ❌ Failed to delete system user '${C_YELLOW}$username${C_RESET}'."
            fi
        else
            echo -e " ℹ️ System user '${C_YELLOW}$username${C_RESET}' was already missing. Removing manager data only."
        fi
        rm -f "$BANDWIDTH_DIR/${username}.usage"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
    done

    if [[ -f "$DB_FILE" ]]; then
        local db_tmp
        db_tmp=$(mktemp)
        awk -F: 'NR==FNR { drop[$1]=1; next } !($1 in drop)' <(printf "%s\n" "${users_to_delete[@]}") "$DB_FILE" > "$db_tmp" && mv "$db_tmp" "$DB_FILE"
        rm -f "$db_tmp" 2>/dev/null
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

require_interactive_terminal() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo -e "${C_RED}❌ Error: The FirewallFalcon menu must be run from an interactive terminal.${C_RESET}"
        exit 1
    fi
}

initial_setup() {
    echo -e "${C_BLUE}⚙️ Initializing FirewallFalcon Manager setup...${C_RESET}"
    check_environment
    
    ensure_firewallfalcon_dirs
    ensure_firewallfalcon_system_group

    # Skonfiguruj SSH keepalive — kluczowe dla poprawnego liczenia sesji
    # ClientAliveInterval=15: sshd wysyła keepalive co 15s
    # ClientAliveCountMax=4: po 4 braku odpowiedzi (60s) zamyka sesję
    # Bez tego [priv] może żyć kilka minut po rozłączeniu przez HAProxy/Nginx
    # co powoduje fałszywe liczenie sesji i błędne bany
    echo -e "${C_BLUE}🔹 Configuring SSH keepalive (prevents ghost sessions)...${C_RESET}"
    local sshd_ff_keepalive="/etc/ssh/sshd_config.d/firewallfalcon-keepalive.conf"
    mkdir -p /etc/ssh/sshd_config.d
    cat > "$sshd_ff_keepalive" << 'SSHEOF'
# FirewallFalcon — SSH keepalive settings
# Szybkie wykrywanie martwych połączeń (przez HAProxy/Nginx tunel)
# [priv] proces ginie w ~60s po rozłączeniu klienta
TCPKeepAlive yes
ClientAliveInterval 15
ClientAliveCountMax 4
SSHEOF
    chmod 644 "$sshd_ff_keepalive"
    if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    echo -e "${C_GREEN}✅ SSH keepalive: 15s interval, 4 retries (dead session detected in ~60s)${C_RESET}"
    
    echo -e "${C_BLUE}🔹 Configuring user limiter service...${C_RESET}"
    setup_limiter_service
    
    echo -e "${C_BLUE}🔹 Configuring bandwidth monitoring service...${C_RESET}"
    setup_bandwidth_service
    
    echo -e "${C_BLUE}🔹 Installing trial account cleanup script...${C_RESET}"
    setup_trial_cleanup_script
    
    echo -e "${C_BLUE}🔹 Cleaning legacy dynamic SSH banner hooks...${C_RESET}"
    disable_dynamic_ssh_banner_system
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}✅ Setup finished.${C_RESET}"
}

_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_and_open_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and port ${port}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port/$protocol"
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
             echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --list-ports --permanent | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and port ${port}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming ports are open.${C_RESET}"
    fi
    return 0
}

check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        echo -e "\n${C_BLUE}🔎 Checking if port $port is available...${C_RESET}"
        local conflicting_process_info
        conflicting_process_info=$(
            ss -H -lntp "( sport = :$port )" 2>/dev/null
            ss -H -lunp "( sport = :$port )" 2>/dev/null
        )
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)' | head -n 1)
            
            echo -e "${C_YELLOW}⚠️ Warning: Port $port is in use by process '${conflicting_name:-unknown}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "👉 Do you want to attempt to stop this process? (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                if [[ -z "$conflicting_pid" ]]; then
                    echo -e "${C_RED}❌ Could not determine which PID owns port $port. Please free it manually.${C_RESET}"
                    return 1
                fi
                echo -e "${C_GREEN}🛑 Stopping process PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -H -lntp "( sport = :$port )" 2>/dev/null | grep -q . || ss -H -lunp "( sport = :$port )" 2>/dev/null | grep -q .; then
                     echo -e "${C_RED}❌ Failed to free port $port. Please handle it manually. Aborting.${C_RESET}"
                     return 1
                else
                     echo -e "${C_GREEN}✅ Port $port has been successfully freed.${C_RESET}"
                fi
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port $port. Aborting.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port $port is free to use.${C_RESET}"
        fi
    done
    return 0
}

setup_limiter_service() {
    # Combined limiter + bandwidth monitoring
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# FirewallFalcon limiter version 2026-06-17.1
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/firewallfalcon/banners"
GRACE_DIR="/run/ff_grace"
SCAN_INTERVAL=20

# Ile KOLEJNYCH skanów z przekroczeniem limitu wymagane przed banem
# Każdy skan = 20s
# MIN_EXCEED_SCANS=6 → minimum 120s ciągłego przekroczenia → ban
# Reconnect/słaby zasięg: stary [priv] ginie w <70s → max 3-4 skany → brak bana
# Celowe dzielenie: utrzymuje się nieprzerwanie → po 6 skanach ban
MIN_EXCEED_SCANS=6

mkdir -p "$BW_DIR" "$PID_DIR" "$GRACE_DIR"
rm -f "$GRACE_DIR"/exceed_* 2>/dev/null
shopt -s nullglob

write_banner_if_changed() {
    local user="$1" content="$2"
    local banner_file="$BANNER_DIR/${user}.txt"
    local tmp_file="${banner_file}.tmp"
    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
}

count_sessions() {
    local target_user="$1"
    local user_uid
    user_uid=$(id -u "$target_user" 2>/dev/null) || { echo 0; return; }
    [[ "$user_uid" =~ ^[0-9]+$ ]] || { echo 0; return; }

    # Znajdź wszystkie PIDy listenerów sshd (Uid=0, PPid<=2)
    local listener_pids=""
    local pd pdir puid ppid _comm
    for pd in /proc/[0-9]*/comm; do
        [[ -f "$pd" ]] || continue
        read -r _comm < "$pd" 2>/dev/null
        [[ "$_comm" == "sshd" ]] || continue
        pdir="${pd%/comm}"
        puid=$(awk '/^Uid:/{print $2; exit}' "$pdir/status" 2>/dev/null)
        ppid=$(awk '/^PPid:/{print $2; exit}' "$pdir/status" 2>/dev/null)
        [[ "$puid" == "0" ]] || continue
        [[ "$ppid" =~ ^[0-9]+$ && "$ppid" -le 2 ]] 2>/dev/null || continue
        listener_pids="$listener_pids $(basename "$pdir")"
    done
    [[ -z "$listener_pids" ]] && { echo 0; return; }

    # Policz [priv] procesy należące do użytkownika
    local count=0
    local login_uid state
    for pd in /proc/[0-9]*/comm; do
        [[ -f "$pd" ]] || continue
        read -r _comm < "$pd" 2>/dev/null
        [[ "$_comm" == "sshd" ]] || continue
        pdir="${pd%/comm}"

        ppid=$(awk '/^PPid:/{print $2; exit}' "$pdir/status" 2>/dev/null)
        [[ " $listener_pids " == *" $ppid "* ]] || continue

        puid=$(awk '/^Uid:/{print $2; exit}' "$pdir/status" 2>/dev/null)
        [[ "$puid" == "0" ]] || continue

        state=$(awk '/^State:/{print $2; exit}' "$pdir/status" 2>/dev/null)
        [[ "$state" == "Z" || "$state" == "X" ]] && continue

        login_uid=""
        if [[ -r "$pdir/loginuid" ]]; then
            read -r login_uid < "$pdir/loginuid" 2>/dev/null
        fi
        [[ -z "$login_uid" ]] && \
            login_uid=$(awk '/^LoginUID:/{print $2; exit}' "$pdir/status" 2>/dev/null)

        [[ "$login_uid" =~ ^[0-9]+$ ]] || continue
        [[ "$login_uid" == "0" || "$login_uid" == "4294967295" ]] && continue
        [[ "$login_uid" == "$user_uid" ]] || continue

        (( count++ ))
    done

    echo "$count"
}

while true; do
    if [[ ! -s "$DB_FILE" ]]; then
        sleep "$SCAN_INTERVAL"
        continue
    fi

    current_ts=$(date +%s)
    dynamic_banners_enabled=false

    unset locked_users
    declare -A locked_users=()
    while read -r pu _ ps _r; do
        [[ "$ps" == "L" ]] && locked_users["$pu"]=1
    done < <(passwd -Sa 2>/dev/null)

    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        mkdir -p "$BANNER_DIR"
        dynamic_banners_enabled=true
    fi

    # session_pids do bandwidth trackingu
    unset session_pids
    declare -A session_pids=()
    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue
        [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" ]] || continue
        [[ -d "/proc/$ssh_pid" ]] || continue
        bw_state=$(awk '/^State:/{print $2; exit}' "/proc/$ssh_pid/status" 2>/dev/null)
        [[ "$bw_state" == "Z" || "$bw_state" == "X" ]] && continue
        session_pids["$ssh_owner"]+="$ssh_pid "
    done < <(ps -C sshd -o pid=,user= 2>/dev/null)

    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        [[ -z "$user" || "$user" == \#* ]] && continue

        user_locked=false
        [[ -n "${locked_users[$user]+x}" ]] && user_locked=true

        # Sprawdź expiry
        expiry_ts=0
        if [[ "$expiry" != "Never" && -n "$expiry" ]]; then
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    killall -u "$user" -9 &>/dev/null
                    locked_users["$user"]=1
                fi
                continue
            fi
        fi

        # Policz sesje
        online_count=$(count_sessions "$user")
        [[ "$online_count" =~ ^[0-9]+$ ]] || online_count=0

        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1

        # Loguj każdy skan gdy jest przekroczenie (do debugowania)
        if (( online_count > limit )); then
            SCAN_LOG="/etc/firewallfalcon/scan_debug.log"
            grace_file_check="$GRACE_DIR/exceed_${user}"
            gcount=0
            if [[ -f "$grace_file_check" ]]; then
                read -r _ gcount < "$grace_file_check" 2>/dev/null
                [[ "$gcount" =~ ^[0-9]+$ ]] || gcount=0
            fi
            printf "%s	%s	online=%d	limit=%d	grace_skan=%d
"                 "$(date '+%Y-%m-%d %H:%M:%S')" "$user"                 "$online_count" "$limit" "$gcount"                 >> "$SCAN_LOG" 2>/dev/null
            # Zachowaj tylko ostatnie 500 linii
            if (( $(wc -l < "$SCAN_LOG" 2>/dev/null || echo 0) > 500 )); then
                tail -n 500 "$SCAN_LOG" > "${SCAN_LOG}.tmp" && mv "${SCAN_LOG}.tmp" "$SCAN_LOG"
            fi
        fi

        if (( online_count > limit )); then
            # Plik grace przechowuje: "timestamp licznik_skanow"
            grace_file="$GRACE_DIR/exceed_${user}"
            BAN_LOG="/etc/firewallfalcon/ban_history.log"

            if [[ ! -f "$grace_file" ]]; then
                # Pierwsze wykrycie - zapisz czas i licznik=1
                printf "%s 1\n" "$current_ts" > "$grace_file"
            else
                # Odczytaj poprzedni stan
                read -r grace_ts grace_count < "$grace_file" 2>/dev/null
                [[ "$grace_ts" =~ ^[0-9]+$ ]] || grace_ts=$current_ts
                [[ "$grace_count" =~ ^[0-9]+$ ]] || grace_count=0

                # Sprawdź czy poprzedni skan był niedawno (max 3×SCAN_INTERVAL)
                # Jeśli przerwa była dłuższa - resetuj licznik (sesja wróciła do normy)
                elapsed_since=$(( current_ts - grace_ts ))
                if (( elapsed_since > SCAN_INTERVAL * 3 )); then
                    # Przerwa była zbyt długa - to nowe przekroczenie, resetuj
                    printf "%s 1\n" "$current_ts" > "$grace_file"
                else
                    grace_count=$(( grace_count + 1 ))
                    printf "%s %s\n" "$current_ts" "$grace_count" > "$grace_file"

                    if (( grace_count >= MIN_EXCEED_SCANS )); then
                        # Potwierdzone celowe przekroczenie - banuj
                        if [[ ! -f "/run/ff_sessionban_${user}" ]]; then
                            touch "/run/ff_sessionban_${user}" 2>/dev/null

                            # Szczegółowe logowanie bana
                            local ban_ts; ban_ts=$(date '+%Y-%m-%d %H:%M:%S')
                            local ban_pids=""
                            local user_uid_log; user_uid_log=$(id -u "$user" 2>/dev/null)

                            # Zbierz PIDs aktywnych sesji [priv]
                            for bpd in /proc/[0-9]*/comm; do
                                [[ -f "$bpd" ]] || continue
                                read -r _bc < "$bpd" 2>/dev/null
                                [[ "$_bc" == "sshd" ]] || continue
                                bpdir="${bpd%/comm}"
                                bpuid=$(awk '/^Uid:/{print $2; exit}' "$bpdir/status" 2>/dev/null)
                                [[ "$bpuid" == "0" ]] || continue
                                bluid=$(cat "$bpdir/loginuid" 2>/dev/null)
                                [[ "$bluid" == "$user_uid_log" ]] || continue
                                bpid=$(basename "$bpdir")
                                ban_pids="$ban_pids $bpid"
                            done
                            ban_pids="${ban_pids# }"

                            # Zapis do logu: timestamp TAB user TAB sesje/limit TAB PIDs TAB licznik_skanow
                            printf "%s	%s	%d/%d	PIDs:[%s]	skany:%d
"                                 "$ban_ts" "$user" "$online_count" "$limit"                                 "$ban_pids" "$grace_count"                                 >> "$BAN_LOG" 2>/dev/null
                        fi
                        if ! $user_locked; then
                            usermod -L "$user" &>/dev/null
                            killall -u "$user" -9 &>/dev/null
                            rm -f "$grace_file"
                            (sleep 60; usermod -U "$user" &>/dev/null
                             _pass=$(awk -F: -v u="$user" '$1==u{print $2;exit}' "$DB_FILE")
                             [[ -n "$_pass" ]] && echo "$user:$_pass" | chpasswd &>/dev/null
                             rm -f "/run/ff_sessionban_${user}" 2>/dev/null) &
                            locked_users["$user"]=1
                            user_locked=true
                        else
                            killall -u "$user" -9 &>/dev/null
                            rm -f "$grace_file"
                        fi
                    fi
                fi
            fi
        else
            # Sesje w normie - wyczyść grace
            if [[ -f "$GRACE_DIR/exceed_${user}" ]]; then
                rm -f "$GRACE_DIR/exceed_${user}" 2>/dev/null
            fi
        fi

        # Banner
        if $dynamic_banners_enabled; then
            days_left="N/A"
            if [[ "$expiry" != "Never" && -n "$expiry" && \
                  "$expiry_ts" =~ ^[0-9]+$ && $expiry_ts -gt 0 ]]; then
                diff_secs=$((expiry_ts - current_ts))
                if (( diff_secs <= 0 )); then
                    days_left="EXPIRED"
                else
                    d_l=$(( diff_secs / 86400 ))
                    h_l=$(( (diff_secs % 86400) / 3600 ))
                    (( d_l == 0 )) && days_left="${h_l}h left" \
                                   || days_left="${d_l}d ${h_l}h"
                fi
            fi
            bw_info="Unlimited"
            accum_disp=0
            if [[ -f "$BW_DIR/${user}.usage" ]]; then
                read -r accum_disp < "$BW_DIR/${user}.usage"
                [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
            fi
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                used_gb=$(awk "BEGIN {printf \"%.2f\", $accum_disp / 1073741824}")
                remain_gb=$(awk \
                    "BEGIN {r=$bandwidth_gb-$used_gb; if(r<0)r=0; printf \"%.2f\",r}")
                bw_info="${used_gb}/${bandwidth_gb} GB used | ${remain_gb} GB left"
            elif (( accum_disp > 0 )); then
                used_gb=$(awk "BEGIN {printf \"%.2f\", $accum_disp / 1073741824}")
                bw_info="Unlimited (used: ${used_gb} GB)"
            fi
            banner_content="<br><font color=\"red\"><b>      ✨ STATUS KONTA ✨      </b></font><br><br>"
            banner_content+="<font color=\"white\">👤 <b>Nazwa   :</b> $user</font><br>"
            banner_content+="<font color=\"white\">📅 <b>Ważne do :</b> $expiry ($days_left)</font><br>"
            banner_content+="<font color=\"white\">📊 <b>Ilość GB  :</b> $bw_info</font><br>"
            banner_content+="<font color=\"white\">🔌 <b>Podłączone urządzenia   :</b> $online_count/$limit</font><br><br>"
            banner_content+="<font color=\"red\">⛔ <b>Przekroczenie podłączonych urządzeń = ban 1 min</b></font><br><br>"
            write_banner_if_changed "$user" "$banner_content"
        fi

        # Bandwidth tracking
        usagefile="$BW_DIR/${user}.usage"
        accumulated=0
        if [[ -f "$usagefile" ]]; then
            read -r accumulated < "$usagefile"
            [[ "$accumulated" =~ ^[0-9]+$ ]] || accumulated=0
        fi

        unset unique_pids
        declare -A unique_pids=()
        for pid in ${session_pids["$user"]:-}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        if (( ${#unique_pids[@]} == 0 )); then
            rm -f "$PID_DIR/${user}__"*.last 2>/dev/null
            continue
        fi

        delta_total=0
        for pid in "${!unique_pids[@]}"; do
            io_file="/proc/$pid/io"
            cur=0
            if [[ -r "$io_file" ]]; then
                rchar=0; wchar=0
                while read -r key value; do
                    case "$key" in
                        rchar:) rchar=${value:-0} ;;
                        wchar:) wchar=${value:-0} ;;
                    esac
                done < "$io_file"
                cur=$(( rchar + wchar ))
            fi
            pidfile="$PID_DIR/${user}__${pid}.last"
            if [[ -f "$pidfile" ]]; then
                read -r prev < "$pidfile"
                [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
                if (( cur >= prev )); then
                    delta_total=$(( delta_total + cur - prev ))
                else
                    delta_total=$(( delta_total + cur ))
                fi
            fi
            printf "%s\n" "$cur" > "$pidfile"
        done

        for f in "$PID_DIR/${user}__"*.last; do
            [[ -f "$f" ]] || continue
            fpid=${f##*__}; fpid=${fpid%.last}
            [[ -d "/proc/$fpid" ]] || rm -f "$f"
        done

        new_total=$(( accumulated + delta_total ))
        printf "%s\n" "$new_total" > "$usagefile"
        chmod 600 "$usagefile" 2>/dev/null

        if (( delta_total > 0 )); then
            stats_dir="/etc/firewallfalcon/stats"
            mkdir -p "$stats_dir"
            today=$(date +%Y-%m-%d)
            month=$(date +%Y-%m)
            daily_file="$stats_dir/${user}.daily"
            day_total=0
            if [[ -f "$daily_file" ]]; then
                read -r saved_day saved_bytes < "$daily_file" 2>/dev/null
                [[ "$saved_day" == "$today" ]] && day_total=${saved_bytes:-0}
            fi
            printf "%s %s\n" "$today" "$(( day_total + delta_total ))" \
                > "$daily_file"
            monthly_file="$stats_dir/${user}.monthly"
            month_total=0
            if [[ -f "$monthly_file" ]]; then
                read -r saved_month saved_mbytes < "$monthly_file" 2>/dev/null
                [[ "$saved_month" == "$month" ]] && month_total=${saved_mbytes:-0}
            fi
            printf "%s %s\n" "$month" "$(( month_total + delta_total ))" \
                > "$monthly_file"
        fi

        quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        if [[ "$bandwidth_gb" != "0" && "$quota_bytes" =~ ^[0-9]+$ ]] \
           && (( new_total >= quota_bytes )); then
            if ! $user_locked; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                locked_users["$user"]=1
            fi
        fi
    done < "$DB_FILE"

    sleep "$SCAN_INTERVAL"
done

EOF
    chmod +x "$LIMITER_SCRIPT"
    # Strip DOS line endings in case menu.sh was uploaded from Windows
    sed -i 's/\r$//' "$LIMITER_SCRIPT" 2>/dev/null

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=FirewallFalcon Active User Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

[Install]
WantedBy=multi-user.target
EOF
    sed -i 's/\r$//' "$LIMITER_SERVICE" 2>/dev/null

    pkill -f "firewallfalcon-limiter" 2>/dev/null

    if ! systemctl is-active --quiet firewallfalcon-limiter; then
        systemctl daemon-reload
        systemctl enable firewallfalcon-limiter &>/dev/null
        systemctl start firewallfalcon-limiter --no-block &>/dev/null
        
    else
        systemctl restart firewallfalcon-limiter --no-block &>/dev/null
        
    fi
}

sync_runtime_components_if_needed() {
    local limiter_marker="# FirewallFalcon limiter version 2026-06-17.1"
    if [[ ! -f "$LIMITER_SCRIPT" ]] || ! grep -Fqx "$limiter_marker" "$LIMITER_SCRIPT" 2>/dev/null; then
        setup_limiter_service >/dev/null 2>&1
    fi
    if [[ -f "$BADVPN_SERVICE_FILE" ]]; then
        ensure_badvpn_service_is_quiet
    fi
    if [[ -f "/etc/firewallfalcon/banners_enabled" ]]; then
        update_ssh_banners_config
    elif [[ -f "$SSHD_FF_CONFIG" ]]; then
        disable_dynamic_ssh_banner_system
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
}

setup_bandwidth_service() {
    mkdir -p "$BANDWIDTH_DIR"
    # Bandwidth monitoring is now integrated into the limiter service above.
    # Stop the old standalone bandwidth service if it exists.
    if systemctl is-active --quiet firewallfalcon-bandwidth 2>/dev/null; then
        systemctl stop firewallfalcon-bandwidth &>/dev/null
        systemctl disable firewallfalcon-bandwidth &>/dev/null
    fi
    rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" 2>/dev/null
}

setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
# FirewallFalcon Trial Account Auto-Cleanup
# Usage: firewallfalcon-trial-cleanup.sh <username>
DB_FILE="/etc/firewallfalcon/users.db"
BW_DIR="/etc/firewallfalcon/bandwidth"

username="$1"
if [[ -z "$username" ]]; then exit 1; fi

# Kill active sessions
killall -u "$username" -9 &>/dev/null
sleep 1

# Delete system user
userdel -r "$username" &>/dev/null

# Remove from DB
awk -F: -v u="$username" '$1 != u' "$DB_FILE" > "$DB_FILE.tmp" && chmod 600 "$DB_FILE.tmp" && sync "$DB_FILE.tmp" 2>/dev/null; mv "$DB_FILE.tmp" "$DB_FILE"

# Remove bandwidth tracking
rm -f "$BW_DIR/${username}.usage"
rm -rf "$BW_DIR/pidtrack/${username}"
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

disable_dynamic_ssh_banner_system() {
    rm -f "/etc/firewallfalcon/banners_enabled" "$SSHD_FF_CONFIG" /usr/local/bin/firewallfalcon-login-info.sh 2>/dev/null
    rm -rf "/etc/firewallfalcon/banners" 2>/dev/null
    invalidate_banner_cache
}

disable_static_ssh_banner_in_sshd_config() {
    sed -i.bak -E "s|^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$|# Banner $SSH_BANNER_FILE|" /etc/ssh/sshd_config 2>/dev/null
}

is_static_ssh_banner_enabled() {
    grep -q -E "^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null && [ -f "$SSH_BANNER_FILE" ]
}

is_dynamic_ssh_banner_enabled() {
    [[ -f "/etc/firewallfalcon/banners_enabled" && -f "$SSHD_FF_CONFIG" ]]
}

get_ssh_banner_mode() {
    if is_dynamic_ssh_banner_enabled; then
        echo "dynamic"
    elif is_static_ssh_banner_enabled; then
        echo "static"
    else
        echo "disabled"
    fi
}

refresh_dynamic_banner_routing_if_enabled() {
    if is_dynamic_ssh_banner_enabled; then
        update_ssh_banners_config
    fi
}

update_ssh_banners_config() {
    local tmp_conf

    if [[ ! -f "/etc/firewallfalcon/banners_enabled" ]]; then
        if [[ -f "$SSHD_FF_CONFIG" ]]; then
            rm -f "$SSHD_FF_CONFIG" 2>/dev/null
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
        fi
        return
    fi

    ensure_firewallfalcon_dirs
    tmp_conf="/tmp/ff_banners_new.conf"
    echo "# FirewallFalcon - Dynamic per-user SSH banners" > "$tmp_conf"

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r u _rest; do
            [[ -z "$u" || "$u" == \#* ]] && continue
            echo "Match User $u" >> "$tmp_conf"
            echo "    Banner /etc/firewallfalcon/banners/${u}.txt" >> "$tmp_conf"
        done < "$DB_FILE"
    fi

    if ! cmp -s "$tmp_conf" "$SSHD_FF_CONFIG" 2>/dev/null; then
        mv "$tmp_conf" "$SSHD_FF_CONFIG"
        if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
            echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        fi
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    else
        rm -f "$tmp_conf"
    fi
}

setup_ssh_login_info() {
    ensure_firewallfalcon_dirs || return 1
    if ! touch "/etc/firewallfalcon/banners_enabled"; then
        echo -e "${C_RED}❌ Failed to enable dynamic SSH banners.${C_RESET}"
        return 1
    fi
    disable_static_ssh_banner_in_sshd_config
    update_ssh_banners_config
    return 0
}


generate_dns_record() {
    echo -e "\n${C_BLUE}⚙️ Generating a random domain...${C_RESET}"
    if ! command -v jq &> /dev/null; then
        echo -e "${C_YELLOW}⚠️ jq not found, attempting to install...${C_RESET}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq || {
            echo -e "${C_RED}❌ Failed to install jq. Cannot manage DNS records.${C_RESET}"
            return 1
        }
    fi
    local SERVER_IPV4
    SERVER_IPV4=$(curl -s -4 icanhazip.com)
    if ! _is_valid_ipv4 "$SERVER_IPV4"; then
        echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
        echo -e "   Output received: '$SERVER_IPV4'"
        return 1
    fi

    local SERVER_IPV6
    SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)

    local RANDOM_SUBDOMAIN="vps-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
    local FULL_DOMAIN="$RANDOM_SUBDOMAIN.$DESEC_DOMAIN"
    local HAS_IPV6="false"

    local API_DATA
    API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}]' "$RANDOM_SUBDOMAIN" "$SERVER_IPV4")

    if [[ -n "$SERVER_IPV6" ]]; then
        local aaaa_record
        aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$RANDOM_SUBDOMAIN" "$SERVER_IPV6")
        API_DATA="${API_DATA%?}${aaaa_record}]"
        HAS_IPV6="true"
    fi

    local CREATE_RESPONSE
    CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
        --data "$API_DATA")
    
    local HTTP_CODE=${CREATE_RESPONSE: -3}
    local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

    if [[ "$HTTP_CODE" -ne 201 ]]; then
        echo -e "${C_RED}❌ Failed to create DNS records. API returned HTTP $HTTP_CODE.${C_RESET}"
        if ! echo "$RESPONSE_BODY" | jq . > /dev/null 2>&1; then
            echo "Raw Response: $RESPONSE_BODY"
        else
            echo "Response: $RESPONSE_BODY" | jq
        fi
        return 1
    fi
    
    cat > "$DNS_INFO_FILE" <<-EOF
SUBDOMAIN="$RANDOM_SUBDOMAIN"
FULL_DOMAIN="$FULL_DOMAIN"
HAS_IPV6="$HAS_IPV6"
EOF
    # Zapisz token do osobnego pliku z ograniczonymi uprawnieniami
    if [[ ! -f "/etc/firewallfalcon/desec.conf" ]]; then
        printf 'DESEC_TOKEN="%s"
DESEC_DOMAIN="%s"
' "$DESEC_TOKEN" "$DESEC_DOMAIN" > /etc/firewallfalcon/desec.conf
        chmod 600 /etc/firewallfalcon/desec.conf
    fi
    echo -e "\n${C_GREEN}✅ Successfully created domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
}

delete_dns_record() {
    if [ ! -f "$DNS_INFO_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No domain to delete.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}🗑️ Deleting DNS records...${C_RESET}"
    source "$DNS_INFO_FILE"
    if [[ -z "$SUBDOMAIN" ]]; then
        echo -e "${C_RED}❌ Could not read record details from config file. Skipping deletion.${C_RESET}"
        return
    fi

    curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/A/" \
         -H "Authorization: Token $DESEC_TOKEN" > /dev/null

    if [[ "$HAS_IPV6" == "true" ]]; then
        curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/AAAA/" \
             -H "Authorization: Token $DESEC_TOKEN" > /dev/null
    fi

    echo -e "\n${C_GREEN}✅ Deleted domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
    rm -f "$DNS_INFO_FILE"
}

dns_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 DNS Domain Management ---${C_RESET}"
    if [ -f "$DNS_INFO_FILE" ]; then
        source "$DNS_INFO_FILE"
        echo -e "\nℹ️ A domain already exists for this server:"
        echo -e "  - ${C_CYAN}Domain:${C_RESET} ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
        echo
        read -p "👉 Do you want to DELETE this domain? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            delete_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    else
        echo -e "\nℹ️ No domain has been generated for this server yet."
        echo
        read -p "👉 Do you want to generate a new random domain now? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            generate_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    fi
}

_select_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    if [[ ! -s $DB_FILE ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the database.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    
    mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    local -A all_user_lookup=()
    local username
    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    echo -e "\nPlease select a user:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED} [ 0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "${C_CYAN}💡 Tip: you can also type the exact username directly.${C_RESET}"
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter the number or exact username: " choice; then
            echo
            SELECTED_USER=""
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "${#users[@]}" ]; then
            if [ "$choice" -eq 0 ]; then
                SELECTED_USER=""; return
            else
                SELECTED_USER="${users[$((choice-1))]}"; return
            fi
        elif [[ -n "${all_user_lookup[$choice]+x}" ]]; then
            SELECTED_USER="$choice"; return
        else
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
        fi
    done
}

_select_multi_user_interface() {
    local title="$1"
    local include_orphan_users="${2:-false}"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    SELECTED_USERS=()
    local -a all_users=()
    local -a orphan_users=()
    local -A all_user_lookup=()
    local -A orphan_user_lookup=()
    local username

    if [[ -s $DB_FILE ]]; then
        mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    fi

    if [[ "$include_orphan_users" == "true" ]]; then
        mapfile -t orphan_users < <(get_firewallfalcon_orphan_users)
        for username in "${orphan_users[@]}"; do
            orphan_user_lookup["$username"]=1
            if ! printf "%s\n" "${all_users[@]}" | grep -Fxq "$username"; then
                all_users+=("$username")
            fi
        done
        if [[ ${#all_users[@]} -gt 0 ]]; then
            mapfile -t all_users < <(printf "%s\n" "${all_users[@]}" | sort)
        fi
    fi

    if [[ ${#all_users[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the manager database.${C_RESET}"
        if [[ "$include_orphan_users" == "true" ]]; then
            echo -e "${C_DIM}No orphan FirewallFalcon system users were found either.${C_RESET}"
        fi
        SELECTED_USERS=("NO_USERS"); return
    fi

    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USERS=("NO_USERS"); return
    fi
    echo -e "\nPlease select users:\n"
    for i in "${!users[@]}"; do
        local display_user="${users[$i]}"
        if [[ "$include_orphan_users" == "true" && -n "${orphan_user_lookup[${users[$i]}]+x}" ]]; then
            display_user="${display_user} ${C_DIM}(system-only)${C_RESET}"
        fi
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "$display_user"
    done
    echo -e "\n  ${C_GREEN}[all]${C_RESET} Select ALL listed users"
    echo -e "  ${C_RED}  [0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "\n${C_CYAN}💡 You can select multiple by number, range, or exact username.${C_RESET}"
    echo -e "${C_CYAN}   Examples: '1 3 5' or '1,3' or '1-4' or 'alice bob'${C_RESET}"
    if [[ "$include_orphan_users" == "true" ]]; then
        echo -e "${C_CYAN}   Users marked '(system-only)' are old accounts still on the VPS but missing from users.db${C_RESET}"
    fi
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter user numbers or usernames: " choice; then
            echo
            SELECTED_USERS=()
            return
        fi
        choice=$(echo "$choice" | tr ',' ' ') # Replace commas with spaces
        
        if [[ -z "$choice" ]]; then
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            SELECTED_USERS=(); return
        fi
        
        if [[ "${choice,,}" == "all" ]]; then
            SELECTED_USERS=("${users[@]}")
            return
        fi
        
        local valid=true
        local selected_indices=()
        local selected_names=()
        for token in $choice; do
            if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=${token%-*}
                local end=${token#*-}
                if [ "$start" -le "$end" ]; then
                    for (( idx=start; idx<=end; idx++ )); do
                        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#users[@]}" ]; then
                            selected_indices+=($idx)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                if [ "$token" -ge 1 ] && [ "$token" -le "${#users[@]}" ]; then
                    selected_indices+=($token)
                elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                    selected_names+=("$token")
                else
                    valid=false; break
                fi
            elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                selected_names+=("$token")
            else
                valid=false; break
            fi
        done
        
        if [[ "$valid" == true && ( ${#selected_indices[@]} -gt 0 || ${#selected_names[@]} -gt 0 ) ]]; then
            mapfile -t unique_indices < <(printf "%s\n" "${selected_indices[@]}" | sort -u -n)
            for idx in "${unique_indices[@]}"; do
                SELECTED_USERS+=("${users[$((idx-1))]}")
            done
            mapfile -t unique_names < <(printf "%s\n" "${selected_names[@]}" | sort -u)
            for username in "${unique_names[@]}"; do
                if ! printf "%s\n" "${SELECTED_USERS[@]}" | grep -Fxq "$username"; then
                    SELECTED_USERS+=("$username")
                fi
            done
            return
        else
            echo -e "${C_RED}❌ Invalid selection. Please check your numbers or usernames.${C_RESET}"
            SELECTED_USERS=()
            selected_indices=()
            selected_names=()
        fi
    done
}

get_user_status() {
    local username="$1"
    if ! id "$username" &>/dev/null; then echo -e "${C_RED}Not Found${C_RESET}"; return; fi
    local expiry_date=$(grep "^$username:" "$DB_FILE" | cut -d: -f3)
    if passwd -S "$username" 2>/dev/null | grep -q " L "; then echo -e "${C_YELLOW}🔒 Locked${C_RESET}"; return; fi
    local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    if [[ $expiry_ts -lt $current_ts ]]; then echo -e "${C_RED}🗓️ Expired${C_RESET}"; return; fi
    echo -e "${C_GREEN}🟢 Active${C_RESET}"
}

create_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create New SSH User ---${C_RESET}"
    read -p "👉 Enter username (or '0' to cancel): " username
    local adopt_existing=false
    if [[ "$username" == "0" ]]; then
        echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
        return
    fi
    if [[ -z "$username" ]]; then
        echo -e "\n${C_RED}❌ Error: Username cannot be empty.${C_RESET}"
        return
    fi
    if db_has_user "$username"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists in FirewallFalcon.${C_RESET}"
        return
    fi
    if id "$username" &>/dev/null; then
        if is_firewallfalcon_orphan_user "$username"; then
            echo -e "\n${C_YELLOW}⚠️ User '$username' already exists on the system but is missing from users.db.${C_RESET}"
            echo -e "${C_DIM}This usually happens after uninstalling the script without deleting the SSH users.${C_RESET}"
            read -p "👉 Do you want to take control of this existing user and manage it with FirewallFalcon? (y/n): " adopt_confirm
            if [[ "$adopt_confirm" == "y" || "$adopt_confirm" == "Y" ]]; then
                adopt_existing=true
            else
                echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
                return
            fi
        else
            echo -e "\n${C_RED}❌ Error: System user '$username' already exists and does not look like a FirewallFalcon SSH account.${C_RESET}"
            return
        fi
    fi
    local password=""
    while true; do
        read -p "🔑 Enter password (or press Enter for auto-generated): " password
        if [[ -z "$password" ]]; then
            password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
            echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$password${C_RESET}"
            break
        else
            break
        fi
    done
    read -p "🗓️ Enter account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📶 Enter simultaneous connection limit [2]: " limit
    limit=${limit:-2}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📦 Enter bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    ensure_firewallfalcon_system_group
    if [[ "$adopt_existing" == "true" ]]; then
        usermod -s /usr/sbin/nologin "$username" &>/dev/null
    else
        useradd -m -s /usr/sbin/nologin "$username"
    fi
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd; chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    
    clear; show_banner
    if [[ "$adopt_existing" == "true" ]]; then
        echo -e "${C_GREEN}✅ Existing system user '$username' has been imported into FirewallFalcon!${C_RESET}\n"
    else
        echo -e "${C_GREEN}✅ User '$username' created successfully!${C_RESET}\n"
    fi
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - 🗓️ Expires on:        ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth Limit:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "    ${C_DIM}(Active monitoring service will enforce these limits)${C_RESET}"

    # Auto-ask for config generation
    echo
    read -p "👉 Do you want to generate a client connection config for this user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

delete_user() {
    _select_multi_user_interface "--- 🗑️ Delete FirewallFalcon Users ---" "true"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_RED}⚠️ You selected ${#SELECTED_USERS[@]} user(s) to delete: ${C_YELLOW}${SELECTED_USERS[*]}${C_RESET}"
    read -p "👉 Are you sure you want to PERMANENTLY delete them? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Deletion cancelled.${C_RESET}"; return; fi
    
    echo -e "\n${C_BLUE}🗑️ Deleting selected users...${C_RESET}"
    delete_firewallfalcon_user_accounts "${SELECTED_USERS[@]}"
}

edit_user() {
    _select_user_interface "--- ✏️ Edit a User ---"
    local username=$SELECTED_USER
    if [[ "$username" == "NO_USERS" ]] || [[ -z "$username" ]]; then return; fi
    while true; do
        clear; show_banner; echo -e "${C_BOLD}${C_PURPLE}--- Editing User: ${C_YELLOW}$username${C_PURPLE} ---${C_RESET}"
        
        # Show current user details
        local current_line; current_line=$(grep "^$username:" "$DB_FILE")
        local cur_pass; cur_pass=$(echo "$current_line" | cut -d: -f2)
        local cur_expiry; cur_expiry=$(echo "$current_line" | cut -d: -f3)
        local cur_limit; cur_limit=$(echo "$current_line" | cut -d: -f4)
        local cur_bw; cur_bw=$(echo "$current_line" | cut -d: -f5)
        [[ -z "$cur_bw" ]] && cur_bw="0"
        local cur_bw_display="Unlimited"; [[ "$cur_bw" != "0" ]] && cur_bw_display="${cur_bw} GB"
        
        # Show bandwidth usage
        local bw_used_display="N/A"
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null)
            if [[ -n "$used_bytes" && "$used_bytes" != "0" ]]; then
                bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $used_bytes / 1073741824}")
            else
                bw_used_display="0.00 GB"
            fi
        fi
        
        echo -e "\n  ${C_DIM}Current: Pass=${C_YELLOW}$cur_pass${C_RESET}${C_DIM} Exp=${C_YELLOW}$cur_expiry${C_RESET}${C_DIM} Conn=${C_YELLOW}$cur_limit${C_RESET}${C_DIM} BW=${C_YELLOW}$cur_bw_display${C_RESET}${C_DIM} Used=${C_CYAN}$bw_used_display${C_RESET}"
        echo -e "\nSelect a detail to edit:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🔑 Change Password"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗓️ Change Expiration Date"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "📶 Change Connection Limit"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "📦 Change Bandwidth Limit"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "🔄 Reset Bandwidth Counter"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ✅ Finish Editing"
        echo
        if ! read -r -p "👉 Enter your choice: " edit_choice; then
            echo
            return
        fi
        case $edit_choice in
            1)
               local new_pass=""
               read -p "Enter new password (or press Enter for auto-generated): " new_pass
               if [[ -z "$new_pass" ]]; then
                   new_pass=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
                   echo -e "${C_GREEN}🔑 Auto-generated: ${C_YELLOW}$new_pass${C_RESET}"
               fi
               echo "$username:$new_pass" | chpasswd
               # Resetuj flagę "hasło wygasłe" i odblokuj konto (naprawia problem po wygaśnięciu)
               chage -d "$(date +%Y-%m-%d)" "$username" 2>/dev/null
               usermod -U "$username" 2>/dev/null
               # Reset bandwidth usage żeby limiter nie zablokował z powrotem w ciągu 20s
               [[ -f "$BANDWIDTH_DIR/${username}.usage" ]] && echo "0" > "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null
               db_update_user "$username" "$new_pass" "$cur_expiry" "$cur_limit" "$cur_bw"
               echo -e "\n${C_GREEN}✅ Password for '$username' changed to: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            2) read -p "Enter new duration (in days from today): " days
               if [[ "$days" =~ ^[0-9]+$ ]]; then
                   local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d); chage -E "$new_expire_date" "$username"
                   # Resetuj flagę "hasło wygasłe", odblokuj konto, przywróć hasło z bazy
                   chage -d "$(date +%Y-%m-%d)" "$username" 2>/dev/null
                   usermod -U "$username" 2>/dev/null
                   echo "$username:$cur_pass" | chpasswd 2>/dev/null
                   # Reset bandwidth usage żeby limiter nie zablokował z powrotem w ciągu 20s
                   [[ -f "$BANDWIDTH_DIR/${username}.usage" ]] && echo "0" > "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null
                   db_update_user "$username" "$cur_pass" "$new_expire_date" "$cur_limit" "$cur_bw"
                   echo -e "\n${C_GREEN}✅ Expiration for '$username' set to ${C_YELLOW}$new_expire_date${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid number of days.${C_RESET}"; fi ;;
            3) read -p "Enter new simultaneous connection limit: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                   db_update_user "$username" "$cur_pass" "$cur_expiry" "$new_limit" "$cur_bw"
                   echo -e "\n${C_GREEN}✅ Connection limit for '$username' set to ${C_YELLOW}$new_limit${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid limit.${C_RESET}"; fi ;;
            4) read -p "Enter new bandwidth limit in GB (0 = unlimited): " new_bw
               if [[ "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   db_update_user "$username" "$cur_pass" "$cur_expiry" "$cur_limit" "$new_bw"
                   local bw_msg="Unlimited"; [[ "$new_bw" != "0" ]] && bw_msg="${new_bw} GB"
                   echo -e "\n${C_GREEN}✅ Bandwidth limit for '$username' set to ${C_YELLOW}$bw_msg${C_RESET}."
                   # Unlock user if they were locked due to bandwidth
                   if [[ "$new_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
                       local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
                       local new_quota_bytes; new_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_bw * 1073741824}")
                       if [[ "$new_bw" == "0" ]] || [[ "$used_bytes" -lt "$new_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                           # Resetuj flagę "hasło wygasłe" i przywróć hasło
                           chage -d "$(date +%Y-%m-%d)" "$username" 2>/dev/null
                           echo "$username:$cur_pass" | chpasswd 2>/dev/null
                           rm -f "/run/ff_sessionban_${username}" "/run/ff_grace/exceed_${username}" 2>/dev/null
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            5)
               echo "0" > "$BANDWIDTH_DIR/${username}.usage"
               # Unlock user if they were locked due to bandwidth
               usermod -U "$username" &>/dev/null
               rm -f "/run/ff_sessionban_${username}" "/run/ff_grace/exceed_${username}" 2>/dev/null
               echo -e "\n${C_GREEN}✅ Bandwidth counter for '$username' has been reset to 0.${C_RESET}"
               ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" ;;
        esac
        
        # Sync DB i restart limiter jeśli coś się zmieniło (dla opcji 1-5)
        if [[ "$edit_choice" =~ ^[1-5]$ ]]; then
            sync "$DB_FILE" 2>/dev/null || true
            if systemctl is-active --quiet firewallfalcon-limiter; then
                systemctl restart firewallfalcon-limiter 2>/dev/null || true
            fi
        fi
        
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue editing..." && read -r || return
    done
}

lock_user() {
    _select_multi_user_interface "--- 🔒 Lock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔒 Locking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -L "$u"
        if [ $? -eq 0 ]; then
            killall -u "$u" -9 &>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} locked and active sessions killed."
        else
            echo -e " ❌ Failed to lock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

unlock_user() {
    _select_multi_user_interface "--- 🔓 Unlock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔓 Unlocking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -U "$u"
        if [ $? -eq 0 ]; then
            # Wyczyść flagi bana sesji i grace period żeby limiter nie zbanował od razu
            rm -f "/run/ff_sessionban_${u}" 2>/dev/null
            rm -f "/run/ff_grace/exceed_${u}" 2>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} unlocked."
        else
            echo -e " ❌ Failed to unlock ${C_YELLOW}$u${C_RESET}."
        fi
    done
    
    # Restart limiter żeby natychmiast przeskanował unlocked konta
    if systemctl is-active --quiet firewallfalcon-limiter; then
        systemctl restart firewallfalcon-limiter 2>/dev/null || true
    fi
}

list_users() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ Brak zarządzanych użytkowników.${C_RESET}"
        return
    fi

    local current_ts
    current_ts=$(date +%s)
    local -A system_user_lookup=()
    local -A locked_user_lookup=()

    while IFS=: read -r system_user _rest; do
        [[ -n "$system_user" ]] && system_user_lookup["$system_user"]=1
    done < /etc/passwd

    while read -r passwd_user _ passwd_status _rest; do
        [[ -z "$passwd_user" ]] && continue
        [[ "$passwd_status" == "L" ]] && locked_user_lookup["$passwd_user"]=1
    done < <(passwd -Sa 2>/dev/null)
    refresh_ssh_session_cache

    # Collect rows: sort_key|user|expiry|sessions|plain_status|status_label
    local -a rows=()
    while IFS=: read -r user pass expiry limit _rest; do
        local online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        local plain_status="Active"
        local status_label="🟢 Aktywny"

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            plain_status="Not Found"; status_label="❌ Brak"
        elif [[ -n "$expiry" && "$expiry" != "Never" ]]; then
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                plain_status="Expired"; status_label="🗓️ Wygasł"
            fi
        fi

        # Check for active session ban (temp lock by limiter)
        if [[ "$plain_status" == "Active" || "$plain_status" == "Locked" ]]; then
            if [[ -f "/run/ff_sessionban_${user}" ]]; then
                plain_status="Banned"; status_label="🚫 BAN (sesje)"
            elif [[ -n "${locked_user_lookup[$user]+x}" ]]; then
                plain_status="Locked"; status_label="🔒 Zablok."
            fi
        fi

        # Sort priority: active/banned/locked first (0), expired/not-found last (9)
        local sort_prio=0
        case "$plain_status" in
            Expired|Not\ Found) sort_prio=9 ;;
        esac

        rows+=("${sort_prio}$(printf '%010d' "$((9999999999 - online_count))")|$user|$expiry|$online_count/$limit|$plain_status|$status_label")
    done < "$DB_FILE"

    local total="${#rows[@]}"
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

    echo -e "  ${C_BOLD}${C_WHITE}📋 LISTA UŻYTKOWNIKÓW${C_RESET}  ${C_DIM}(aktywne wg sesji • wygasłe na końcu)${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-16s  %-12s  %-8s  %s${C_RESET}\n" "UŻYTKOWNIK" "WYGASA" "SESJE" "STATUS"
    echo -e "$div"

    while IFS='|' read -r _key user expiry sessions plain_status status_label; do
        local uc="$C_WHITE" sc="$C_GREEN"
        case "$plain_status" in
            Banned)    uc="$C_RED";    sc="$C_RED" ;;
            Locked)    uc="$C_YELLOW"; sc="$C_YELLOW" ;;
            Expired)   uc="$C_RED";    sc="$C_RED" ;;
            Not\ Found) uc="$C_DIM";  sc="$C_DIM" ;;
        esac
        printf "  ${uc}%-16s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${C_CYAN}%-8s${C_RESET}  ${sc}%s${C_RESET}\n" \
            "$user" "$expiry" "$sessions" "$status_label"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n)

    echo -e "$div"
    echo -e "  ${C_DIM}Razem: ${total} użytkowników  •  Sesje online: ${SSH_SESSION_TOTAL}${C_RESET}"
    echo -e "  ${C_DIM}${C_RED}BAN${C_RESET}${C_DIM}=tymczasowy ban za sesje (mija po ~120s)  ${C_YELLOW}Zablok.${C_RESET}${C_DIM}=ręczna blokada${C_RESET}\n"
}

renew_user() {
    _select_multi_user_interface "--- 🔄 Renew Users ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    read -p "👉 Enter number of days to extend the account(s): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi

    local today; today=$(date +%Y-%m-%d)

    # Opcja odroczenia
    echo -e "\n${C_CYAN}📅 Od kiedy liczyć odnowienie?${C_RESET}"
    echo -e "  ${C_CHOICE}[1]${C_RESET} Od dzisiaj / od daty wygaśnięcia (normalnie)"
    echo -e "  ${C_CHOICE}[2]${C_RESET} Za X dni od dzisiaj (odroczone)"
    echo -e "  ${C_CHOICE}[3]${C_RESET} Od konkretnej daty (YYYY-MM-DD)"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz [1]: ${C_RESET}")" start_choice
    start_choice=${start_choice:-1}

    local defer_date=""
    case "$start_choice" in
        2)
            read -r -p "👉 Za ile dni od dzisiaj zacząć? " defer_days
            if [[ "$defer_days" =~ ^[0-9]+$ ]]; then
                defer_date=$(date -d "$today +$defer_days days" +%Y-%m-%d)
                echo -e "${C_DIM}Odnowienie od: $defer_date${C_RESET}"
            else
                echo -e "${C_RED}❌ Nieprawidłowa liczba — użyję dzisiaj.${C_RESET}"
            fi
            ;;
        3)
            read -r -p "👉 Podaj datę startu (DD-MM-YYYY): " defer_input
            # Zamień DD-MM-YYYY na YYYY-MM-DD
            if [[ "$defer_input" =~ ^([0-9]{2})-([0-9]{2})-([0-9]{4})$ ]]; then
                defer_date="${BASH_REMATCH[3]}-${BASH_REMATCH[2]}-${BASH_REMATCH[1]}"
            else
                defer_date="$defer_input"
            fi
            if ! date -d "$defer_date" &>/dev/null 2>&1; then
                echo -e "${C_RED}❌ Nieprawidłowa data — użyję dzisiaj.${C_RESET}"
                defer_date=""
            else
                local defer_display; defer_display=$(date -d "$defer_date" +%d-%m-%Y)
                echo -e "${C_DIM}Odnowienie od: $defer_display${C_RESET}"
            fi
            ;;
    esac

    echo -e "\n${C_BLUE}🔄 Renewing selected users for $days days...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        [[ -z "$u" ]] && continue
        local line; line=$(awk -F: -v u="$u" '$1 == u {print; exit}' "$DB_FILE")
        [[ -z "$line" ]] && { echo -e " ❌ ${C_RED}Nie znaleziono '$u' w bazie.${C_RESET}"; continue; }
        local pass; pass=$(echo "$line" | cut -d: -f2)
        local cur_expire; cur_expire=$(echo "$line" | cut -d: -f3)
        local limit; limit=$(echo "$line" | cut -d: -f4)
        local bw; bw=$(echo "$line" | cut -d: -f5)
        [[ -z "$bw" ]] && bw="0"
        # Walidacja hasła - jeśli puste pobierz bezpośrednio z shadow
        if [[ -z "$pass" ]]; then
            echo -e " ⚠️  ${C_YELLOW}Brak hasła w bazie dla '$u' — pomijam przywracanie hasła.${C_RESET}"
        fi

        # Wyznacz datę bazową
        local base_date
        if [[ -n "$defer_date" ]]; then
            base_date="$defer_date"
        elif [[ -n "$cur_expire" ]] && [[ "$cur_expire" > "$today" || "$cur_expire" == "$today" ]]; then
            base_date="$cur_expire"
        else
            base_date="$today"
        fi


        local new_expire_date
        new_expire_date=$(date -d "$base_date +$days days" +%Y-%m-%d)

        if ! chage -E "$new_expire_date" "$u" 2>/dev/null; then
            echo -e " ❌ ${C_RED}chage failed for '$u' — konto systemowe nie zostało zaktualizowane.${C_RESET}"
            continue
        fi
        db_update_user "$u" "$pass" "$new_expire_date" "$limit" "$bw"

        # Jeśli data startu jest w przyszłości — zablokuj konto i ustaw cron odblokowania
        if [[ -n "$defer_date" && "$defer_date" > "$today" ]]; then
            usermod -L "$u" 2>/dev/null
            # Ustaw cron który odblokuje konto w dniu startu
            local unlock_hour; unlock_hour="0"
            local unlock_min; unlock_min="0"
            local unlock_day; unlock_day=$(date -d "$defer_date" +%d | sed 's/^0//')
            local unlock_month; unlock_month=$(date -d "$defer_date" +%m | sed 's/^0//')
            # Usuń stary cron dla tego użytkownika jeśli istnieje
            crontab -l 2>/dev/null | grep -v "ff_unlock_${u}" | crontab - 2>/dev/null
            # Dodaj nowy cron
            local cron_cmd="$unlock_min $unlock_hour $unlock_day $unlock_month * usermod -U $u && echo \"$u:$pass\" | chpasswd && chage -d \$(date +%Y-%m-%d) $u; echo 0 > $BANDWIDTH_DIR/${u}.usage 2>/dev/null; rm -f /run/ff_sessionban_${u} /run/ff_grace/exceed_${u} # ff_unlock_${u}"
            (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
            local defer_display; defer_display=$(date -d "$defer_date" +%d-%m-%Y)
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} odnowiony do ${C_GREEN}${new_expire_date}${C_RESET} — aktywny od ${C_CYAN}${defer_display}${C_RESET} (konto zablokowane do tego dnia)"
        else
            # Odblokuj natychmiast
            if ! usermod -U "$u" 2>/dev/null; then
                echo -e " ⚠️  ${C_YELLOW}usermod -U failed dla '$u'.${C_RESET}"
            fi
            # Zawsze przywróć hasło z bazy users.db (naprawia problem "złe hasło" po wygaśnięciu)
            if [[ -n "$pass" ]]; then
                if ! echo "$u:$pass" | chpasswd 2>/dev/null; then
                    echo -e " ⚠️  ${C_YELLOW}chpasswd failed dla '$u' — sprawdź hasło w bazie.${C_RESET}"
                fi
                # Resetuj flagę "hasło wygasłe" która może być ustawiona po expiracji
                chage -d "$(date +%Y-%m-%d)" "$u" 2>/dev/null
            else
                echo -e " ⚠️  ${C_YELLOW}Brak hasła dla '$u' — nie można przywrócić hasła.${C_RESET}"
            fi
            # KRYTYCZNE: zresetuj zużycie bandwidth, inaczej limiter w ciągu 20s ponownie
            # zablokuje konto (przekroczony quota) i TYM RAZEM bez przywrócenia hasła,
            # bo blokada za bandwidth nie ma logiki auto-unlock jak blokada za sesje.
            if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
                echo "0" > "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null
            fi
            rm -f "/run/ff_sessionban_${u}" 2>/dev/null
            rm -f "/run/ff_grace/exceed_${u}" 2>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} renewed until ${C_GREEN}${new_expire_date}${C_RESET} (+${days}d from ${base_date})."
        fi
    done
    
    # WAŻNE: Flush DB na dysk i restart limiter, żeby na pewno przeczytał nowe daty
    # Inaczej limiter stary cache'uje starą datę i RE-LOCKUJE w ciągu 20s
    sync "$DB_FILE" 2>/dev/null || true
    if systemctl is-active --quiet firewallfalcon-limiter; then
        echo -e "\n${C_DIM}🔄 Restarting limiter to pick up changes...${C_RESET}"
        systemctl restart firewallfalcon-limiter 2>/dev/null || true
        sleep 2
        echo -e "${C_GREEN}✅ Limiter restarted.${C_RESET}"
    fi
}

cleanup_expired() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🧹 Cleanup Expired Users ---${C_RESET}"
    
    local expired_users=()
    local current_ts
    current_ts=$(date +%s)

    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_GREEN}✅ User database is empty. No expired users found.${C_RESET}"
        return
    fi
    
    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        local expiry_ts
        expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        
        if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ No expired users found.${C_RESET}"
        return
    fi

    echo -e "\nThe following users have expired: ${C_RED}${expired_users[*]}${C_RESET}"
    read -p "👉 Do you want to delete all of them? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for user in "${expired_users[@]}"; do
            echo " - Deleting ${C_YELLOW}$user...${C_RESET}"
            killall -u "$user" -9 &>/dev/null
            # Clean up bandwidth tracking
            rm -f "$BANDWIDTH_DIR/${user}.usage"
            rm -rf "$BANDWIDTH_DIR/pidtrack/${user}"
            userdel -r "$user" &>/dev/null
            awk -F: -v u="$user" '$1 != u' "$DB_FILE" > "$DB_FILE.tmp" && chmod 600 "$DB_FILE.tmp" && sync "$DB_FILE.tmp" 2>/dev/null; mv "$DB_FILE.tmp" "$DB_FILE"
        done
        echo -e "\n${C_GREEN}✅ Expired users have been cleaned up.${C_RESET}"
        invalidate_banner_cache
        refresh_dynamic_banner_routing_if_enabled
    else
        echo -e "\n${C_YELLOW}❌ Cleanup cancelled.${C_RESET}"
    fi
}


_gdrive_setup() {
    if ! command -v rclone &>/dev/null; then
        echo -e "\n${C_BLUE}📦 Instalowanie rclone...${C_RESET}"
        curl -s https://rclone.org/install.sh | bash >/dev/null 2>&1
        if ! command -v rclone &>/dev/null; then
            echo -e "${C_RED}❌ Nie udało się zainstalować rclone.${C_RESET}"
            return 1
        fi
    fi
    if ! rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
        echo -e "\n${C_YELLOW}⚠️ Google Drive nie jest skonfigurowany.${C_RESET}"
        echo -e "${C_CYAN}Uruchamiam kreator konfiguracji rclone...${C_RESET}"
        echo -e "${C_DIM}Instrukcja:"
        echo -e "  1. Wpisz: n (new remote)"
        echo -e "  2. Nazwa: gdrive"
        echo -e "  3. Typ: drive (Google Drive)"
        echo -e "  4. Client ID i Secret: zostaw puste (Enter)"
        echo -e "  5. Scope: 1 (full access)"
        echo -e "  6. Root folder ID: zostaw puste (Enter)"
        echo -e "  7. Service account: zostaw puste (Enter)"
        echo -e "  8. Edit advanced: n"
        echo -e "  9. Use auto config: n"
        echo -e "  10. Skopiuj link do przeglądarki, zaloguj się na Google, wklej kod"
        echo -e "  11. Team drive: n"
        echo -e "  12. OK: y${C_RESET}\n"
        rclone config
        if ! rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
            echo -e "${C_RED}❌ Google Drive nie został skonfigurowany.${C_RESET}"
            return 1
        fi
    fi
    return 0
}

_gdrive_reauth() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ☁️ Konfiguracja Cloud Backup (rclone) ---${C_RESET}
"

    # Krok 1: Zainstaluj rclone jeśli brakuje
    if ! command -v rclone &>/dev/null; then
        echo -e "${C_BLUE}📦 rclone nie jest zainstalowany.${C_RESET}"
        read -r -p "👉 Zainstalować rclone? (t/n): " inst_choice
        if [[ "$inst_choice" != "t" && "$inst_choice" != "T" ]]; then return; fi
        echo -e "${C_BLUE}Instalowanie rclone...${C_RESET}"
        curl -s https://rclone.org/install.sh | bash >/dev/null 2>&1
        if ! command -v rclone &>/dev/null; then
            echo -e "${C_RED}❌ Nie udało się zainstalować rclone.${C_RESET}"
            return 1
        fi
        echo -e "${C_GREEN}✅ rclone zainstalowany pomyślnie.${C_RESET}
"
    else
        echo -e "${C_GREEN}✅ rclone zainstalowany ($(rclone version 2>/dev/null | head -1))${C_RESET}
"
    fi

    # Krok 2: Pokaż skonfigurowane usługi
    local remotes
    remotes=$(rclone listremotes 2>/dev/null)
    if [[ -n "$remotes" ]]; then
        echo -e "${C_CYAN}Skonfigurowane usługi:${C_RESET}"
        while IFS= read -r remote; do
            [[ -z "$remote" ]] && continue
            local rname="${remote%:}"
            if rclone lsd "$remote" &>/dev/null 2>&1; then
                echo -e "  ${C_GREEN}✅ $rname${C_RESET} — działa"
            else
                echo -e "  ${C_YELLOW}⚠️  $rname${C_RESET} — token wygasł lub błąd"
            fi
        done <<< "$remotes"
        echo
    else
        echo -e "${C_YELLOW}⚠️  Brak skonfigurowanych usług cloud.${C_RESET}
"
    fi

    # Krok 3: Menu akcji
    echo -e "  ${C_CHOICE}[1]${C_RESET} 🔄 Odnów token Google Drive (gdrive:)"
    echo -e "  ${C_CHOICE}[2]${C_RESET} ⚙️  Skonfiguruj Google Drive od nowa"
    echo -e "  ${C_CHOICE}[3]${C_RESET} 🌐 Skonfiguruj inną usługę (Dropbox, OneDrive, itp.)"
    echo -e "  ${C_CHOICE}[4]${C_RESET} 🗑️  Usuń konfigurację usługi"
    echo -e "  ${C_CHOICE}[5]${C_RESET} 📋 Otwórz pełny kreator rclone"
    echo -e "  ${C_WARN}[0]${C_RESET} ↩️  Anuluj
"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" rc_choice

    case "$rc_choice" in
        1)
            if ! rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
                echo -e "${C_RED}❌ Brak konfiguracji Google Drive — wybierz opcję [2].${C_RESET}"
                return 1
            fi
            echo -e "\n${C_BLUE}🔄 Odnawianie tokenu Google Drive...${C_RESET}"
            echo -e "${C_DIM}Instrukcja:"
            echo -e "  1. Skopiuj link który się pojawi do przeglądarki na telefonie"
            echo -e "  2. Zaloguj się na konto Google"
            echo -e "  3. Skopiuj kod i wklej tutaj${C_RESET}\n"
            rclone config reconnect gdrive:
            if rclone lsd gdrive: &>/dev/null 2>&1; then
                echo -e "\n${C_GREEN}✅ Token odnowiony! Google Drive działa poprawnie.${C_RESET}"
            else
                echo -e "\n${C_RED}❌ Nie udało się odnowić tokenu.${C_RESET}"
                echo -e "${C_YELLOW}Spróbuj opcji [2] — konfiguracja od nowa.${C_RESET}"
            fi
            ;;
        2)
            if rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
                echo -e "\n${C_BLUE}🗑️  Usuwanie starej konfiguracji gdrive...${C_RESET}"
                rclone config delete gdrive 2>/dev/null
            fi
            echo -e "\n${C_CYAN}Uruchamiam kreator konfiguracji Google Drive...${C_RESET}"
            echo -e "${C_DIM}Instrukcja:"
            echo -e "  1. Wpisz: n (new remote)"
            echo -e "  2. Nazwa: gdrive"
            echo -e "  3. Typ: drive (Google Drive)"
            echo -e "  4. Client ID i Secret: zostaw puste (Enter)"
            echo -e "  5. Scope: 1 (full access)"
            echo -e "  6. Root folder ID: zostaw puste (Enter)"
            echo -e "  7. Service account: zostaw puste (Enter)"
            echo -e "  8. Edit advanced: n"
            echo -e "  9. Use auto config: n"
            echo -e "  10. Skopiuj link do przeglądarki, zaloguj się, wklej kod"
            echo -e "  11. Team drive: n"
            echo -e "  12. Potwierdź: y${C_RESET}\n"
            rclone config
            if rclone listremotes 2>/dev/null | grep -q "^gdrive:" && rclone lsd gdrive: &>/dev/null 2>&1; then
                echo -e "\n${C_GREEN}✅ Google Drive skonfigurowany pomyślnie!${C_RESET}"
            else
                echo -e "\n${C_RED}❌ Konfiguracja nie powiodła się. Spróbuj ponownie.${C_RESET}"
            fi
            ;;
        3)
            echo -e "\n${C_CYAN}Uruchamiam kreator rclone — wybierz swoją usługę...${C_RESET}"
            echo -e "${C_DIM}Popularne: Dropbox, OneDrive, Box, Mega, pCloud, S3${C_RESET}\n"
            echo -e "${C_DIM}Instrukcja:"
            echo -e "  1. Wpisz: n (new remote)"
            echo -e "  2. Podaj nazwę np: dropbox"
            echo -e "  3. Wybierz typ usługi z listy"
            echo -e "  4. Postępuj zgodnie z instrukcjami${C_RESET}\n"
            rclone config
            echo -e "\n${C_GREEN}Skonfigurowane usługi:${C_RESET}"
            rclone listremotes 2>/dev/null | while read -r r; do
                echo -e "  • ${r%:}"
            done
            ;;
        4)
            local all_remotes
            all_remotes=$(rclone listremotes 2>/dev/null)
            if [[ -z "$all_remotes" ]]; then
                echo -e "\n${C_YELLOW}Brak skonfigurowanych usług.${C_RESET}"
                return
            fi
            echo -e "\n${C_CYAN}Skonfigurowane usługi:${C_RESET}"
            local ridx=1
            local -a remote_list=()
            while IFS= read -r r; do
                [[ -z "$r" ]] && continue
                remote_list+=("${r%:}")
                echo -e "  ${C_CHOICE}[$ridx]${C_RESET} ${r%:}"
                (( ridx++ ))
            done <<< "$all_remotes"
            echo -e "  ${C_WARN}[0]${C_RESET} Anuluj\n"
            read -r -p "$(echo -e "${C_PROMPT}  👉 Którą usunąć?: ${C_RESET}")" del_choice
            if [[ "$del_choice" =~ ^[0-9]+$ ]] && (( del_choice > 0 && del_choice <= ${#remote_list[@]} )); then
                local del_name="${remote_list[$((del_choice-1))]}"
                read -r -p "👉 Usunąć '$del_name'? (t/n): " confirm_del
                if [[ "$confirm_del" == "t" || "$confirm_del" == "T" ]]; then
                    rclone config delete "$del_name"
                    echo -e "${C_GREEN}✅ Usunięto: $del_name${C_RESET}"
                fi
            fi
            ;;
        5)
            echo -e "\n${C_CYAN}Otwieranie pełnego kreatora rclone...${C_RESET}\n"
            rclone config
            ;;
        0|"") return ;;
        *) echo -e "${C_RED}❌ Nieprawidłowy wybór.${C_RESET}" ;;
    esac
}

_telegram_send_message() {
    local token="$1"
    local chat_id="$2"
    local message="$3"
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=HTML" >/dev/null 2>&1
}

_autobackup_setup() {
    local config_file="$DB_DIR/autobackup.conf"

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⏰ Auto-Backup Konfiguracja ---${C_RESET}\n"

    # Load existing config
    local tg_token="" tg_chat_id="" backup_hour="3" gdrive_enabled="n"
    if [ -f "$config_file" ]; then
        source "$config_file"
    fi

    echo -e "${C_DIM}Obecna konfiguracja:${C_RESET}"
    echo -e "  Telegram token : ${C_YELLOW}${tg_token:-nie ustawiony}${C_RESET}"
    echo -e "  Telegram chat  : ${C_YELLOW}${tg_chat_id:-nie ustawiony}${C_RESET}"
    echo -e "  Godzina backup : ${C_YELLOW}${backup_hour}:00${C_RESET}"
    echo -e "  Google Drive   : ${C_YELLOW}${gdrive_enabled}${C_RESET}\n"

    read -p "👉 Bot Token Telegram (Enter = bez zmian): " inp
    [ -n "$inp" ] && tg_token="$inp"

    read -p "👉 Chat ID Telegram (Enter = bez zmian): " inp
    [ -n "$inp" ] && tg_chat_id="$inp"

    read -p "👉 Godzina wykonania backup 0-23 [${backup_hour}]: " inp
    if [[ "$inp" =~ ^[0-9]+$ ]] && [ "$inp" -ge 0 ] && [ "$inp" -le 23 ]; then
        backup_hour="$inp"
    fi

    read -p "👉 Wysyłać też na Google Drive? (t/n) [${gdrive_enabled}]: " inp
    [ "$inp" == "t" ] && gdrive_enabled="y" || { [ "$inp" == "n" ] && gdrive_enabled="n"; }

    # Save config
    cat > "$config_file" << EOF
tg_token="${tg_token}"
tg_chat_id="${tg_chat_id}"
backup_hour="${backup_hour}"
gdrive_enabled="${gdrive_enabled}"
EOF

    # Write the autobackup script
    cat > /usr/local/bin/firewallfalcon-autobackup.sh << 'ABEOF'
#!/bin/bash
DB_DIR="/etc/firewallfalcon"
DB_FILE="$DB_DIR/users.db"
CONFIG="$DB_DIR/autobackup.conf"

[ -f "$CONFIG" ] || exit 0
source "$CONFIG"
[ -s "$DB_FILE" ] || exit 0

ts=$(date +%Y%m%d_%H%M%S)
fname="firewallfalcon_backup_${ts}.tar.gz"
local_path="/root/${fname}"

tar -czf "$local_path" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")" 2>/dev/null
[ $? -ne 0 ] && exit 1

# Count users
user_count=$(grep -c "." "$DB_FILE" 2>/dev/null || echo 0)
server_ip=$(curl -s -4 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
size=$(du -sh "$local_path" | cut -f1)
date_str=$(date '+%Y-%m-%d %H:%M')

gdrive_link=""
if [ "$gdrive_enabled" = "y" ] && command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    rclone copy "$local_path" "gdrive:FirewallFalcon/" >/dev/null 2>&1
    gdrive_link=$(rclone link "gdrive:FirewallFalcon/${fname}" 2>/dev/null)
fi

# Usuń stare lokalne backupy — zachowaj ostatnie 5
ls -t /root/firewallfalcon_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null

if [ -n "$tg_token" ] && [ -n "$tg_chat_id" ]; then
    if [ -n "$gdrive_link" ]; then
        msg="$(printf "✅ FirewallFalcon Auto-Backup\n📅 Data: %s\n🌐 Serwer: %s\n👥 Użytkownicy: %s\n📦 Rozmiar: %s\n🔗 Backup: %s" "$date_str" "$server_ip" "$user_count" "$size" "$gdrive_link")"
    else
        msg="$(printf "✅ FirewallFalcon Auto-Backup\n📅 Data: %s\n🌐 Serwer: %s\n👥 Użytkownicy: %s\n📦 Rozmiar: %s\n💾 Plik: %s" "$date_str" "$server_ip" "$user_count" "$size" "$local_path")"
    fi
    curl -s -X POST "https://api.telegram.org/bot${tg_token}/sendMessage" \
        -d "chat_id=${tg_chat_id}" \
        --data-urlencode "text=${msg}" >/dev/null 2>&1
fi
ABEOF
    chmod +x /usr/local/bin/firewallfalcon-autobackup.sh

    # Setup cron - "0 ${backup_hour} * * *" = o pelnej godzinie backup_hour
    crontab -l 2>/dev/null | grep -v "firewallfalcon-autobackup" | { cat; echo "0 ${backup_hour} * * * /usr/local/bin/firewallfalcon-autobackup.sh"; } | crontab -

    echo -e "\n${C_GREEN}✅ Auto-backup skonfigurowany!${C_RESET}"
    echo -e "   Wykonywany codziennie o ${C_YELLOW}${backup_hour}:00${C_RESET}"
    [ -n "$tg_token" ] && echo -e "   Powiadomienie Telegram: ${C_GREEN}TAK${C_RESET}" || echo -e "   Powiadomienie Telegram: ${C_YELLOW}NIE (nie ustawiono tokena)${C_RESET}"
    [ "$gdrive_enabled" = "y" ] && echo -e "   Google Drive: ${C_GREEN}TAK${C_RESET}" || echo -e "   Google Drive: ${C_YELLOW}NIE${C_RESET}"

    # Test telegram if configured
    if [ -n "$tg_token" ] && [ -n "$tg_chat_id" ]; then
        read -p "👉 Wysłać wiadomość testową na Telegram? (t/n): " test_inp
        if [ "$test_inp" = "t" ]; then
            _telegram_send_message "$tg_token" "$tg_chat_id" "✅ FirewallFalcon: Telegram działa poprawnie!"
            echo -e "${C_GREEN}✅ Wiadomość testowa wysłana.${C_RESET}"
        fi
    fi
}

_autobackup_disable() {
    crontab -l 2>/dev/null | grep -v "firewallfalcon-autobackup" | crontab -
    rm -f /usr/local/bin/firewallfalcon-autobackup.sh "$DB_DIR/autobackup.conf"
    echo -e "\n${C_GREEN}✅ Auto-backup wyłączony.${C_RESET}"
}

backup_menu() {
    while true; do
        clear; show_banner
        local config_file="$DB_DIR/autobackup.conf"
        local auto_status="${C_STATUS_I}(Wyłączony)${C_RESET}"
        local tg_status="${C_STATUS_I}(Nie skonfigurowany)${C_RESET}"
        if crontab -l 2>/dev/null | grep -q "firewallfalcon-autobackup"; then
            auto_status="${C_STATUS_A}(Aktywny)${C_RESET}"
        fi
        if [ -f "$config_file" ]; then
            source "$config_file"
            if [ -n "$tg_token" ] && [ -n "$tg_chat_id" ]; then
                tg_status="${C_STATUS_A}(Skonfigurowany)${C_RESET}"
            fi
        fi

        echo -e "  ${C_BOLD}${C_WHITE}💾 BACKUP & PRZYWRACANIE${C_RESET}"
        local SEP2="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        echo -e "$SEP2"
        echo -e "  ${C_TITLE}${C_BOLD}📤 Kopia zapasowa${C_RESET}"
        printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %s\n" "💾" "Zapisz lokalnie"
        printf "  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s\n" "☁️ " "Wyślij na Google Drive (+ link)"
        echo
        echo -e "  ${C_TITLE}${C_BOLD}📥 Przywracanie${C_RESET}"
        printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %s\n" "📂" "Przywróć z pliku lokalnego"
        printf "  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s\n" "🔗" "Przywróć z linku (URL / Google Drive)"
        echo
        echo -e "  ${C_TITLE}${C_BOLD}⏰ Auto-backup${C_RESET}  ${auto_status}"
        printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %s\n" "⚙️ " "Konfiguruj auto-backup + Telegram"
        printf "  ${C_CHOICE}[ 6]${C_RESET}  %-2s %s  %s\n" "📱" "Status Telegram" "$tg_status"
        printf "  ${C_CHOICE}[ 7]${C_RESET}  %-2s %s\n" "▶️ " "Wykonaj backup teraz (testowy)"
        printf "  ${C_DANGER}[ 8]${C_RESET}  %-2s %s\n" "🚫" "Wyłącz auto-backup"
        echo
        # Status Google Drive
        local gdrive_status="${C_STATUS_I}(Nie skonfigurowany)${C_RESET}"
        if command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
            if rclone lsd gdrive: &>/dev/null 2>&1; then
                gdrive_status="${C_STATUS_A}(Aktywny ✅)${C_RESET}"
            else
                gdrive_status="${C_YELLOW}(Token wygasł ⚠️)${C_RESET}"
            fi
        fi
        echo -e "  ${C_TITLE}${C_BOLD}☁️  Google Drive${C_RESET}  ${gdrive_status}"
        printf "  ${C_CHOICE}[ 9]${C_RESET}  %-2s %s\n" "🔑" "Konfiguruj / Odnów token Google Drive"
        echo
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s\n" "↩️ " "Powrót do menu głównego"
        echo

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz opcję: ${C_RESET}")" bm_choice
        case "$bm_choice" in
            1) _backup_do local;  press_enter ;;
            2) _backup_do gdrive; press_enter ;;
            3) _restore_do local; press_enter ;;
            4) _restore_do url;   press_enter ;;
            5) _autobackup_setup; press_enter ;;
            6) _telegram_status;  press_enter ;;
            7) _backup_do test;   press_enter ;;
            8) _autobackup_disable; press_enter ;;
            9) _gdrive_reauth; press_enter ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

_backup_do() {
    local mode="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 💾 Kopia zapasowa ---${C_RESET}"

    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Brak danych użytkowników do zapisania.${C_RESET}"
        return
    fi

    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local fname="firewallfalcon_backup_${ts}.tar.gz"
    local local_path="/root/${fname}"

    echo -e "\n${C_BLUE}⚙️ Tworzenie archiwum...${C_RESET}"
    tar -czf "$local_path" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")"
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}❌ Błąd tworzenia archiwum.${C_RESET}"; return
    fi
    local size; size=$(du -sh "$local_path" | cut -f1)
    echo -e "${C_GREEN}✅ Archiwum: ${C_YELLOW}${local_path}${C_RESET} (${size})"

    if [ "$mode" = "local" ]; then
        echo -e "\n${C_GREEN}✅ Kopia zapisana lokalnie.${C_RESET}"
        return
    fi

    # gdrive or test (test also uploads)
    _gdrive_setup || return
    echo -e "\n${C_BLUE}☁️ Wysyłanie na Google Drive...${C_RESET}"
    rclone copy "$local_path" "gdrive:FirewallFalcon/" --progress
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}❌ Błąd wysyłania.${C_RESET}"; return
    fi
    echo -e "${C_BLUE}🔗 Generowanie linku...${C_RESET}"
    local gdrive_link
    gdrive_link=$(rclone link "gdrive:FirewallFalcon/${fname}" 2>/dev/null)
    echo -e "\n${C_GREEN}✅ Wysłano na Google Drive!${C_RESET}"
    if [ -n "$gdrive_link" ]; then
        echo -e "\n${C_BOLD}${C_CYAN}🔗 Link do pobrania:${C_RESET}"
        echo -e "   ${C_YELLOW}${gdrive_link}${C_RESET}"
        echo -e "\n${C_DIM}Użyj tego linku w opcji [4] na innym serwerze.${C_RESET}"

        # If test mode or telegram configured - send notification
        local config_file="$DB_DIR/autobackup.conf"
        if [ -f "$config_file" ]; then
            source "$config_file"
            if [ -n "$tg_token" ] && [ -n "$tg_chat_id" ]; then
                local user_count; user_count=$(grep -c "." "$DB_FILE" 2>/dev/null || echo 0)
                local server_ip; server_ip=$(curl -s -4 icanhazip.com 2>/dev/null || hostname -I | awk '"'"'{print $1}'"'"')
                local msg
                msg="$(printf '✅ FirewallFalcon Backup\n📅 Data: %s\n🌐 Serwer: %s\n👥 Użytkownicy: %s\n📦 Rozmiar: %s\n🔗 Link: %s' "$(date '+%Y-%m-%d %H:%M')" "$server_ip" "$user_count" "$size" "$gdrive_link")"
                _telegram_send_message "$tg_token" "$tg_chat_id" "$msg"
                echo -e "${C_GREEN}✅ Powiadomienie wysłane na Telegram.${C_RESET}"
            fi
        fi
    fi
}

_restore_do() {
    local mode="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📥 Przywróć kopię zapasową ---${C_RESET}"
    local backup_path=""

    if [ "$mode" = "local" ]; then
        read -p "👉 Podaj ścieżkę do pliku [/root/firewallfalcon_users.tar.gz]: " backup_path
        backup_path=${backup_path:-/root/firewallfalcon_users.tar.gz}
        if [ ! -f "$backup_path" ]; then
            echo -e "\n${C_RED}❌ Plik nie znaleziony: '$backup_path'${C_RESET}"; return
        fi
    else
        read -p "👉 Wklej link do pliku backup: " gdrive_url
        if [ -z "$gdrive_url" ]; then
            echo -e "${C_RED}❌ Nie podano linku.${C_RESET}"; return
        fi
        backup_path="/tmp/ff_restore_$$.tar.gz"
        echo -e "\n${C_BLUE}📥 Pobieranie...${C_RESET}"

        if echo "$gdrive_url" | grep -q "drive.google.com"; then
            local file_id=""
            if echo "$gdrive_url" | grep -q "/d/"; then
                file_id=$(echo "$gdrive_url" | sed 's|.*/d/||;s|[/?].*||')
            elif echo "$gdrive_url" | grep -q "id="; then
                file_id=$(echo "$gdrive_url" | sed 's/.*id=//;s/&.*//')
            fi
            if [ -n "$file_id" ]; then
                echo -e "${C_DIM}Google Drive ID: $file_id${C_RESET}"
                # Pobierz z potwierdzeniem (duże pliki Google Drive)
                wget -q --show-progress \
                    --save-cookies /tmp/gdcook_$$.txt \
                    --keep-session-cookies \
                    "https://drive.google.com/uc?export=download&id=${file_id}" \
                    -O /tmp/gdcheck_$$.html 2>/dev/null
                local confirm
                confirm=$(grep -oP 'confirm=\K[^&"'"'"']+' /tmp/gdcheck_$$.html 2>/dev/null | head -1)
                if [ -n "$confirm" ]; then
                    wget -q --show-progress \
                        --load-cookies /tmp/gdcook_$$.txt \
                        "https://drive.google.com/uc?export=download&id=${file_id}&confirm=${confirm}" \
                        -O "$backup_path"
                else
                    wget -q --show-progress \
                        --load-cookies /tmp/gdcook_$$.txt \
                        "https://drive.google.com/uc?export=download&confirm=t&id=${file_id}" \
                        -O "$backup_path"
                fi
                rm -f /tmp/gdcook_$$.txt /tmp/gdcheck_$$.html
            else
                wget -q --show-progress -O "$backup_path" "$gdrive_url"
            fi
        else
            wget -q --show-progress -O "$backup_path" "$gdrive_url"
        fi

        if [ $? -ne 0 ] || [ ! -s "$backup_path" ]; then
            echo -e "${C_RED}❌ Błąd pobierania.${C_RESET}"; rm -f "$backup_path"; return
        fi
        if file "$backup_path" 2>/dev/null | grep -qi "html\|text"; then
            echo -e "${C_RED}❌ Pobrany plik nie jest archiwum — możliwe że link wygasł.${C_RESET}"
            echo -e "${C_DIM}$(file "$backup_path" 2>/dev/null | cut -d: -f2)${C_RESET}"
            rm -f "$backup_path"; return
        fi
        echo -e "${C_GREEN}✅ Pobrano.${C_RESET}"
    fi

    echo -e "\n${C_RED}${C_BOLD}⚠️ UWAGA:${C_RESET} Nadpisze wszystkich obecnych użytkowników i ustawienia."
    read -p "👉 Na pewno przywrócić? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Anulowano.${C_RESET}"; return; fi

    local temp_dir; temp_dir=$(mktemp -d)
    tar -xzf "$backup_path" -C "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}❌ Błąd rozpakowania.${C_RESET}"; rm -rf "$temp_dir"; return
    fi
    local restored_db="$temp_dir/firewallfalcon/users.db"
    if [ ! -f "$restored_db" ]; then
        echo -e "${C_RED}❌ Brak users.db w archiwum.${C_RESET}"; rm -rf "$temp_dir"; return
    fi
    mkdir -p "$DB_DIR"
    cp "$restored_db" "$DB_FILE"
    for f in ssl dnstt; do [ -d "$temp_dir/firewallfalcon/$f" ] && cp -r "$temp_dir/firewallfalcon/$f" "$DB_DIR/"; done
    for f in dns_info.conf dnstt_info.conf falconproxy_config.conf nginx_ports.conf edge_cert.conf ban_history.log autobackup.conf; do
        [ -f "$temp_dir/firewallfalcon/$f" ] && cp "$temp_dir/firewallfalcon/$f" "$DB_DIR/"
    done
    ensure_firewallfalcon_system_group
    while IFS=: read -r user pass expiry limit _rest; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        id "$user" &>/dev/null || useradd -m -s /usr/sbin/nologin "$user"
        usermod -aG "$FF_USERS_GROUP" "$user" 2>/dev/null
        echo "$user:$pass" | chpasswd
        chage -E "$expiry" "$user"
        usermod -U "$user" &>/dev/null
        rm -f "/run/ff_sessionban_${user}" "/run/ff_grace/exceed_${user}" 2>/dev/null
    done < "$DB_FILE"
    rm -rf "$temp_dir"
    [ "$mode" = "url" ] && rm -f "$backup_path"
    echo -e "\n${C_GREEN}✅ Przywracanie zakończone pomyślnie!${C_RESET}"
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

_telegram_status() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📱 Status Telegram ---${C_RESET}\n"
    local config_file="$DB_DIR/autobackup.conf"
    if [ ! -f "$config_file" ]; then
        echo -e "${C_YELLOW}ℹ️ Telegram nie jest skonfigurowany.${C_RESET}"
        echo -e "${C_DIM}Wejdź w opcję [5] aby skonfigurować.${C_RESET}"
        return
    fi
    source "$config_file"
    echo -e "  Token : ${C_YELLOW}${tg_token:-nie ustawiony}${C_RESET}"
    echo -e "  Chat  : ${C_YELLOW}${tg_chat_id:-nie ustawiony}${C_RESET}"
    echo -e "  Auto  : ${C_YELLOW}${backup_hour:-?}:00 codziennie${C_RESET}"
    echo -e "  Drive : ${C_YELLOW}${gdrive_enabled:-n}${C_RESET}\n"
    if [ -n "$tg_token" ] && [ -n "$tg_chat_id" ]; then
        read -p "👉 Wysłać wiadomość testową? (t/n): " test_inp
        if [ "$test_inp" = "t" ]; then
            _telegram_send_message "$tg_token" "$tg_chat_id" "✅ <b>FirewallFalcon</b>: Test połączenia OK!"
            echo -e "${C_GREEN}✅ Wysłano.${C_RESET}"
        fi
    fi
}

_enable_banner_in_sshd_config() {
    echo -e "\n${C_BLUE}⚙️ Configuring sshd_config...${C_RESET}"
    disable_dynamic_ssh_banner_system
    sed -i.bak -E 's/^( *Banner *).*/#\1/' /etc/ssh/sshd_config
    if ! grep -q -E "^Banner $SSH_BANNER_FILE" /etc/ssh/sshd_config; then
        echo -e "\n# FirewallFalcon SSH Banner\nBanner $SSH_BANNER_FILE" >> /etc/ssh/sshd_config
    fi
    echo -e "${C_GREEN}✅ sshd_config updated.${C_RESET}"
}

_restart_ssh() {
    echo -e "\n${C_BLUE}🔄 Restarting SSH service to apply changes...${C_RESET}"
    local ssh_service_name=""
    if [ -f /lib/systemd/system/sshd.service ]; then
        ssh_service_name="sshd.service"
    elif [ -f /lib/systemd/system/ssh.service ]; then
        ssh_service_name="ssh.service"
    else
        echo -e "${C_RED}❌ Could not find sshd.service or ssh.service. Cannot restart SSH.${C_RESET}"
        return 1
    fi

    systemctl restart "${ssh_service_name}"
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✅ SSH service ('${ssh_service_name}') restarted successfully.${C_RESET}"
    else
        echo -e "${C_RED}❌ Failed to restart SSH service ('${ssh_service_name}'). Please check 'journalctl -u ${ssh_service_name}' for errors.${C_RESET}"
    fi
}

set_ssh_banner_paste() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Paste Static SSH Banner ---${C_RESET}"
    echo -e "Paste your custom banner below. Press ${C_YELLOW}[Ctrl+D]${C_RESET} when you are finished."
    echo -e "${C_DIM}This will be shown to all SSH users through 'Banner $SSH_BANNER_FILE'.${C_RESET}"
    echo -e "${C_DIM}The current banner (if any) will be overwritten.${C_RESET}"
    echo -e "--------------------------------------------------"
    cat > "$SSH_BANNER_FILE"
    chmod 644 "$SSH_BANNER_FILE"
    echo -e "\n--------------------------------------------------"
    echo -e "\n${C_GREEN}✅ Static banner content saved.${C_RESET}"
    _enable_banner_in_sshd_config
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

view_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👁️ Current SSH Banner ---${C_RESET}"
    if [ -f "$SSH_BANNER_FILE" ]; then
        echo -e "\n${C_CYAN}--- BEGIN BANNER ---${C_RESET}"
        cat "$SSH_BANNER_FILE"
        echo -e "${C_CYAN}---- END BANNER ----${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file found at $SSH_BANNER_FILE.${C_RESET}"
    fi
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

remove_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Disable SSH Banners ---${C_RESET}"
    read -p "👉 Are you sure you want to disable all SSH banners? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
        return
    fi
    if [ -f "$SSH_BANNER_FILE" ]; then
        rm -f "$SSH_BANNER_FILE"
        echo -e "\n${C_GREEN}✅ Removed banner file: $SSH_BANNER_FILE${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file to remove.${C_RESET}"
    fi
    disable_dynamic_ssh_banner_system
    echo -e "\n${C_BLUE}⚙️ Disabling banner in sshd_config...${C_RESET}"
    disable_static_ssh_banner_in_sshd_config
    echo -e "${C_GREEN}✅ Banner disabled in configuration.${C_RESET}"
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

preview_dynamic_ssh_banner() {
    if ! is_dynamic_ssh_banner_enabled; then
        echo -e "\n${C_RED}❌ Dynamic banners are not enabled right now.${C_RESET}"
        press_enter
        return
    fi

    echo -e "${C_DIM}Refreshing dynamic banner worker...${C_RESET}"
    setup_limiter_service >/dev/null 2>&1
    _select_user_interface "--- 📝 Preview Dynamic Banner ---"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        return
    fi

    echo -e "\n${C_CYAN}--- Dynamic Banner Preview for user '$u' ---${C_RESET}\n"
    if [[ -f "/etc/firewallfalcon/banners/${u}.txt" ]]; then
        cat "/etc/firewallfalcon/banners/${u}.txt"
    else
        echo -e "${C_RED}Banner file not generated yet. Waiting up to 10s for the worker...${C_RESET}"
        sleep 5
        if ! cat "/etc/firewallfalcon/banners/${u}.txt" 2>/dev/null; then
            echo -e "\n${C_RED}Still not generated. Here are the last limiter logs:${C_RESET}"
            echo -e "----------------------------------------------------------------------"
            journalctl -u firewallfalcon-limiter -n 15 --no-pager
            echo -e "----------------------------------------------------------------------"
        fi
    fi
    press_enter
}

install_udp_custom() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing udp-custom ---${C_RESET}"
    if [ -f "$UDP_CUSTOM_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ udp-custom is already installed.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}⚙️ Creating directory for udp-custom...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    mkdir -p "$UDP_CUSTOM_DIR"

    echo -e "\n${C_GREEN}⚙️ Detecting system architecture...${C_RESET}"
    local arch
    arch=$(uname -m)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://github.com/taifunss/FirewallFalcon-Manager/raw/main/udp/udp-custom-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://github.com/taifunss/FirewallFalcon-Manager/raw/main/udp/udp-custom-linux-arm"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install udp-custom.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi

    echo -e "\n${C_GREEN}📥 Downloading udp-custom binary...${C_RESET}"
    wget -q --show-progress -O "$UDP_CUSTOM_DIR/udp-custom" "$binary_url"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the udp-custom binary.${C_RESET}"
        rm -rf "$UDP_CUSTOM_DIR"
        return
    fi
    chmod +x "$UDP_CUSTOM_DIR/udp-custom"

    echo -e "\n${C_GREEN}📝 Creating default config.json...${C_RESET}"
    cat > "$UDP_CUSTOM_DIR/config.json" <<EOF
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    chmod 644 "$UDP_CUSTOM_DIR/config.json"

    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$UDP_CUSTOM_SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom by FirewallFalcon
After=network.target

[Service]
User=root
Type=simple
ExecStart=$UDP_CUSTOM_DIR/udp-custom server -exclude 53,5300
WorkingDirectory=$UDP_CUSTOM_DIR/
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF

    echo -e "\n${C_GREEN}▶️ Enabling and starting udp-custom service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable udp-custom.service
    systemctl start udp-custom.service
    sleep 2
    if systemctl is-active --quiet udp-custom; then
        echo -e "\n${C_GREEN}✅ SUCCESS: udp-custom is installed and active.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: udp-custom service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u udp-custom.service -n 15 --no-pager
    fi
}

uninstall_udp_custom() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling udp-custom ---${C_RESET}"
    if [ ! -f "$UDP_CUSTOM_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ udp-custom is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling udp-custom service...${C_RESET}"
    systemctl stop udp-custom.service >/dev/null 2>&1
    systemctl disable udp-custom.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$UDP_CUSTOM_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing udp-custom directory and files...${C_RESET}"
    rm -rf "$UDP_CUSTOM_DIR"
    echo -e "${C_GREEN}✅ udp-custom has been uninstalled successfully.${C_RESET}"
}


ensure_badvpn_service_is_quiet() {
    if [[ ! -f "$BADVPN_SERVICE_FILE" ]] || grep -q "^StandardOutput=null$" "$BADVPN_SERVICE_FILE" 2>/dev/null; then
        return
    fi

    local tmp_service
    tmp_service=$(mktemp)
    awk '
        /^\[Service\]$/ {
            print
            print "StandardOutput=null"
            print "StandardError=null"
            next
        }
        { print }
    ' "$BADVPN_SERVICE_FILE" > "$tmp_service" && mv "$tmp_service" "$BADVPN_SERVICE_FILE"
    rm -f "$tmp_service" 2>/dev/null
    systemctl daemon-reload
    systemctl restart badvpn.service >/dev/null 2>&1 || true
}

install_badvpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing badvpn (udpgw) ---${C_RESET}"
    if [ -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ badvpn is already installed.${C_RESET}"
        return
    fi
    check_and_open_firewall_port 7300 udp || return
    echo -e "\n${C_GREEN}🔄 Updating package lists...${C_RESET}"
    apt-get update
    echo -e "\n${C_GREEN}📦 Installing all required packages...${C_RESET}"
    apt-get install -y cmake g++ make screen git build-essential libssl-dev libnspr4-dev libnss3-dev pkg-config
    echo -e "\n${C_GREEN}📥 Cloning badvpn from github...${C_RESET}"
    git clone https://github.com/ambrop72/badvpn.git "$BADVPN_BUILD_DIR"
    cd "$BADVPN_BUILD_DIR" || { echo -e "${C_RED}❌ Failed to change directory to build folder.${C_RESET}"; return; }
    echo -e "\n${C_GREEN}⚙️ Running CMake...${C_RESET}"
    cmake . || { echo -e "${C_RED}❌ CMake configuration failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    echo -e "\n${C_GREEN}🛠️ Compiling source...${C_RESET}"
    make || { echo -e "${C_RED}❌ Compilation (make) failed.${C_RESET}"; rm -rf "$BADVPN_BUILD_DIR"; return; }
    local badvpn_binary
    badvpn_binary=$(find "$BADVPN_BUILD_DIR" -name "badvpn-udpgw" -type f | head -n 1)
    if [[ -z "$badvpn_binary" || ! -f "$badvpn_binary" ]]; then
        echo -e "${C_RED}❌ ERROR: Could not find the compiled 'badvpn-udpgw' binary after compilation.${C_RESET}"
        rm -rf "$BADVPN_BUILD_DIR"
        return
    fi
    echo -e "${C_GREEN}ℹ️ Found binary at: $badvpn_binary${C_RESET}"
    chmod +x "$badvpn_binary"
    echo -e "\n${C_GREEN}📝 Creating systemd service file...${C_RESET}"
    cat > "$BADVPN_SERVICE_FILE" <<-EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
ExecStart=$badvpn_binary --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 8
User=root
Restart=always
RestartSec=3
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_GREEN}▶️ Enabling and starting badvpn service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable badvpn.service
    systemctl start badvpn.service
    sleep 2
    if systemctl is-active --quiet badvpn; then
        echo -e "\n${C_GREEN}✅ SUCCESS: badvpn (udpgw) is installed and active on port 7300.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: badvpn service failed to start.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Displaying last 15 lines of the service log for diagnostics:${C_RESET}"
        journalctl -u badvpn.service -n 15 --no-pager
    fi
}

uninstall_badvpn() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling badvpn (udpgw) ---${C_RESET}"
    if [ ! -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ badvpn is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling badvpn service...${C_RESET}"
    systemctl stop badvpn.service >/dev/null 2>&1
    systemctl disable badvpn.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing systemd service file...${C_RESET}"
    rm -f "$BADVPN_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing badvpn build directory...${C_RESET}"
    rm -rf "$BADVPN_BUILD_DIR"
    echo -e "${C_GREEN}✅ badvpn has been uninstalled successfully.${C_RESET}"
}

load_edge_cert_info() {
    EDGE_CERT_MODE=""
    EDGE_DOMAIN=""
    EDGE_EMAIL=""
    if [ -f "$EDGE_CERT_INFO_FILE" ]; then
        source "$EDGE_CERT_INFO_FILE"
    fi
}

save_edge_cert_info() {
    local cert_mode="$1"
    local cert_domain="$2"
    local cert_email="$3"
    mkdir -p "$DB_DIR"
    cat > "$EDGE_CERT_INFO_FILE" <<EOF
EDGE_CERT_MODE="$cert_mode"
EDGE_DOMAIN="$cert_domain"
EDGE_EMAIL="$cert_email"
EOF
}

detect_preferred_host() {
    local host_domain=""
    load_edge_cert_info
    if [[ -n "$EDGE_DOMAIN" ]]; then
        host_domain="$EDGE_DOMAIN"
    fi
    if [[ -z "$host_domain" && -f "$DNS_INFO_FILE" ]]; then
        host_domain=$(grep 'FULL_DOMAIN' "$DNS_INFO_FILE" | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" && -f "$NGINX_CONFIG_FILE" ]]; then
        local nginx_domain
        nginx_domain=$(grep -oP 'server_name \K[^\s;]+' "$NGINX_CONFIG_FILE" 2>/dev/null | head -n 1)
        if [[ "$nginx_domain" != "_" && -n "$nginx_domain" ]]; then
            host_domain="$nginx_domain"
        fi
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(curl -s -4 icanhazip.com)
    fi
    echo "$host_domain"
}

backup_edge_configs() {
    if [ -f "$NGINX_CONFIG_FILE" ] && [ ! -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon" ]; then
        cp "$NGINX_CONFIG_FILE" "${NGINX_CONFIG_FILE}.bak.firewallfalcon" 2>/dev/null
    fi
    if [ -f "$HAPROXY_CONFIG" ] && [ ! -f "${HAPROXY_CONFIG}.bak.firewallfalcon" ]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.firewallfalcon" 2>/dev/null
    fi
}

ensure_edge_stack_packages() {
    local missing_packages=()
    command -v haproxy &> /dev/null || missing_packages+=("haproxy")
    command -v nginx &> /dev/null || missing_packages+=("nginx")
    command -v openssl &> /dev/null || missing_packages+=("openssl")

    if (( ${#missing_packages[@]} > 0 )); then
        echo -e "\n${C_BLUE}📦 Installing required packages: ${missing_packages[*]}${C_RESET}"
        apt-get update && apt-get install -y "${missing_packages[@]}" || {
            echo -e "${C_RED}❌ Failed to install the required packages.${C_RESET}"
            return 1
        }
    fi
    return 0
}

build_shared_tls_bundle() {
    if [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "${C_RED}❌ Certificate chain or key is missing.${C_RESET}"
        return 1
    fi
    cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > "$SSL_CERT_FILE" || return 1
    chmod 644 "$SSL_CERT_CHAIN_FILE"
    chmod 600 "$SSL_CERT_KEY_FILE" "$SSL_CERT_FILE"
    return 0
}

generate_self_signed_edge_cert() {
    local common_name="$1"
    mkdir -p "$SSL_CERT_DIR"
    echo -e "\n${C_GREEN}🔐 Generating a shared self-signed certificate...${C_RESET}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$SSL_CERT_KEY_FILE" \
        -out "$SSL_CERT_CHAIN_FILE" \
        -subj "/CN=$common_name" \
        >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to generate the self-signed certificate.${C_RESET}"
            return 1
        }
    build_shared_tls_bundle || return 1
    save_edge_cert_info "self-signed" "$common_name" ""
    echo -e "${C_GREEN}✅ Shared certificate created for ${C_YELLOW}$common_name${C_RESET}"
    return 0
}

_install_certbot() {
    if command -v certbot &> /dev/null; then
        echo -e "${C_GREEN}✅ Certbot is already installed.${C_RESET}"
        return 0
    fi
    echo -e "${C_BLUE}📦 Installing Certbot...${C_RESET}"
    apt-get update > /dev/null 2>&1
    apt-get install -y certbot || {
        echo -e "${C_RED}❌ Failed to install Certbot.${C_RESET}"
        return 1
    }
    echo -e "${C_GREEN}✅ Certbot installed successfully.${C_RESET}"
    return 0
}

obtain_certbot_edge_cert() {
    local domain_name="$1"
    local email="$2"
    local restart_haproxy=0
    local restart_nginx=0

    mkdir -p "$SSL_CERT_DIR"
    _install_certbot || return 1

    if systemctl is-active --quiet haproxy; then restart_haproxy=1; fi
    if systemctl is-active --quiet nginx; then restart_nginx=1; fi

    echo -e "\n${C_BLUE}🛑 Stopping HAProxy and Nginx for Certbot validation...${C_RESET}"
    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 2

    check_and_free_ports "$EDGE_PUBLIC_HTTP_PORT" "$EDGE_PUBLIC_TLS_PORT" || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }

    echo -e "\n${C_BLUE}🚀 Requesting a Certbot certificate for ${C_YELLOW}$domain_name${C_RESET}"
    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos -m "$email"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Certbot failed to obtain a certificate.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Make sure the domain points to this server and port 80 is reachable.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    local certbot_chain="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local certbot_key="/etc/letsencrypt/live/$domain_name/privkey.pem"
    if [ ! -f "$certbot_chain" ] || [ ! -f "$certbot_key" ]; then
        echo -e "\n${C_RED}❌ Certbot completed, but the certificate files were not found.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    cp "$certbot_chain" "$SSL_CERT_CHAIN_FILE"
    cp "$certbot_key" "$SSL_CERT_KEY_FILE"
    build_shared_tls_bundle || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }
    save_edge_cert_info "certbot" "$domain_name" "$email"
    echo -e "${C_GREEN}✅ Certbot certificate copied into ${C_YELLOW}$SSL_CERT_DIR${C_RESET}"
    return 0
}

select_edge_certificate() {
    local preferred_host
    local cert_choice
    local has_existing_cert=false

    preferred_host=$(detect_preferred_host)
    if [[ -z "$preferred_host" ]]; then
        preferred_host="firewallfalcon.local"
    fi

    if [ -s "$SSL_CERT_FILE" ] && [ -s "$SSL_CERT_CHAIN_FILE" ] && [ -s "$SSL_CERT_KEY_FILE" ]; then
        has_existing_cert=true
    fi

    load_edge_cert_info

    echo -e "\n${C_BOLD}${C_PURPLE}--- 🔐 Shared TLS Certificate ---${C_RESET}"
    echo -e "${C_DIM}The same certificate will be used by HAProxy and the internal Nginx proxy.${C_RESET}"

    if $has_existing_cert; then
        local existing_label="${EDGE_CERT_MODE:-existing}"
        if [[ -n "$EDGE_DOMAIN" ]]; then
            existing_label="$existing_label - $EDGE_DOMAIN"
        fi
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Reuse existing certificate (${existing_label})"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Replace with a new self-signed certificate"
        printf "  ${C_CHOICE}[ 3]${C_RESET} %-52s\n" "Replace with a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    else
        printf "  ${C_CHOICE}[ 1]${C_RESET} %-52s\n" "Generate a self-signed certificate"
        printf "  ${C_CHOICE}[ 2]${C_RESET} %-52s\n" "Use a Certbot certificate"
        echo
        read -p "👉 Enter choice [1]: " cert_choice
        cert_choice=${cert_choice:-1}
    fi

    case "$cert_choice" in
        1)
            if $has_existing_cert; then
                echo -e "${C_GREEN}✅ Reusing the existing shared certificate.${C_RESET}"
                return 0
            fi
            local common_name
            read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
            common_name=${common_name:-$preferred_host}
            generate_self_signed_edge_cert "$common_name"
            ;;
        2)
            if $has_existing_cert; then
                local common_name
                read -p "👉 Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
                common_name=${common_name:-$preferred_host}
                generate_self_signed_edge_cert "$common_name"
            else
                local default_domain=""
                local domain_name
                local email
                if ! _is_valid_ipv4 "$preferred_host"; then
                    default_domain="$preferred_host"
                fi
                if [[ -n "$default_domain" ]]; then
                    read -p "👉 Enter your domain name [$default_domain]: " domain_name
                    domain_name=${domain_name:-$default_domain}
                else
                    read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
                fi
                if [[ -z "$domain_name" ]]; then
                    echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                    return 1
                fi
                if _is_valid_ipv4 "$domain_name"; then
                    echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                    return 1
                fi
                read -p "👉 Enter your email for Let's Encrypt: " email
                if [[ -z "$email" ]]; then
                    echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                    return 1
                fi
                obtain_certbot_edge_cert "$domain_name" "$email"
            fi
            ;;
        3)
            if ! $has_existing_cert; then
                echo -e "${C_RED}❌ Invalid option.${C_RESET}"
                return 1
            fi
            local default_domain=""
            local domain_name
            local email
            if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
                default_domain="$EDGE_DOMAIN"
            fi
            if [[ -z "$default_domain" ]] && ! _is_valid_ipv4 "$preferred_host"; then
                default_domain="$preferred_host"
            fi
            if [[ -n "$default_domain" ]]; then
                read -p "👉 Enter your domain name [$default_domain]: " domain_name
                domain_name=${domain_name:-$default_domain}
            else
                read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
            fi
            if [[ -z "$domain_name" ]]; then
                echo -e "${C_RED}❌ Domain name cannot be empty.${C_RESET}"
                return 1
            fi
            if _is_valid_ipv4 "$domain_name"; then
                echo -e "${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                return 1
            fi
            read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
            email=${email:-$EDGE_EMAIL}
            if [[ -z "$email" ]]; then
                echo -e "${C_RED}❌ Email cannot be empty.${C_RESET}"
                return 1
            fi
            obtain_certbot_edge_cert "$domain_name" "$email"
            ;;
        *)
            echo -e "${C_RED}❌ Invalid option.${C_RESET}"
            return 1
            ;;
    esac
}

write_internal_nginx_config() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > "$NGINX_CONFIG_FILE" <<EOF
server {
    listen 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT} default_server;
    listen 127.0.0.1:${NGINX_INTERNAL_TLS_PORT} ssl http2 default_server;
    server_tokens off;
    server_name ${server_name};

    ssl_certificate ${SSL_CERT_CHAIN_FILE};
    ssl_certificate_key ${SSL_CERT_KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;

    location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)$ {
        client_max_body_size 0;
        client_body_timeout 1d;
        grpc_read_timeout 1d;
        grpc_socket_keepalive on;
        proxy_read_timeout 1d;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        if (\$content_type ~* "GRPC") { grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args; break; }
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }

    location / {
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_socket_keepalive on;
        tcp_nodelay on;
        tcp_nopush off;
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONFIG_FILE" /etc/nginx/sites-enabled/default
}

write_haproxy_edge_config() {
    mkdir -p /etc/haproxy
    cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  24h
    timeout server  24h

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_HTTP_PORT} (Cleartext Payloads & Raw SSH)
# ====================================================================
frontend port_80_edge
    bind *:${EDGE_PUBLIC_HTTP_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_TLS_PORT} (TLS v2ray, SSL Payloads, Raw SSH)
# ====================================================================
frontend port_443_edge
    bind *:${EDGE_PUBLIC_TLS_PORT}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    acl is_tls req.ssl_hello_type 1
    acl has_web_alpn req.ssl_alpn -m sub h2 http/1.1

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP
    tcp-request content accept if is_tls

    use_backend direct_ssh if is_ssh
    use_backend nginx_cleartext if HTTP
    use_backend nginx_tls if is_tls has_web_alpn
    default_backend loopback_ssl_terminator

# ====================================================================
# TIER 2: INTERNAL DECRYPTOR (Only for Any-SNI SSH-TLS)
# ====================================================================
frontend internal_decryptor
    bind 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT} ssl crt ${SSL_CERT_FILE}
    mode tcp
    tcp-request inspect-delay 2s

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend nginx_cleartext

# ====================================================================
# DESTINATION BACKENDS (Clean handoffs, no proxy headers)
# ====================================================================
backend direct_ssh
    mode tcp
    server ssh_server 127.0.0.1:22

backend nginx_cleartext
    mode tcp
    server nginx_8880 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}

backend nginx_tls
    mode tcp
    server nginx_8443 127.0.0.1:${NGINX_INTERNAL_TLS_PORT}

backend loopback_ssl_terminator
    mode tcp
    server haproxy_ssl 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT}
EOF
}

save_edge_ports_info() {
    cat > "$NGINX_PORTS_FILE" <<EOF
EDGE_HTTP_PORT="${EDGE_PUBLIC_HTTP_PORT}"
EDGE_TLS_PORT="${EDGE_PUBLIC_TLS_PORT}"
HTTP_PORTS="${NGINX_INTERNAL_HTTP_PORT}"
TLS_PORTS="${NGINX_INTERNAL_TLS_PORT}"
EOF
}

configure_edge_stack() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"

    backup_edge_configs

    echo -e "\n${C_BLUE}📝 Writing internal Nginx config (127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT})...${C_RESET}"
    write_internal_nginx_config "$server_name"

    echo -e "${C_BLUE}📝 Writing HAProxy edge config (${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT})...${C_RESET}"
    write_haproxy_edge_config

    echo -e "\n${C_BLUE}🧪 Validating Nginx configuration...${C_RESET}"
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${C_RED}❌ Nginx configuration validation failed.${C_RESET}"
        nginx -t
        return 1
    fi

    echo -e "${C_BLUE}🧪 Validating HAProxy configuration...${C_RESET}"
    if ! haproxy -c -f "$HAPROXY_CONFIG" >/dev/null 2>&1; then
        echo -e "${C_RED}❌ HAProxy configuration validation failed.${C_RESET}"
        haproxy -c -f "$HAPROXY_CONFIG"
        return 1
    fi

    systemctl daemon-reload
    systemctl enable nginx >/dev/null 2>&1
    systemctl enable haproxy >/dev/null 2>&1

    echo -e "\n${C_BLUE}▶️ Restarting internal Nginx...${C_RESET}"
    systemctl restart nginx || {
        echo -e "${C_RED}❌ Nginx failed to restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    }

    echo -e "${C_BLUE}▶️ Restarting HAProxy edge...${C_RESET}"
    systemctl restart haproxy || {
        echo -e "${C_RED}❌ HAProxy failed to restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    }

    sleep 2
    if ! systemctl is-active --quiet nginx; then
        echo -e "${C_RED}❌ Nginx is not active after restart.${C_RESET}"
        systemctl status nginx --no-pager
        return 1
    fi
    if ! systemctl is-active --quiet haproxy; then
        echo -e "${C_RED}❌ HAProxy is not active after restart.${C_RESET}"
        systemctl status haproxy --no-pager
        return 1
    fi

    save_edge_ports_info
    return 0
}

install_ssl_tunnel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing HAProxy Edge Stack (80/443 -> 8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This installer will configure:${C_RESET}"
    echo -e "   • HAProxy on ${C_WHITE}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx on ${C_WHITE}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Loopback SSL decryptor on ${C_WHITE}${HAPROXY_INTERNAL_DECRYPT_PORT}${C_RESET}"

    if [ -f "$HAPROXY_CONFIG" ] || [ -f "$NGINX_CONFIG_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ Existing HAProxy/Nginx configs will be replaced with the FirewallFalcon edge layout.${C_RESET}"
        read -p "👉 Continue with the replacement? (y/n): " confirm_replace
        if [[ "$confirm_replace" != "y" && "$confirm_replace" != "Y" ]]; then
            echo -e "${C_RED}❌ Installation cancelled.${C_RESET}"
            return
        fi
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"

    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    select_edge_certificate || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ SUCCESS: HAProxy edge stack is active.${C_RESET}"
    echo -e "   • Public edge ports: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx ports: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Shared certificate: ${C_YELLOW}${EDGE_CERT_MODE:-unknown}${C_RESET}"
}

uninstall_ssl_tunnel() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling HAProxy Edge Stack ---${C_RESET}"
    if ! command -v haproxy &> /dev/null; then
        echo -e "${C_YELLOW}ℹ️ HAProxy is not installed, skipping service removal.${C_RESET}"
    else
        echo -e "${C_GREEN}🛑 Stopping and disabling HAProxy...${C_RESET}"
        systemctl stop haproxy >/dev/null 2>&1
        systemctl disable haproxy >/dev/null 2>&1
    fi

    if [ -f "$HAPROXY_CONFIG" ]; then
        cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice

defaults
    log     global
EOF
    fi

    local delete_cert="n"
    if [[ "$UNINSTALL_MODE" == "silent" ]]; then
        delete_cert="y"
    elif [ -f "$SSL_CERT_FILE" ] || [ -f "$SSL_CERT_CHAIN_FILE" ] || [ -f "$SSL_CERT_KEY_FILE" ]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_YELLOW}⚠️ The shared certificate is also used by the internal Nginx proxy.${C_RESET}"
        fi
        read -p "👉 Delete the shared TLS certificate too? (y/n): " delete_cert
    fi

    if [[ "$delete_cert" == "y" || "$delete_cert" == "Y" ]]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_GREEN}🛑 Stopping Nginx because the shared certificate is being removed...${C_RESET}"
            systemctl stop nginx >/dev/null 2>&1
        fi
        rm -f "$SSL_CERT_FILE" "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" "$EDGE_CERT_INFO_FILE"
        rm -f "$NGINX_PORTS_FILE"
        echo -e "${C_GREEN}🗑️ Shared certificate files removed.${C_RESET}"
    fi

    echo -e "${C_GREEN}✅ HAProxy edge stack has been removed.${C_RESET}"
    if systemctl is-active --quiet nginx; then
        echo -e "${C_DIM}The internal Nginx proxy is still installed on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
    fi
}

show_dnstt_details() {
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        echo -e "\n${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}            📡 DNSTT Connection Details             ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_WHITE}Your connection details:${C_RESET}"
        echo -e "  - ${C_CYAN}Tunnel Domain:${C_RESET} ${C_YELLOW}$TUNNEL_DOMAIN${C_RESET}"
        echo -e "  - ${C_CYAN}Public Key:${C_RESET}    ${C_YELLOW}$PUBLIC_KEY${C_RESET}"
        if [[ -n "$FORWARD_DESC" ]]; then
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}$FORWARD_DESC${C_RESET}"
        else
            echo -e "  - ${C_CYAN}Forwarding To:${C_RESET} ${C_YELLOW}Unknown (config_missing)${C_RESET}"
        fi
        if [[ -n "$MTU_VALUE" ]]; then
            echo -e "  - ${C_CYAN}MTU Value:${C_RESET}     ${C_YELLOW}$MTU_VALUE${C_RESET}"
        fi
        if [[ "$DNSTT_RECORDS_MANAGED" == "false" && -n "$NS_DOMAIN" ]]; then
             echo -e "  - ${C_CYAN}NS Record:${C_RESET}     ${C_YELLOW}$NS_DOMAIN${C_RESET}"
        fi
        
        if [[ "$FORWARD_DESC" == *"V2Ray"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure a V2Ray service (vless/vmess/trojan) listens on port 8787 (no TLS)${C_RESET}"
        elif [[ "$FORWARD_DESC" == *"SSH"* ]]; then
             echo -e "  - ${C_CYAN}Action Required:${C_RESET} ${C_YELLOW}Ensure your SSH client is configured to use the DNS tunnel.${C_RESET}"
        fi
        
        echo -e "\n${C_DIM}Use these details in your client configuration.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ DNSTT configuration file not found. Details are unavailable.${C_RESET}"
    fi
}

install_dnstt() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📡 DNSTT (DNS Tunnel) Management ---${C_RESET}"
    if [ -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ DNSTT is already installed.${C_RESET}"
        show_dnstt_details
        return
    fi
    
    # --- FIX: Force release of Port 53 / Disable systemd-resolved ---
    echo -e "${C_GREEN}⚙️ Forcing release of Port 53 (stopping systemd-resolved)...${C_RESET}"
    systemctl stop systemd-resolved >/dev/null 2>&1
    systemctl disable systemd-resolved >/dev/null 2>&1
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null
    # ----------------------------------------------------------------
    
    echo -e "\n${C_BLUE}🔎 Checking if port 53 (UDP) is available...${C_RESET}"
    if ss -lunp | grep -q ':53\s'; then
        if [[ $(ps -p $(ss -lunp | grep ':53\s' | grep -oP 'pid=\K[0-9]+') -o comm=) == "systemd-resolve" ]]; then
            echo -e "${C_YELLOW}⚠️ Warning: Port 53 is in use by 'systemd-resolved'.${C_RESET}"
            echo -e "${C_YELLOW}This is the system's DNS stub resolver. It must be disabled to run DNSTT.${C_RESET}"
            read -p "👉 Allow the script to automatically disable it and reconfigure DNS? (y/n): " resolve_confirm
            if [[ "$resolve_confirm" == "y" || "$resolve_confirm" == "Y" ]]; then
                echo -e "${C_GREEN}⚙️ Stopping and disabling systemd-resolved to free port 53...${C_RESET}"
                systemctl stop systemd-resolved
                systemctl disable systemd-resolved
                chattr -i /etc/resolv.conf &>/dev/null
                rm -f /etc/resolv.conf
                echo "nameserver 8.8.8.8" > /etc/resolv.conf
                chattr +i /etc/resolv.conf
                echo -e "${C_GREEN}✅ Port 53 has been freed and DNS set to 8.8.8.8.${C_RESET}"
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port 53. Aborting.${C_RESET}"
                return
            fi
        else
            check_and_free_ports "53" || return
        fi
    else
        echo -e "${C_GREEN}✅ Port 53 (UDP) is free to use.${C_RESET}"
    fi

    check_and_open_firewall_port 53 udp || return



    local forward_port=""
    local forward_desc=""
    echo -e "\n${C_BLUE}Please choose where DNSTT should forward traffic:${C_RESET}"
    echo -e "  ${C_GREEN}[ 1]${C_RESET} ➡️ Forward to local SSH service (port 22)"
    echo -e "  ${C_GREEN}[ 2]${C_RESET} ➡️ Forward to local V2Ray backend (port 8787)"
    read -p "👉 Enter your choice [2]: " fwd_choice
    fwd_choice=${fwd_choice:-2}
    if [[ "$fwd_choice" == "1" ]]; then
        forward_port="22"
        forward_desc="SSH (port 22)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to SSH on 127.0.0.1:22.${C_RESET}"
        

        
    elif [[ "$fwd_choice" == "2" ]]; then
        forward_port="8787"
        forward_desc="V2Ray (port 8787)"
        echo -e "${C_GREEN}ℹ️ DNSTT will forward to V2Ray on 127.0.0.1:8787.${C_RESET}"
    else
        echo -e "${C_RED}❌ Invalid choice. Aborting.${C_RESET}"
        return
    fi
    local FORWARD_TARGET="127.0.0.1:$forward_port"
    
    local NS_DOMAIN=""
    local TUNNEL_DOMAIN=""
    local DNSTT_RECORDS_MANAGED="true"
    local NS_SUBDOMAIN=""
    local TUNNEL_SUBDOMAIN=""
    local HAS_IPV6="false"

    read -p "👉 Auto-generate DNS records or use custom ones? (auto/custom) [auto]: " dns_choice
    dns_choice=${dns_choice:-auto}

    if [[ "$dns_choice" == "custom" ]]; then
        DNSTT_RECORDS_MANAGED="false"
        read -p "👉 Enter your full nameserver domain (e.g., ns1.yourdomain.com): " NS_DOMAIN
        if [[ -z "$NS_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Nameserver domain cannot be empty. Aborting.${C_RESET}"; return; fi
        read -p "👉 Enter your full tunnel domain (e.g., tun.yourdomain.com): " TUNNEL_DOMAIN
        if [[ -z "$TUNNEL_DOMAIN" ]]; then echo -e "\n${C_RED}❌ Tunnel domain cannot be empty. Aborting.${C_RESET}"; return; fi
    else
        echo -e "\n${C_BLUE}⚙️ Configuring DNS records for DNSTT...${C_RESET}"
        local SERVER_IPV4
        SERVER_IPV4=$(curl -s -4 icanhazip.com)
        if ! _is_valid_ipv4 "$SERVER_IPV4"; then
            echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
            echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
            echo -e "   Output received: '$SERVER_IPV4'"
            return 1
        fi
        
        local SERVER_IPV6
        SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)
        
        local RANDOM_STR
        RANDOM_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
        NS_SUBDOMAIN="ns-$RANDOM_STR"
        TUNNEL_SUBDOMAIN="tun-$RANDOM_STR"
        NS_DOMAIN="$NS_SUBDOMAIN.$DESEC_DOMAIN"
        TUNNEL_DOMAIN="$TUNNEL_SUBDOMAIN.$DESEC_DOMAIN"

        local API_DATA
        API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}, {"subname": "%s", "type": "NS", "ttl": 3600, "records": ["%s."]}]' \
            "$NS_SUBDOMAIN" "$SERVER_IPV4" "$TUNNEL_SUBDOMAIN" "$NS_DOMAIN")

        if [[ -n "$SERVER_IPV6" ]]; then
            local aaaa_record
            aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$NS_SUBDOMAIN" "$SERVER_IPV6")
            API_DATA="${API_DATA%?}${aaaa_record}]"
            HAS_IPV6="true"
        fi

        local CREATE_RESPONSE
        CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
            --data "$API_DATA")
        
        local HTTP_CODE=${CREATE_RESPONSE: -3}
        local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

        if [[ "$HTTP_CODE" -ne 201 ]]; then
            echo -e "${C_RED}❌ Failed to create DNSTT records. API returned HTTP $HTTP_CODE.${C_RESET}"
            echo "Response: $RESPONSE_BODY" | jq
            return 1
        fi
    fi
    
    read -p "👉 Enter MTU value (e.g., 512, 1200) or press [Enter] for default: " mtu_value
    local mtu_string=""
    if [[ "$mtu_value" =~ ^[0-9]+$ ]]; then
        mtu_string=" -mtu $mtu_value"
        echo -e "${C_GREEN}ℹ️ Using MTU: $mtu_value${C_RESET}"
    else
        mtu_value=""
        echo -e "${C_YELLOW}ℹ️ Using default MTU.${C_RESET}"
    fi

    echo -e "\n${C_BLUE}📥 Downloading pre-compiled DNSTT server binary...${C_RESET}"
    local arch
    arch=$(uname -m)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected x86_64 (amd64) architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Unsupported architecture: $arch. Cannot install DNSTT.${C_RESET}"
        return
    fi
    
    curl -sL "$binary_url" -o "$DNSTT_BINARY"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Failed to download the DNSTT binary.${C_RESET}"
        return
    fi
    chmod +x "$DNSTT_BINARY"

    echo -e "${C_BLUE}🔐 Generating cryptographic keys...${C_RESET}"
    mkdir -p "$DNSTT_KEYS_DIR"
    "$DNSTT_BINARY" -gen-key -privkey-file "$DNSTT_KEYS_DIR/server.key" -pubkey-file "$DNSTT_KEYS_DIR/server.pub"
    if [[ ! -f "$DNSTT_KEYS_DIR/server.key" ]]; then echo -e "${C_RED}❌ Failed to generate DNSTT keys.${C_RESET}"; return; fi
    
    local PUBLIC_KEY
    PUBLIC_KEY=$(cat "$DNSTT_KEYS_DIR/server.pub")
    
    echo -e "\n${C_BLUE}📝 Creating systemd service...${C_RESET}"
    cat > "$DNSTT_SERVICE_FILE" <<-EOF
[Unit]
Description=DNSTT (DNS Tunnel) Server for $forward_desc
After=network.target
[Service]
Type=simple
User=root
ExecStart=$DNSTT_BINARY -udp :53$mtu_string -privkey-file $DNSTT_KEYS_DIR/server.key $TUNNEL_DOMAIN $FORWARD_TARGET
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    echo -e "\n${C_BLUE}💾 Saving configuration and starting service...${C_RESET}"
    cat > "$DNSTT_CONFIG_FILE" <<-EOF
NS_SUBDOMAIN="$NS_SUBDOMAIN"
TUNNEL_SUBDOMAIN="$TUNNEL_SUBDOMAIN"
NS_DOMAIN="$NS_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
PUBLIC_KEY="$PUBLIC_KEY"
FORWARD_DESC="$forward_desc"
DNSTT_RECORDS_MANAGED="$DNSTT_RECORDS_MANAGED"
HAS_IPV6="$HAS_IPV6"
MTU_VALUE="$mtu_value"
EOF
    systemctl daemon-reload
    systemctl enable dnstt.service
    systemctl start dnstt.service
    sleep 2
    if systemctl is-active --quiet dnstt.service; then
        echo -e "\n${C_GREEN}✅ SUCCESS: DNSTT has been installed and started!${C_RESET}"
        show_dnstt_details
    else
        echo -e "\n${C_RED}❌ ERROR: DNSTT service failed to start.${C_RESET}"
        journalctl -u dnstt.service -n 15 --no-pager
    fi
}

uninstall_dnstt() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling DNSTT ---${C_RESET}"
    if [ ! -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ DNSTT does not appear to be installed, skipping.${C_RESET}"
        return
    fi
    local confirm="y"
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        read -p "👉 Are you sure you want to uninstall DNSTT? This will delete DNS records if they were auto-generated. (y/n): " confirm
    fi
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
        return
    fi
    echo -e "${C_BLUE}🛑 Stopping and disabling DNSTT service...${C_RESET}"
    systemctl stop dnstt.service > /dev/null 2>&1
    systemctl disable dnstt.service > /dev/null 2>&1
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        if [[ "$DNSTT_RECORDS_MANAGED" == "true" ]]; then
            echo -e "${C_BLUE}🗑️ Removing auto-generated DNS records...${C_RESET}"
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$TUNNEL_SUBDOMAIN/NS/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/A/" \
                 -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            if [[ "$HAS_IPV6" == "true" ]]; then
                curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$NS_SUBDOMAIN/AAAA/" \
                     -H "Authorization: Token $DESEC_TOKEN" > /dev/null
            fi
            echo -e "${C_GREEN}✅ DNS records have been removed.${C_RESET}"
        else
            echo -e "${C_YELLOW}⚠️ DNS records were manually configured. Please delete them from your DNS provider.${C_RESET}"
        fi
    fi
    echo -e "${C_BLUE}🗑️ Removing service files and binaries...${C_RESET}"
    rm -f "$DNSTT_SERVICE_FILE"
    rm -f "$DNSTT_BINARY"
    rm -rf "$DNSTT_KEYS_DIR"
    rm -f "$DNSTT_CONFIG_FILE"
    systemctl daemon-reload
    
    echo -e "${C_YELLOW}ℹ️ Making /etc/resolv.conf writable again...${C_RESET}"
    chattr -i /etc/resolv.conf &>/dev/null

    echo -e "\n${C_GREEN}✅ DNSTT has been successfully uninstalled.${C_RESET}"
}

install_falcon_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🦅 Installing Falcon Proxy ---${C_RESET}"

    if [ -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Falcon Proxy is already installed.${C_RESET}"
        if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then
            source "$FALCONPROXY_CONFIG_FILE"
            echo -e "   Port(s): ${C_YELLOW}$PORTS${C_RESET}  Version: ${C_YELLOW}${INSTALLED_VERSION:-Unknown}${C_RESET}"
        fi
        read -p "👉 Do you want to reinstall/update? (y/n): " confirm_reinstall
        if [[ "$confirm_reinstall" != "y" ]]; then return; fi
        systemctl stop falconproxy.service 2>/dev/null
    fi

    echo -e "\n${C_BLUE}🌐 Fetching available versions from GitHub...${C_RESET}"
    local releases_json
    releases_json=$(curl -s "https://api.github.com/repos/taifunss/FirewallFalcon-Manager/releases")
    if [[ -z "$releases_json" || "$releases_json" == "[]" ]]; then
        echo -e "${C_RED}❌ Could not fetch releases. Check internet connection.${C_RESET}"
        return
    fi

    mapfile -t versions < <(echo "$releases_json" | jq -r '.[].tag_name')
    if [ ${#versions[@]} -eq 0 ]; then
        echo -e "${C_RED}❌ No releases found.${C_RESET}"
        return
    fi

    echo -e "\n${C_CYAN}Select a version to install:${C_RESET}"
    for i in "${!versions[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${versions[$i]}"
    done
    echo -e "  ${C_RED} [ 0]${C_RESET} ↩️ Cancel"

    local choice
    while true; do
        if ! read -r -p "👉 Enter version number [1]: " choice; then echo; return; fi
        choice=${choice:-1}
        [[ "$choice" == "0" ]] && return
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            SELECTED_VERSION="${versions[$((choice-1))]}"
            break
        fi
        echo -e "${C_RED}❌ Invalid selection.${C_RESET}"
    done

    local ports
    read -p "👉 Enter port(s) for Falcon Proxy (e.g., 8080 or 8080 8888) [8080]: " ports
    ports=${ports:-8080}
    local port_array=($ports)
    for port in "${port_array[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo -e "\n${C_RED}❌ Invalid port: $port${C_RESET}"; return
        fi
        check_and_free_ports "$port" || return
        check_and_open_firewall_port "$port" tcp || return
    done

    echo -e "\n${C_BLUE}⚙️ Detecting architecture...${C_RESET}"
    local arch; arch=$(uname -m)
    local binary_name
    if [[ "$arch" == "x86_64" ]]; then
        binary_name="falconproxy"
        echo -e "${C_BLUE}ℹ️ x86_64 detected.${C_RESET}"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_name="falconproxyarm"
        echo -e "${C_BLUE}ℹ️ ARM64 detected.${C_RESET}"
    else
        echo -e "${C_RED}❌ Unsupported architecture: $arch${C_RESET}"; return
    fi

    local download_url="https://github.com/taifunss/FirewallFalcon-Manager/releases/download/$SELECTED_VERSION/$binary_name"
    echo -e "\n${C_BLUE}📥 Downloading Falcon Proxy $SELECTED_VERSION...${C_RESET}"
    wget -q --show-progress -O "$FALCONPROXY_BINARY" "$download_url"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ Download failed.${C_RESET}"; return
    fi
    chmod +x "$FALCONPROXY_BINARY"

    # Usuń link do Telegrama z binarki (podmień bajty, zachowaj tę samą długość)
    if command -v python3 &>/dev/null; then
        python3 -c "
data = open('$FALCONPROXY_BINARY','rb').read()
old = b'HTTP/1.1 101 t.me/firewallfalcons'
new = b'HTTP/1.1 101 Switching Protocols '
if old in data:
    open('$FALCONPROXY_BINARY','wb').write(data.replace(old, new))
    print('✅ Telegram link removed from binary.')
else:
    print('ℹ️ No Telegram link found in binary (already clean).')
" 2>/dev/null
    fi

    echo -e "\n${C_BLUE}📝 Creating systemd service...${C_RESET}"
    cat > "$FALCONPROXY_SERVICE_FILE" << EOF
[Unit]
Description=Falcon Proxy ($SELECTED_VERSION)
After=network.target

[Service]
User=root
Type=simple
ExecStart=$FALCONPROXY_BINARY -p $ports
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF

    cat > "$FALCONPROXY_CONFIG_FILE" << EOF
PORTS="$ports"
INSTALLED_VERSION="$SELECTED_VERSION"
EOF

    systemctl daemon-reload
    systemctl enable falconproxy.service
    systemctl restart falconproxy.service
    sleep 2

    if systemctl is-active --quiet falconproxy; then
        echo -e "\n${C_GREEN}✅ Falcon Proxy $SELECTED_VERSION active on port(s): ${C_YELLOW}$ports${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Service failed to start.${C_RESET}"
        journalctl -u falconproxy.service -n 15 --no-pager
    fi
}

uninstall_falcon_proxy() {
    echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling Falcon Proxy ---${C_RESET}"
    if [ ! -f "$FALCONPROXY_SERVICE_FILE" ]; then
        echo -e "${C_YELLOW}ℹ️ Falcon Proxy is not installed, skipping.${C_RESET}"
        return
    fi
    echo -e "${C_GREEN}🛑 Stopping and disabling Falcon Proxy service...${C_RESET}"
    systemctl stop falconproxy.service >/dev/null 2>&1
    systemctl disable falconproxy.service >/dev/null 2>&1
    echo -e "${C_GREEN}🗑️ Removing service file...${C_RESET}"
    rm -f "$FALCONPROXY_SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${C_GREEN}🗑️ Removing binary and config files...${C_RESET}"
    rm -f "$FALCONPROXY_BINARY"
    rm -f "$FALCONPROXY_CONFIG_FILE"
    echo -e "${C_GREEN}✅ Falcon Proxy has been uninstalled successfully.${C_RESET}"
}

# --- ZiVPN Installation Logic ---
install_zivpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Installing ZiVPN (UDP/VPN) ---${C_RESET}"
    
    if [ -f "$ZIVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ ZiVPN is already installed.${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}⚙️ Checking system architecture...${C_RESET}"
    local arch=$(uname -m)
    local zivpn_url=""
    
    if [[ "$arch" == "x86_64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
        echo -e "${C_BLUE}ℹ️ Detected AMD64/x86_64 architecture.${C_RESET}"
    elif [[ "$arch" == "aarch64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
        echo -e "${C_BLUE}ℹ️ Detected ARM64 architecture.${C_RESET}"
    elif [[ "$arch" == "armv7l" || "$arch" == "arm" ]]; then
         zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm"
         echo -e "${C_BLUE}ℹ️ Detected ARM architecture.${C_RESET}"
    else
        echo -e "${C_RED}❌ Unsupported architecture: $arch${C_RESET}"
        return
    fi

    echo -e "\n${C_GREEN}📦 Downloading ZiVPN binary...${C_RESET}"
    if ! wget -q --show-progress -O "$ZIVPN_BIN" "$zivpn_url"; then
        echo -e "${C_RED}❌ Download failed. Check internet connection.${C_RESET}"
        return
    fi
    chmod +x "$ZIVPN_BIN"

    echo -e "\n${C_GREEN}⚙️ Configuring ZIVPN...${C_RESET}"
    mkdir -p "$ZIVPN_DIR"
    
    # Generate Certificates
    echo -e "${C_BLUE}🔐 Generating self-signed certificates...${C_RESET}"
    if ! command -v openssl &>/dev/null; then apt-get install -y openssl &>/dev/null; fi
    
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "$ZIVPN_KEY_FILE" -out "$ZIVPN_CERT_FILE" 2>/dev/null

    if [ ! -f "$ZIVPN_CERT_FILE" ]; then
        echo -e "${C_RED}❌ Failed to generate certificates.${C_RESET}"
        return
    fi

    # System Tuning
    echo -e "${C_BLUE}🔧 Tuning system network parameters...${C_RESET}"
    sysctl -w net.core.rmem_max=16777216 >/dev/null
    sysctl -w net.core.wmem_max=16777216 >/dev/null

    # Create Service
    echo -e "${C_BLUE}📝 Creating systemd service file...${C_RESET}"
    cat <<EOF > "$ZIVPN_SERVICE_FILE"
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$ZIVPN_DIR
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG_FILE
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # Configure Passwords
    echo -e "\n${C_YELLOW}🔑 ZiVPN Password Setup${C_RESET}"
    read -p "👉 Enter passwords separated by commas (e.g., user1,user2) [Default: 'zi']: " input_config
    
    if [ -n "$input_config" ]; then
        IFS=',' read -r -a config_array <<< "$input_config"
        # Ensure array format for JSON
        json_passwords=$(printf '"%s",' "${config_array[@]}")
        json_passwords="[${json_passwords%,}]"
    else
        json_passwords='["zi"]'
    fi

    # Create Config File
    cat <<EOF > "$ZIVPN_CONFIG_FILE"
{
  "listen": ":5667",
   "cert": "$ZIVPN_CERT_FILE",
   "key": "$ZIVPN_KEY_FILE",
   "obfs":"zivpn",
   "auth": {
    "mode": "passwords", 
    "config": $json_passwords
  }
}
EOF

    echo -e "\n${C_GREEN}🚀 Starting ZiVPN Service...${C_RESET}"
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service

    # Port Forwarding / Firewall
    echo -e "${C_BLUE}🔥 Configuring Firewall Rules (Redirecting 6000-19999 -> 5667)...${C_RESET}"
    
    # Determine primary interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    if [ -n "$iface" ]; then
        iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
        # Note: IPTables rules are not persistent by default without iptables-persistent package
    else
        echo -e "${C_YELLOW}⚠️ Could not detect default interface for IPTables redirection.${C_RESET}"
    fi

    if command -v ufw &>/dev/null; then
        ufw allow 6000:19999/udp >/dev/null
        ufw allow 5667/udp >/dev/null
    fi

    # Cleanup
    rm -f zi.sh zi2.sh 2>/dev/null

    if systemctl is-active --quiet zivpn.service; then
        echo -e "\n${C_GREEN}✅ ZiVPN Installed Successfully!${C_RESET}"
        echo -e "   - UDP Port: 5667 (Direct)"
        echo -e "   - UDP Ports: 6000-19999 (Forwarded)"
    else
        echo -e "\n${C_RED}❌ ZiVPN Service failed to start. Check logs: journalctl -u zivpn.service${C_RESET}"
    fi
}

uninstall_zivpn() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall ZiVPN ---${C_RESET}"
    
    if [ ! -f "$ZIVPN_SERVICE_FILE" ] && [ ! -f "$ZIVPN_BIN" ]; then
        echo -e "\n${C_YELLOW}ℹ️ ZiVPN does not appear to be installed.${C_RESET}"
        return
    fi

    read -p "👉 Are you sure you want to uninstall ZiVPN? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "${C_YELLOW}Cancelled.${C_RESET}"; return; fi

    echo -e "\n${C_BLUE}🛑 Stopping services...${C_RESET}"
    systemctl stop zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null
    
    echo -e "${C_BLUE}🗑️ Removing files...${C_RESET}"
    rm -f "$ZIVPN_SERVICE_FILE"
    rm -rf "$ZIVPN_DIR"
    rm -f "$ZIVPN_BIN"
    
    systemctl daemon-reload
    
    # Clean cache (from original uninstall script logic)
    echo -e "${C_BLUE}🧹 Cleaning memory cache...${C_RESET}"
    sync; echo 3 > /proc/sys/vm/drop_caches

    echo -e "\n${C_GREEN}✅ ZiVPN Uninstalled Successfully.${C_RESET}"
}

purge_nginx() {
    local mode="$1"
    if [[ "$mode" != "silent" ]]; then
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🔥 Purge Internal Nginx Proxy ---${C_RESET}"
        if ! command -v nginx &> /dev/null; then
            rm -f "$NGINX_PORTS_FILE"
            echo -e "\n${C_YELLOW}ℹ️ Nginx is not installed. Nothing to do.${C_RESET}"
            return
        fi
        echo -e "\n${C_YELLOW}⚠️ This removes the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            echo -e "${C_YELLOW}⚠️ HAProxy will stay installed, but web payload routing from ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} will stop until you reinstall the stack.${C_RESET}"
        fi
        read -p "👉 Continue and purge Nginx? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
            return
        fi
    fi
    echo -e "\n${C_BLUE}🛑 Stopping Nginx service...${C_RESET}"
    systemctl stop nginx >/dev/null 2>&1
    systemctl disable nginx >/dev/null 2>&1
    echo -e "\n${C_BLUE}🗑️ Purging Nginx packages...${C_RESET}"
    apt-get purge -y nginx nginx-common >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1
    echo -e "\n${C_BLUE}🗑️ Removing leftover files...${C_RESET}"
    rm -f /etc/ssl/certs/nginx-selfsigned.pem
    rm -f /etc/ssl/private/nginx-selfsigned.key
    rm -rf /etc/nginx
    rm -f "${NGINX_CONFIG_FILE}.bak"
    rm -f "${NGINX_CONFIG_FILE}.bak.certbot"
    rm -f "${NGINX_CONFIG_FILE}.bak.selfsigned"
    rm -f "${NGINX_CONFIG_FILE}.bak.firewallfalcon"
    rm -f "$NGINX_PORTS_FILE"
    if [[ "$mode" != "silent" ]]; then
        echo -e "\n${C_GREEN}✅ Internal Nginx proxy purged. Shared FirewallFalcon certificates were kept.${C_RESET}"
    fi
}

install_nginx_proxy() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Reconfiguring Internal Nginx Proxy (8880/8443) ---${C_RESET}"
    echo -e "\n${C_CYAN}This keeps HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} and rewrites the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    if [ ! -s "$SSL_CERT_FILE" ] || [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "\n${C_YELLOW}⚠️ No shared FirewallFalcon certificate was found.${C_RESET}"
        echo -e "${C_DIM}Running the full HAProxy edge installer so the certificate and both services stay aligned.${C_RESET}"
        install_ssl_tunnel
        return
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}✅ Internal Nginx proxy reconfigured successfully.${C_RESET}"
    echo -e "   • Public HAProxy edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
}

request_certbot_ssl() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Shared Certbot Certificate (HAProxy + Nginx) ---${C_RESET}"
    echo -e "\n${C_DIM}This will replace the shared certificate used by HAProxy on ${EDGE_PUBLIC_TLS_PORT} and internal Nginx on ${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return
    load_edge_cert_info

    local preferred_host
    local default_domain=""
    local domain_name
    local email

    preferred_host=$(detect_preferred_host)
    if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
        default_domain="$EDGE_DOMAIN"
    elif [[ -n "$preferred_host" ]] && ! _is_valid_ipv4 "$preferred_host"; then
        default_domain="$preferred_host"
    fi

    if [[ -n "$default_domain" ]]; then
        read -p "👉 Enter your domain name [$default_domain]: " domain_name
        domain_name=${domain_name:-$default_domain}
    else
        read -p "👉 Enter your domain name (e.g. vpn.example.com): " domain_name
    fi
    if [[ -z "$domain_name" ]]; then
        echo -e "\n${C_RED}❌ Domain name cannot be empty.${C_RESET}"
        return
    fi
    if _is_valid_ipv4 "$domain_name"; then
        echo -e "\n${C_RED}❌ Certbot requires a real domain name, not a raw IP address.${C_RESET}"
        return
    fi

    read -p "👉 Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
    email=${email:-$EDGE_EMAIL}
    if [[ -z "$email" ]]; then
        echo -e "\n${C_RED}❌ Email address cannot be empty.${C_RESET}"
        return
    fi

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    obtain_certbot_edge_cert "$domain_name" "$email" || return
    configure_edge_stack "$domain_name" || return

    echo -e "\n${C_GREEN}✅ Shared Certbot certificate applied successfully.${C_RESET}"
    echo -e "   • Domain: ${C_YELLOW}${domain_name}${C_RESET}"
    echo -e "   • Public edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
}

nginx_proxy_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Internal Nginx Proxy Management ---${C_RESET}"

    local nginx_status="${C_STATUS_I}Inactive${C_RESET}"
    local haproxy_status="${C_STATUS_I}Inactive${C_RESET}"
    if systemctl is-active --quiet nginx; then
        nginx_status="${C_STATUS_A}Active${C_RESET}"
    fi
    if systemctl is-active --quiet haproxy; then
        haproxy_status="${C_STATUS_A}Active${C_RESET}"
    fi

    load_edge_cert_info
    local cert_info="${EDGE_CERT_MODE:-Not configured}"
    if [[ -n "$EDGE_DOMAIN" ]]; then
        cert_info="${cert_info} - ${EDGE_DOMAIN}"
    fi

    echo -e "\n${C_WHITE}Nginx:${C_RESET} ${nginx_status}"
    echo -e "${C_WHITE}HAProxy:${C_RESET} ${haproxy_status}"
    echo -e "${C_DIM}Public Edge: ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} | Internal Nginx: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "${C_DIM}Shared Certificate: ${cert_info}${C_RESET}"

    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    
    if systemctl is-active --quiet nginx; then
         printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🛑 Stop Nginx Service"
         printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "🔄 Restart HAProxy + Nginx Stack"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "⚙️ Re-install/Re-configure Edge Stack"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "🔒 Switch/Renew Shared SSL (Certbot)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "🔥 Uninstall/Purge Nginx"
    else
         printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "▶️ Start Nginx Service"
         printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "⚙️ Install/Configure Edge Stack"
         printf "  ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "🔒 Switch/Renew Shared SSL (Certbot)"
         printf "  ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "🔥 Uninstall/Purge Nginx"
    fi

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return to previous menu"
    echo
    read -p "👉 Enter your choice: " choice
    
    case $choice in
        1) 
            if systemctl is-active --quiet nginx; then
                echo -e "\n${C_BLUE}🛑 Stopping Nginx...${C_RESET}"
                systemctl stop nginx
                echo -e "${C_GREEN}✅ Nginx stopped.${C_RESET}"
                if systemctl is-active --quiet haproxy; then
                    echo -e "${C_YELLOW}⚠️ HAProxy is still running, but web traffic that depends on internal Nginx will not work until Nginx starts again.${C_RESET}"
                fi
            else
                echo -e "\n${C_BLUE}▶️ Starting Nginx...${C_RESET}"
                systemctl start nginx
                if systemctl is-active --quiet nginx; then
                    echo -e "${C_GREEN}✅ Nginx started.${C_RESET}"
                else
                    echo -e "${C_RED}❌ Failed to start Nginx.${C_RESET}"
                fi
            fi
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}🔄 Restarting Nginx and HAProxy...${C_RESET}"
            local restart_ok=true
            systemctl restart nginx || restart_ok=false
            if command -v haproxy &> /dev/null; then
                systemctl restart haproxy || restart_ok=false
            else
                restart_ok=false
            fi
            if $restart_ok && systemctl is-active --quiet nginx && systemctl is-active --quiet haproxy; then
                echo -e "${C_GREEN}✅ HAProxy + Nginx stack restarted.${C_RESET}"
            else
                echo -e "${C_RED}❌ One or more services failed to restart.${C_RESET}"
            fi
            press_enter
            ;;
        3) 
             install_nginx_proxy; press_enter
             ;;
        4)
             request_certbot_ssl; press_enter
             ;;
        5)
             purge_nginx; press_enter
             ;;
        0) return ;;
        *) invalid_option ;;
    esac
}

install_xui_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚀 Install X-UI Panel ---${C_RESET}"
    echo -e "\nThis will download and run the official installation script for X-UI."
    echo -e "Choose an installation option:\n"
    echo -e "Choose an installation option:\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} %-40s\n" "Install the latest version of X-UI"
    printf "  ${C_GREEN}[ 2]${C_RESET} %-40s\n" "Install a specific version of X-UI"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ❌ Cancel Installation"
    echo
    read -p "👉 Select an option: " choice
    case $choice in
        1)
            echo -e "\n${C_BLUE}⚙️ Installing the latest version...${C_RESET}"
            bash <(curl -Ls https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh)
            ;;
        2)
            read -p "👉 Enter the version to install (e.g., 1.8.0): " version
            if [[ -z "$version" ]]; then
                echo -e "\n${C_RED}❌ Version number cannot be empty.${C_RESET}"
                return
            fi
            echo -e "\n${C_BLUE}⚙️ Installing version ${C_YELLOW}$version...${C_RESET}"
            VERSION=$version bash <(curl -Ls "https://raw.githubusercontent.com/alireza0/x-ui/$version/install.sh") "$version"
            ;;
        0)
            echo -e "\n${C_YELLOW}❌ Installation cancelled.${C_RESET}"
            ;;
        *)
            echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"
            ;;
    esac
}

uninstall_xui_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Uninstall X-UI Panel ---${C_RESET}"
    if ! command -v x-ui &> /dev/null; then
        echo -e "\n${C_YELLOW}ℹ️ X-UI does not appear to be installed.${C_RESET}"
        return
    fi
    read -p "👉 Are you sure you want to thoroughly uninstall X-UI? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        echo -e "\n${C_BLUE}⚙️ Running the default X-UI uninstaller first...${C_RESET}"
        x-ui uninstall >/dev/null 2>&1
        echo -e "\n${C_BLUE}🧹 Performing a full cleanup to ensure complete removal...${C_RESET}"
        echo " - Stopping and disabling x-ui service..."
        systemctl stop x-ui >/dev/null 2>&1
        systemctl disable x-ui >/dev/null 2>&1
        echo " - Removing x-ui files and directories..."
        rm -f /etc/systemd/system/x-ui.service
        rm -f /usr/local/bin/x-ui
        rm -rf /usr/local/x-ui/
        rm -rf /etc/x-ui/
        echo " - Reloading systemd daemon..."
        systemctl daemon-reload
        echo -e "\n${C_GREEN}✅ X-UI has been thoroughly uninstalled.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
    fi
}

refresh_ssh_session_cache() {
    local now db_mtime
    now=$(date +%s)
    db_mtime=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo 0)

    if (( SSH_SESSION_CACHE_TS > 0 && now - SSH_SESSION_CACHE_TS < SSH_SESSION_CACHE_TTL && db_mtime == SSH_SESSION_CACHE_DB_MTIME )); then
        return
    fi

    SSH_SESSION_COUNTS=()
    SSH_SESSION_PIDS=()
    SSH_SESSION_TOTAL=0
    SSH_SESSION_CACHE_DB_MTIME=$db_mtime

    if [[ ! -s "$DB_FILE" ]]; then
        SSH_SESSION_CACHE_TS=$now
        return
    fi

    local -A managed_user_lookup=()
    local -A uid_user_lookup=()
    local -A seen_sessions=()
    local managed_user system_user system_uid ssh_pid ssh_owner candidate_user login_uid

    while IFS=: read -r managed_user _rest; do
        [[ -n "$managed_user" && "$managed_user" != \#* ]] && managed_user_lookup["$managed_user"]=1
    done < "$DB_FILE"

    while IFS=: read -r system_user _ system_uid _rest; do
        [[ -n "$system_user" && "$system_uid" =~ ^[0-9]+$ ]] && uid_user_lookup["$system_uid"]="$system_user"
    done < /etc/passwd

    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue

        candidate_user=""
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" && -n "${managed_user_lookup[$ssh_owner]+x}" ]]; then
            candidate_user="$ssh_owner"
        elif [[ -r "/proc/$ssh_pid/loginuid" ]]; then
            login_uid=""
            read -r login_uid < "/proc/$ssh_pid/loginuid" || login_uid=""
            if [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]]; then
                candidate_user="${uid_user_lookup[$login_uid]}"
            fi
        fi

        [[ -n "$candidate_user" && -n "${managed_user_lookup[$candidate_user]+x}" ]] || continue
        [[ -z "${seen_sessions[$candidate_user:$ssh_pid]+x}" ]] || continue

        seen_sessions["$candidate_user:$ssh_pid"]=1
        ((SSH_SESSION_COUNTS["$candidate_user"]++))
        SSH_SESSION_PIDS["$candidate_user"]+="$ssh_pid "
        ((SSH_SESSION_TOTAL++))
    done < <(ps -C sshd -o pid=,user= 2>/dev/null)

    SSH_SESSION_CACHE_TS=$now
}

count_managed_online_sessions() {
    refresh_ssh_session_cache
    echo "$SSH_SESSION_TOTAL"
}

invalidate_banner_cache() {
    BANNER_CACHE_TS=0
    SSH_SESSION_CACHE_TS=0
}

refresh_banner_cache() {
    local now
    now=$(date +%s)
    if (( BANNER_CACHE_TS > 0 && now - BANNER_CACHE_TS < BANNER_CACHE_TTL )); then
        return
    fi

    if [[ -z "$BANNER_CACHE_OS_NAME" ]]; then
        BANNER_CACHE_OS_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    fi
    BANNER_CACHE_UP_TIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    BANNER_CACHE_RAM_USAGE=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    BANNER_CACHE_CPU_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [[ -s "$DB_FILE" ]]; then
        BANNER_CACHE_TOTAL_USERS=$(grep -c . "$DB_FILE")
    else
        BANNER_CACHE_TOTAL_USERS=0
    fi
    BANNER_CACHE_ONLINE_USERS=$(count_managed_online_sessions)
    BANNER_CACHE_TS=$now
}

show_banner() {
    refresh_banner_cache
    [[ -t 1 ]] && clear
    echo
    echo -e "${C_TITLE}   FirewallFalcon Manager ${C_RESET}${C_DIM}| v4.0.0 Premium Edition${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "OS" "$BANNER_CACHE_OS_NAME" "Uptime: $BANNER_CACHE_UP_TIME"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Memory" "${BANNER_CACHE_RAM_USAGE}% Used" "Online Sessions: ${C_WHITE}${BANNER_CACHE_ONLINE_USERS}${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Users" "${BANNER_CACHE_TOTAL_USERS} Managed Accounts" "Sys Load (1m): ${C_GREEN}${BANNER_CACHE_CPU_LOAD}${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
}

warp_menu() {
    local mode="$1"
    clear; show_banner

    case "$mode" in
        wgd) echo -e "${C_BOLD}${C_PURPLE}--- ☁️  Cloudflare WARP — IPv4 + IPv6 ---${C_RESET}" ;;
        wg4) echo -e "${C_BOLD}${C_PURPLE}--- ☁️  Cloudflare WARP — tylko IPv4 ---${C_RESET}" ;;
        wg6) echo -e "${C_BOLD}${C_PURPLE}--- ☁️  Cloudflare WARP — tylko IPv6 ---${C_RESET}" ;;
        dwg) echo -e "${C_BOLD}${C_PURPLE}--- 🗑️  Cloudflare WARP — wyłączanie ---${C_RESET}" ;;
    esac

    if [[ "$mode" == "dwg" ]]; then
        read -p "👉 Na pewno wyłączyć WARP? (y/n): " confirm
        [[ "$confirm" != "y" ]] && { echo -e "${C_YELLOW}❌ Anulowano.${C_RESET}"; return; }
    fi

    echo -e "
${C_BLUE}📥 Pobieranie warp.sh...${C_RESET}"
    rm -f /tmp/warp.sh
    wget -q -O /tmp/warp.sh "https://raw.githubusercontent.com/P3TERX/warp.sh/main/warp.sh"
    if [ $? -ne 0 ] || [ ! -s /tmp/warp.sh ]; then
        echo -e "${C_RED}❌ Nie udało się pobrać warp.sh. Sprawdź połączenie.${C_RESET}"
        return
    fi
    chmod +x /tmp/warp.sh

    echo -e "${C_BLUE}⚙️ Uruchamianie instalatora WARP (tryb: ${mode})...${C_RESET}
"
    bash /tmp/warp.sh "$mode"
    local exit_code=$?
    rm -f /tmp/warp.sh

    echo
    if [ $exit_code -eq 0 ]; then
        if [[ "$mode" == "dwg" ]]; then
            echo -e "${C_GREEN}✅ WARP został wyłączony.${C_RESET}"
        else
            echo -e "${C_GREEN}✅ WARP zainstalowany pomyślnie!${C_RESET}"
            echo -e "
${C_DIM}Sprawdź IP:${C_RESET}"
            curl -s -4 https://icanhazip.com 2>/dev/null && echo " (IPv4)"
            curl -s -6 https://icanhazip.com 2>/dev/null && echo " (IPv6)"
        fi
    else
        echo -e "${C_RED}❌ Instalacja zakończona błędem (kod: $exit_code).${C_RESET}"
    fi
}



protocol_menu() {
    while true; do
        show_banner
        local badvpn_status; if systemctl is-active --quiet badvpn; then badvpn_status="${C_STATUS_A}(Active)${C_RESET}"; else badvpn_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local udp_custom_status; if systemctl is-active --quiet udp-custom; then udp_custom_status="${C_STATUS_A}(Active)${C_RESET}"; else udp_custom_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local zivpn_status; if systemctl is-active --quiet zivpn.service; then zivpn_status="${C_STATUS_A}(Active)${C_RESET}"; else zivpn_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        
        local ssl_tunnel_text="HAProxy Edge Stack (80/443)"
        local ssl_tunnel_status="${C_STATUS_I}(Inactive)${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            ssl_tunnel_status="${C_STATUS_A}(Active)${C_RESET}"
        fi
        
        local dnstt_status; if systemctl is-active --quiet dnstt.service; then dnstt_status="${C_STATUS_A}(Active)${C_RESET}"; else dnstt_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        
        local falconproxy_status="${C_STATUS_I}(Inactive)${C_RESET}"
        local falconproxy_ports=""
        if systemctl is-active --quiet falconproxy; then
            if [ -f "$FALCONPROXY_CONFIG_FILE" ]; then source "$FALCONPROXY_CONFIG_FILE"; fi
            falconproxy_ports=" ($PORTS)"
            falconproxy_status="${C_STATUS_A}(Active - ${INSTALLED_VERSION:-latest})${C_RESET}"
        fi

        local nginx_status; if systemctl is-active --quiet nginx; then nginx_status="${C_STATUS_A}(Active)${C_RESET}"; else nginx_status="${C_STATUS_I}(Inactive)${C_RESET}"; fi
        local xui_status; if command -v x-ui &> /dev/null; then xui_status="${C_STATUS_A}(Installed)${C_RESET}"; else xui_status="${C_STATUS_I}(Not Installed)${C_RESET}"; fi
        local stunnel_st; stunnel_st=$(stunnel_status)
        local dropbear_st; dropbear_st=$(dropbear_status)
        local xray_st; xray_st=$(xray_status_str)
        local warp_status="${C_STATUS_I}(Inactive)${C_RESET}"
        if systemctl is-active --quiet wg-quick@wgcf 2>/dev/null || ip link show wgcf &>/dev/null 2>/dev/null; then
            warp_status="${C_STATUS_A}(Active)${C_RESET}"
        fi
        
        echo -e "\n   ${C_TITLE}══════════════[ ${C_BOLD}🔌 PROTOCOL & PANEL MANAGEMENT ${C_RESET}${C_TITLE}]══════════════${C_RESET}"
        echo -e "     ${C_ACCENT}--- TUNNELLING PROTOCOLS---${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-45s %s\n" "🚀 Install badvpn (UDP 7300)" "$badvpn_status"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-45s\n" "🗑️ Uninstall badvpn"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-45s %s\n" "🚀 Install udp-custom" "$udp_custom_status"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-45s\n" "🗑️ Uninstall udp-custom"
        printf "     ${C_CHOICE}[ 5]${C_RESET} %-45s %s\n" "🔒 Install ${ssl_tunnel_text}" "$ssl_tunnel_status"
        printf "     ${C_CHOICE}[ 6]${C_RESET} %-45s\n" "🗑️ Uninstall HAProxy Edge Stack"
        printf "     ${C_CHOICE}[ 7]${C_RESET} %-45s %s\n" "📡 Install/View DNSTT (Port 53)" "$dnstt_status"
        printf "     ${C_CHOICE}[ 8]${C_RESET} %-45s\n" "🗑️ Uninstall DNSTT"
        printf "     ${C_CHOICE}[ 9]${C_RESET} %-45s %s\n" "🦅 Install Falcon Proxy (Select Version)" "$falconproxy_status"
        printf "     ${C_CHOICE}[10]${C_RESET} %-45s\n" "🗑️ Uninstall Falcon Proxy"
        printf "     ${C_CHOICE}[11]${C_RESET} %-45s %s\n" "🌐 Install/Manage Internal Nginx (8880/8443)" "$nginx_status"
        printf "     ${C_CHOICE}[16]${C_RESET} %-45s %s\n" "🛡️ Install ZiVPN (UDP 5667)" "$zivpn_status"
        printf "     ${C_CHOICE}[17]${C_RESET} %-45s\n" "🗑️ Uninstall ZiVPN"
        
        echo -e "     ${C_ACCENT}--- ☁️  CLOUDFLARE WARP ---${C_RESET}"
        printf "     ${C_CHOICE}[18]${C_RESET} %-45s %s\n" "☁️  WARP IPv4+IPv6" "$warp_status"
        printf "     ${C_CHOICE}[22]${C_RESET} %-45s\n" "🎬 Streaming Bypass (Netflix/Disney+/HBO przez WARP)"
        printf "     ${C_CHOICE}[19]${C_RESET} %-45s\n" "☁️  WARP tylko IPv4"
        printf "     ${C_CHOICE}[20]${C_RESET} %-45s\n" "☁️  WARP tylko IPv6"
        printf "     ${C_DANGER}[21]${C_RESET} %-45s\n" "🗑️ Wyłącz WARP"

        echo -e "     ${C_ACCENT}--- 🔒 DODATKOWE PROTOKOŁY ---${C_RESET}"
        printf "     ${C_CHOICE}[23]${C_RESET} %-45s %s\n" "🔒 Stunnel4 (porty 222, 333, 777)" "$stunnel_st"
        printf "     ${C_CHOICE}[24]${C_RESET} %-45s %s\n" "💧 Dropbear SSH (porty 109, 143)" "$dropbear_st"
        printf "     ${C_CHOICE}[25]${C_RESET} %-45s %s\n" "⚡ Xray/V2Ray (VLess/VMess/Trojan/SS)" "$xray_st"

        echo -e "     ${C_ACCENT}--- 💻 MANAGEMENT PANELS ---${C_RESET}"
        printf "     ${C_CHOICE}[12]${C_RESET} %-45s %s\n" "💻 Install X-UI Panel" "$xui_status"
        printf "     ${C_CHOICE}[13]${C_RESET} %-45s\n" "🗑️ Uninstall X-UI Panel"
        
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return to Main Menu"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1) install_badvpn; press_enter ;; 2) uninstall_badvpn; press_enter ;;
            3) install_udp_custom; press_enter ;; 4) uninstall_udp_custom; press_enter ;;
            5) install_ssl_tunnel; press_enter ;; 6) uninstall_ssl_tunnel; press_enter ;;
            7) install_dnstt; press_enter ;; 8) uninstall_dnstt; press_enter ;;
            9) install_falcon_proxy; press_enter ;; 10) uninstall_falcon_proxy; press_enter ;;
            11) nginx_proxy_menu ;;
            12) install_xui_panel; press_enter ;; 13) uninstall_xui_panel; press_enter ;;
            16) install_zivpn; press_enter ;; 17) uninstall_zivpn; press_enter ;;
            18) warp_menu "wgd"; press_enter ;;
            22) streaming_bypass_menu ;;
            19) warp_menu "wg4"; press_enter ;;
            20) warp_menu "wg6"; press_enter ;;
            21) warp_menu "dwg"; press_enter ;;
            23) stunnel_menu ;;
            24) dropbear_menu ;;
            25) xray_menu ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

uninstall_script() {
    clear; show_banner
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_RED}       🔥 DANGER: UNINSTALL SCRIPT & ALL DATA 🔥      ${C_RESET}"
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_YELLOW}This will PERMANENTLY remove this script and all its components, including:"
    echo -e " - The main command ($(command -v menu))"
    echo -e " - All configuration and user data ($DB_DIR)"
    echo -e " - The active limiter service ($LIMITER_SERVICE)"
    echo -e " - All installed services (badvpn, udp-custom, HAProxy Edge Stack, Nginx, DNSTT)"
    echo -e "\n${C_RED}This action is irreversible.${C_RESET}"
    echo ""
    read -p "👉 Type 'yes' to confirm and proceed with uninstallation: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "\n${C_GREEN}✅ Uninstallation cancelled.${C_RESET}"
        return
    fi
    local -a removable_users=()
    local remove_users_confirm
    local remove_users_on_uninstall=false
    mapfile -t removable_users < <(get_firewallfalcon_known_users)
    if [[ ${#removable_users[@]} -gt 0 ]]; then
        echo -e "\n${C_YELLOW}FirewallFalcon SSH users detected on this VPS:${C_RESET} ${removable_users[*]}"
        read -p "👉 Do you also want to permanently delete these SSH users before uninstalling? (y/n): " remove_users_confirm
        if [[ "$remove_users_confirm" == "y" || "$remove_users_confirm" == "Y" ]]; then
            remove_users_on_uninstall=true
        fi
    fi
    export UNINSTALL_MODE="silent"
    echo -e "\n${C_BLUE}--- 💥 Starting Uninstallation 💥 ---${C_RESET}"
    
    if [[ "$remove_users_on_uninstall" == "true" ]]; then
        echo -e "\n${C_BLUE}🗑️ Removing FirewallFalcon SSH users before uninstall...${C_RESET}"
        delete_firewallfalcon_user_accounts "${removable_users[@]}"
    fi
    
    echo -e "\n${C_BLUE}🗑️ Removing active limiter service...${C_RESET}"
    systemctl stop firewallfalcon-limiter &>/dev/null
    systemctl disable firewallfalcon-limiter &>/dev/null
    rm -f "$LIMITER_SERVICE"
    rm -f "$LIMITER_SCRIPT"
    
    echo -e "\n${C_BLUE}🗑️ Removing bandwidth monitoring service...${C_RESET}"
    systemctl stop firewallfalcon-bandwidth &>/dev/null
    systemctl disable firewallfalcon-bandwidth &>/dev/null
    rm -f "$BANDWIDTH_SERVICE"
    rm -f "$BANDWIDTH_SCRIPT"
    rm -f "$TRIAL_CLEANUP_SCRIPT"
    
    echo -e "\n${C_BLUE}\ud83d\uddd1\ufe0f Removing SSH login banner...${C_RESET}"
    rm -f "$LOGIN_INFO_SCRIPT"
    rm -f "$SSHD_FF_CONFIG"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    
    chattr -i /etc/resolv.conf &>/dev/null

    purge_nginx "silent"
    uninstall_dnstt
    uninstall_badvpn
    uninstall_udp_custom
    uninstall_ssl_tunnel
    uninstall_falcon_proxy
    uninstall_zivpn
    delete_dns_record
    
    echo -e "\n${C_BLUE}🔄 Reloading systemd daemon...${C_RESET}"
    systemctl daemon-reload
    
    echo -e "\n${C_BLUE}🗑️ Removing script and configuration files...${C_RESET}"
    rm -rf "$BADVPN_BUILD_DIR"
    rm -rf "$UDP_CUSTOM_DIR"
    rm -rf "$DB_DIR"
    rm -f "$(command -v menu)"
    
    echo -e "\n${C_GREEN}=============================================${C_RESET}"
    echo -e "${C_GREEN}      Script has been successfully uninstalled.     ${C_RESET}"
    echo -e "${C_GREEN}=============================================${C_RESET}"
    echo -e "\nAll associated files and services have been removed."
    echo "The 'menu' command will no longer work."
    exit 0
}

# --- NEW FEATURES ---

create_trial_account() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⏱️ Create Trial/Test Account ---${C_RESET}"
    
    # Ensure 'at' daemon is available
    if ! command -v at &>/dev/null; then
        echo -e "${C_YELLOW}⚠️ 'at' command not found. Installing...${C_RESET}"
        apt-get update > /dev/null 2>&1 && apt-get install -y at || {
            echo -e "${C_RED}❌ Failed to install 'at'. Cannot schedule auto-expiry.${C_RESET}"
            return
        }
        systemctl enable atd &>/dev/null
        systemctl start atd &>/dev/null
    fi
    
    # Ensure atd is running
    if ! systemctl is-active --quiet atd; then
        systemctl start atd &>/dev/null
    fi
    
    echo -e "\n${C_CYAN}Select trial duration:${C_RESET}\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} ⏱️  1 Hour\n"
    printf "  ${C_GREEN}[ 2]${C_RESET} ⏱️  2 Hours\n"
    printf "  ${C_GREEN}[ 3]${C_RESET} ⏱️  3 Hours\n"
    printf "  ${C_GREEN}[ 4]${C_RESET} ⏱️  6 Hours\n"
    printf "  ${C_GREEN}[ 5]${C_RESET} ⏱️  12 Hours\n"
    printf "  ${C_GREEN}[ 6]${C_RESET} 📅  1 Day\n"
    printf "  ${C_GREEN}[ 7]${C_RESET} 📅  3 Days\n"
    printf "  ${C_GREEN}[ 8]${C_RESET} ⚙️  Custom (enter hours)\n"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ Cancel"
    echo
    read -p "👉 Select duration: " dur_choice
    
    local duration_hours=0
    local duration_label=""
    case $dur_choice in
        1) duration_hours=1;   duration_label="1 Hour" ;;
        2) duration_hours=2;   duration_label="2 Hours" ;;
        3) duration_hours=3;   duration_label="3 Hours" ;;
        4) duration_hours=6;   duration_label="6 Hours" ;;
        5) duration_hours=12;  duration_label="12 Hours" ;;
        6) duration_hours=24;  duration_label="1 Day" ;;
        7) duration_hours=72;  duration_label="3 Days" ;;
        8) read -p "👉 Enter custom duration in hours: " custom_hours
           if ! [[ "$custom_hours" =~ ^[0-9]+$ ]] || [[ "$custom_hours" -lt 1 ]]; then
               echo -e "\n${C_RED}❌ Invalid number of hours.${C_RESET}"; return
           fi
           duration_hours=$custom_hours
           duration_label="$custom_hours Hours"
           ;;
        0) echo -e "\n${C_YELLOW}❌ Cancelled.${C_RESET}"; return ;;
        *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"; return ;;
    esac
    
    # Username
    local rand_suffix=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 5)
    local default_username="trial_${rand_suffix}"
    read -p "👤 Username [${default_username}]: " username
    username=${username:-$default_username}
    
    if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists.${C_RESET}"; return
    fi
    
    # Password
    local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
    read -p "🔑 Password [${password}]: " custom_pass
    password=${custom_pass:-$password}
    
    # Connection limit
    read -p "📶 Connection limit [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Bandwidth limit
    read -p "📦 Bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Calculate expiry
    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        local days=$((duration_hours / 24))
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    else
        # For sub-day durations, set expiry to tomorrow to be safe (at job does the real cleanup)
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi
    local expiry_timestamp
    expiry_timestamp=$(date -d "+${duration_hours} hours" '+%Y-%m-%d %H:%M:%S')
    
    # Create the system user
    ensure_firewallfalcon_system_group
    useradd -m -s /usr/sbin/nologin "$username"
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
    
    # Schedule auto-cleanup via 'at'
    echo "$TRIAL_CLEANUP_SCRIPT $username" | at now + ${duration_hours} hours 2>/dev/null
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    
    clear; show_banner
    echo -e "${C_GREEN}✅ Trial account created successfully!${C_RESET}\n"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  ⏱️  ${C_BOLD}TRIAL ACCOUNT${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - ⏱️ Duration:          ${C_CYAN}$duration_label${C_RESET}"
    echo -e "  - 🕐 Auto-expires at:   ${C_RED}$expiry_timestamp${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth Limit:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "\n${C_DIM}The account will be automatically deleted when the trial expires.${C_RESET}"
    
    # Auto-ask for config generation
    echo
    read -p "👉 Generate client config for this trial user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

view_user_bandwidth() {
    _select_user_interface "--- 📊 View User Bandwidth ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 Bandwidth Details: ${C_YELLOW}$u${C_PURPLE} ---${C_RESET}\n"
    
    local line; line=$(grep "^$u:" "$DB_FILE")
    local bandwidth_gb; bandwidth_gb=$(echo "$line" | cut -d: -f5)
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    
    local used_bytes=0
    if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
        used_bytes=$(cat "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null)
        [[ -z "$used_bytes" ]] && used_bytes=0
    fi
    
    local used_mb; used_mb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1048576}")
    local used_gb; used_gb=$(awk "BEGIN {printf \"%.3f\", $used_bytes / 1073741824}")
    
    echo -e "  ${C_CYAN}Data Used:${C_RESET}        ${C_WHITE}${used_gb} GB${C_RESET} (${used_mb} MB)"
    
    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_GREEN}Unlimited${C_RESET}"
        echo -e "  ${C_CYAN}Status:${C_RESET}           ${C_GREEN}No quota restrictions${C_RESET}"
        # Pokaż zużycie nawet dla unlimited
        if [[ "$used_bytes" -gt 0 ]]; then
            echo -e "  ${C_CYAN}Total Used:${C_RESET}       ${C_WHITE}${used_gb} GB${C_RESET} (${used_mb} MB) — tylko informacyjnie"
        fi
    else
        local quota_bytes; quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        local percentage; percentage=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / $quota_bytes) * 100}")
        local remaining_bytes; remaining_bytes=$((quota_bytes - used_bytes))
        if [[ "$remaining_bytes" -lt 0 ]]; then remaining_bytes=0; fi
        local remaining_gb; remaining_gb=$(awk "BEGIN {printf \"%.3f\", $remaining_bytes / 1073741824}")
        
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Remaining:${C_RESET}        ${C_WHITE}${remaining_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Usage:${C_RESET}            ${C_WHITE}${percentage}%${C_RESET}"
        
        # Progress bar
        local bar_width=30
        local filled; filled=$(awk "BEGIN {printf \"%.0f\", ($percentage / 100) * $bar_width}")
        if [[ "$filled" -gt "$bar_width" ]]; then filled=$bar_width; fi
        local empty=$((bar_width - filled))
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percentage > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percentage > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        printf "  ${C_CYAN}Progress:${C_RESET}         ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percentage}%%\n"
        
        if [[ "$used_bytes" -ge "$quota_bytes" ]]; then
            echo -e "\n  ${C_RED}⚠️ USER HAS EXCEEDED BANDWIDTH QUOTA — ACCOUNT LOCKED${C_RESET}"
        fi
    fi
}

bulk_create_users() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👥 Bulk Create Users ---${C_RESET}"
    
    read -p "👉 Enter username prefix (e.g., 'user'): " prefix
    if [[ -z "$prefix" ]]; then echo -e "\n${C_RED}❌ Prefix cannot be empty.${C_RESET}"; return; fi
    
    read -p "🔢 How many users to create? " count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo -e "\n${C_RED}❌ Invalid count (1-100).${C_RESET}"; return
    fi
    
    read -p "🗓️ Account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📶 Connection limit per user [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📦 Bandwidth limit in GB per user (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    local bw_display="Unlimited"; [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb} GB"
    ensure_firewallfalcon_system_group
    
    echo -e "\n${C_BLUE}⚙️ Creating $count users with prefix '${prefix}'...${C_RESET}\n"
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-20s | %-15s | %-12s${C_RESET}\n" "USERNAME" "PASSWORD" "EXPIRES"
    echo -e "${C_YELLOW}----------------------------------------------------------------${C_RESET}"
    
    local created=0
    for ((i=1; i<=count; i++)); do
        local username="${prefix}${i}"
        if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
            echo -e "${C_RED}  ⚠️ Skipping '$username' — already exists${C_RESET}"
            continue
        fi
        local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
        useradd -m -s /usr/sbin/nologin "$username"
        usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
        echo "$username:$password" | chpasswd
        chage -E "$expire_date" "$username"
        echo "$username:$password:$expire_date:$limit:$bandwidth_gb" >> "$DB_FILE"
        printf "  ${C_GREEN}%-20s${C_RESET} | ${C_YELLOW}%-15s${C_RESET} | ${C_CYAN}%-12s${C_RESET}\n" "$username" "$password" "$expire_date"
        created=$((created + 1))
    done
    
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    echo -e "\n${C_GREEN}✅ Created $created users. Conn Limit: ${limit} | BW: ${bw_display}${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

generate_client_config() {
    local user=$1
    local pass=$2
    
    local host_ip=$(curl -s -4 icanhazip.com)
    local host_domain
    host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$host_ip"

    echo -e "\n${C_BOLD}${C_PURPLE}--- 📱 Client Connection Configuration ---${C_RESET}"
    echo -e "${C_CYAN}Copy the details below to your clipboard:${C_RESET}\n"

    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "👤 ${C_BOLD}User Details${C_RESET}"
    echo -e "   • Username: ${C_WHITE}$user${C_RESET}"
    echo -e "   • Password: ${C_WHITE}$pass${C_RESET}"
    echo -e "   • Host/IP : ${C_WHITE}$host_domain${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    
    # 1. SSH Direct
    echo -e "\n🔹 ${C_BOLD}SSH Direct${C_RESET}:"
    echo -e "   • Host: $host_domain"
    echo -e "   • Port: 22"
    echo -e "   • payload: (Standard SSH)"

    # 2. HAProxy edge stack
    if systemctl is-active --quiet haproxy; then
        echo -e "\n🔹 ${C_BOLD}HAProxy Edge Stack${C_RESET}:"
        echo -e "   • Host: $host_domain"
        echo -e "   • Port 80: HTTP payloads / raw SSH"
        echo -e "   • Port 443: TLS / SNI / SSL payloads"
        echo -e "   • Internal handoff: Nginx ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
        echo -e "   • SNI (BugHost): $host_domain (or your preferred SNI)"
    elif systemctl is-active --quiet nginx; then
        echo -e "\n🔹 ${C_BOLD}Internal Nginx Proxy${C_RESET}:"
        echo -e "   • Internal only: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
        echo -e "   • Public clients should connect through HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}"
    fi

    # 3. UDP Custom
    if systemctl is-active --quiet udp-custom; then
        echo -e "\n🔹 ${C_BOLD}UDP Custom${C_RESET}:"
        echo -e "   • IP: $host_ip (Must use numeric IP)"
        echo -e "   • Port: 1-65535 (Exclude 53, 5300)"
        echo -e "   • Obfs: (None/Plain)"
    fi

    # 4. DNSTT
    if systemctl is-active --quiet dnstt; then
        if [ -f "$DNSTT_CONFIG_FILE" ]; then
            source "$DNSTT_CONFIG_FILE"
            echo -e "\n🔹 ${C_BOLD}DNSTT (SlowDNS)${C_RESET}:"
            echo -e "   • Nameserver: $TUNNEL_DOMAIN"
            echo -e "   • PubKey: $PUBLIC_KEY"
            echo -e "   • DNS IP: 1.1.1.1 / 8.8.8.8"
        fi
    fi
    
    # 5. ZiVPN
    if systemctl is-active --quiet zivpn; then
        echo -e "\n🔹 ${C_BOLD}ZiVPN${C_RESET}:"
        echo -e "   • UDP Port: 5667"
        echo -e "   • Forwarded Ports: 6000-19999"
    fi
    
    echo -e "${C_YELLOW}========================================${C_RESET}"
    press_enter
}

client_config_menu() {
    _select_user_interface "--- 📱 Generate Client Config ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    # We need to find the password. It's in the DB.
    local pass=$(grep "^$u:" "$DB_FILE" | cut -d: -f2)
    generate_client_config "$u" "$pass"
}

format_rate_from_kbps() {
    local kbps=${1:-0}
    if (( kbps >= 1024 )); then
        printf "%d.%02d MB/s" $((kbps / 1024)) $((((kbps % 1024) * 100) / 1024))
    else
        printf "%d KB/s" "$kbps"
    fi
}

# Lightweight Bash Monitor (No vnStat required)
simple_live_monitor() {
    local iface=$1
    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"
    local interval=2
    local stop_monitor=0
    local rx1 tx1 rx2 tx2 rx_diff tx_diff rx_kbs tx_kbs rx_fmt tx_fmt

    if [[ -z "$iface" || ! -r "$rx_file" || ! -r "$tx_file" ]]; then
        echo -e "\n${C_RED}❌ Could not read interface statistics for '${iface:-unknown}'.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}⚡ Starting Lightweight Traffic Monitor for $iface...${C_RESET}"
    echo -e "${C_DIM}Press [Ctrl+C] to stop.${C_RESET}\n"

    read -r rx1 < "$rx_file"
    read -r tx1 < "$tx_file"

    printf "%-15s | %-15s\n" "⬇️ Download" "⬆️ Upload"
    echo "-----------------------------------"

    trap 'stop_monitor=1' INT TERM
    while (( ! stop_monitor )); do
        sleep "$interval"
        read -r rx2 < "$rx_file" || break
        read -r tx2 < "$tx_file" || break

        rx_diff=$((rx2 - rx1))
        tx_diff=$((tx2 - tx1))
        (( rx_diff < 0 )) && rx_diff=0
        (( tx_diff < 0 )) && tx_diff=0

        rx_kbs=$((rx_diff / 1024 / interval))
        tx_kbs=$((tx_diff / 1024 / interval))
        rx_fmt=$(format_rate_from_kbps "$rx_kbs")
        tx_fmt=$(format_rate_from_kbps "$tx_kbs")

        printf "\r%-15s | %-15s" "$rx_fmt" "$tx_fmt"

        rx1=$rx2
        tx1=$tx2
    done
    trap - INT TERM
    echo
}

traffic_monitor_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📈 Network Traffic Monitor ---${C_RESET}"
    
    # Find active interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    echo -e "\nInterface: ${C_CYAN}${iface}${C_RESET}"
    
    echo -e "\n${C_BOLD}Select a monitoring option:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "⚡ Live Monitor ${C_DIM}(Lightweight, No Install)${C_RESET}"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📊 View Total Traffic Since Boot"
    printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "📅 Daily/Monthly Logs ${C_DIM}(Requires vnStat)${C_RESET}"
    
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " t_choice
    case $t_choice in
        1) 
           simple_live_monitor "$iface"
           ;;
        2)
            local rx_total=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            local tx_total=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            local rx_mb=$((rx_total / 1024 / 1024))
            local tx_mb=$((tx_total / 1024 / 1024))
            echo -e "\n${C_BLUE}📊 Total Traffic (Since Boot):${C_RESET}"
            echo -e "   ⬇️ Download: ${C_WHITE}${rx_mb} MB${C_RESET}"
            echo -e "   ⬆️ Upload:   ${C_WHITE}${tx_mb} MB${C_RESET}"
            press_enter
            ;;
        3) 
           # vnStat Logic
           if ! command -v vnstat &> /dev/null; then
               echo -e "\n${C_YELLOW}⚠️ vnStat is not installed.${C_RESET}"
               echo -e "   This tool provides persistent history (Daily/Monthly reports)."
               echo -e "   It is lightweight but requires installation."
               read -p "👉 Install vnStat now? (y/n): " confirm
               if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo -e "\n${C_BLUE}📦 Installing vnStat...${C_RESET}"
                    apt-get update >/dev/null 2>&1
                    apt-get install -y vnstat >/dev/null 2>&1
                    systemctl enable vnstat >/dev/null 2>&1
                    systemctl restart vnstat >/dev/null 2>&1
                    local default_iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
                    vnstat --add -i "$default_iface" >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ Installed.${C_RESET}"
                    sleep 1
               else
                    return
               fi
           fi
           echo
           vnstat -i "$iface"
           echo -e "\n${C_DIM}Run 'vnstat -d' or 'vnstat -m' manually for specific views.${C_RESET}"
           press_enter
           ;;
        *) return ;;
    esac
}

torrent_block_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🚫 Blokowanie Torrentów ---${C_RESET}\n"

        # Sprawdź status
        local port_status="${C_STATUS_I}Wyłączone${C_RESET}"
        local dns_status="${C_STATUS_I}Wyłączone${C_RESET}"

        if iptables -L OUTPUT -n 2>/dev/null | grep -q "6881:6999"; then
            port_status="${C_STATUS_A}Aktywne${C_RESET}"
        fi
        if [[ -f /etc/torrent_block_domains ]]; then
            dns_status="${C_STATUS_A}Aktywne${C_RESET}"
        fi

        echo -e "  ${C_BOLD}${C_WHITE}Metoda 1 — Blokowanie portów P2P${C_RESET}  ${port_status}"
        echo -e "  ${C_DIM}Blokuje porty 6881-6999 TCP/UDP (domyślne porty BitTorrent)${C_RESET}"
        echo -e "  ${C_DIM}Skuteczne dla standardowych klientów, nie wymaga inspekcji pakietów${C_RESET}\n"

        echo -e "  ${C_BOLD}${C_WHITE}Metoda 2 — Blokowanie DNS trackerów${C_RESET}  ${dns_status}"
        echo -e "  ${C_DIM}Blokuje ~200 znanych domen trackerów przez /etc/hosts${C_RESET}"
        echo -e "  ${C_DIM}Skuteczne dla klientów używających DNS (qBittorrent, uTorrent)${C_RESET}\n"

        local div="${C_BLUE}  ──────────────────────────────────────${C_RESET}"
        echo -e "$div"
        printf "  ${C_CHOICE}[1]${C_RESET} %-40s\n" "🔒 Włącz blokowanie portów P2P"
        printf "  ${C_CHOICE}[2]${C_RESET} %-40s\n" "🔓 Wyłącz blokowanie portów P2P"
        printf "  ${C_CHOICE}[3]${C_RESET} %-40s\n" "🔒 Włącz blokowanie DNS trackerów"
        printf "  ${C_CHOICE}[4]${C_RESET} %-40s\n" "🔓 Wyłącz blokowanie DNS trackerów"
        printf "  ${C_CHOICE}[5]${C_RESET} %-40s\n" "🔒 Włącz OBA (zalecane)"
        printf "  ${C_CHOICE}[6]${C_RESET} %-40s\n" "🔓 Wyłącz wszystko"
        echo -e "\n  ${C_WARN}[0]${C_RESET} ↩️ Powrót\n"
        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" b_choice

        case $b_choice in
            1|5)
                echo -e "\n${C_BLUE}🛡️ Włączanie blokowania portów P2P...${C_RESET}"
                _flush_torrent_rules
                # Blokuj porty BitTorrent 6881-6999 TCP i UDP
                iptables -A OUTPUT -p tcp --dport 6881:6999 -j DROP
                iptables -A OUTPUT -p udp --dport 6881:6999 -j DROP
                iptables -A FORWARD -p tcp --dport 6881:6999 -j DROP
                iptables -A FORWARD -p udp --dport 6881:6999 -j DROP
                # Blokuj też popularne alternatywne porty
                iptables -A OUTPUT -p tcp --dport 51413 -j DROP  # qBittorrent
                iptables -A OUTPUT -p udp --dport 51413 -j DROP
                iptables -A FORWARD -p tcp --dport 51413 -j DROP
                iptables -A FORWARD -p udp --dport 51413 -j DROP
                echo -e "${C_GREEN}✅ Porty P2P zablokowane (6881-6999, 51413)${C_RESET}"
                ;;&
            3|5)
                echo -e "\n${C_BLUE}🛡️ Włączanie blokowania DNS trackerów...${C_RESET}"
                _apply_torrent_dns_block
                echo -e "${C_GREEN}✅ Blokowanie DNS trackerów aktywne${C_RESET}"
                ;;&
            1|3|5)
                _save_torrent_rules
                press_enter
                ;;
            2|6)
                echo -e "\n${C_BLUE}🔓 Usuwanie blokowania portów P2P...${C_RESET}"
                _flush_torrent_rules
                _save_torrent_rules
                echo -e "${C_GREEN}✅ Blokowanie portów wyłączone${C_RESET}"
                ;;&
            4|6)
                echo -e "\n${C_BLUE}🔓 Usuwanie blokowania DNS...${C_RESET}"
                _flush_torrent_dns_block
                echo -e "${C_GREEN}✅ Blokowanie DNS wyłączone${C_RESET}"
                ;;&
            2|4|6)
                press_enter
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

_flush_torrent_rules() {
    # Usuń reguły portów P2P
    iptables -D OUTPUT -p tcp --dport 6881:6999 -j DROP 2>/dev/null
    iptables -D OUTPUT -p udp --dport 6881:6999 -j DROP 2>/dev/null
    iptables -D FORWARD -p tcp --dport 6881:6999 -j DROP 2>/dev/null
    iptables -D FORWARD -p udp --dport 6881:6999 -j DROP 2>/dev/null
    iptables -D OUTPUT -p tcp --dport 51413 -j DROP 2>/dev/null
    iptables -D OUTPUT -p udp --dport 51413 -j DROP 2>/dev/null
    iptables -D FORWARD -p tcp --dport 51413 -j DROP 2>/dev/null
    iptables -D FORWARD -p udp --dport 51413 -j DROP 2>/dev/null
    # Usuń też stare reguły string matching
    iptables -D FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "torrent" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "info_hash" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "get_peers" --algo bm -j DROP 2>/dev/null
    iptables -D OUTPUT -m string --string "find_node" --algo bm -j DROP 2>/dev/null
}

_save_torrent_rules() {
    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        if ! command -v iptables-persistent &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1
        fi
    fi
    if dpkg -s iptables-persistent &>/dev/null 2>/dev/null; then
        netfilter-persistent save &>/dev/null
    fi
}

_apply_torrent_dns_block() {
    local hosts_file="/etc/hosts"
    local marker="# FirewallFalcon torrent block"
    local domain_file="/etc/torrent_block_domains"

    # Lista znanych domen trackerów
    cat > "$domain_file" << 'DOMAINS'
tracker.openbittorrent.com
tracker.opentrackr.org
tracker.leechers-paradise.org
tracker.coppersurfer.tk
tracker.internetwarriors.net
tracker.pirateparty.gr
tracker.torrent.eu.org
tracker.tiny-vps.com
open.stealth.si
open.tracker.cl
tracker.gbitt.info
tracker.nitrix.me
tracker2.dler.org
tracker.dler.org
tracker.lelux.fi
tracker.army
tracker.bt4g.com
tracker.moeking.me
tracker.servark.net
retracker.lanta-net.ru
tracker.iamhansen.xyz
tracker.shkinev.me
tracker.ipv6tracker.ru
tracker.anonseed.com
tracker.birkenwald.de
tracker.decentralize.it
opentracker.i2p.rocks
tracker.zerobytes.xyz
exodus.desync.com
tracker.uw0.xyz
tracker.obytes.xyz
DOMAINS

    # Usuń stare wpisy
    sed -i "/$marker/d" "$hosts_file" 2>/dev/null

    # Dodaj nowe wpisy
    while IFS= read -r domain; do
        [[ -z "$domain" || "$domain" == \#* ]] && continue
        echo "0.0.0.0 $domain $marker" >> "$hosts_file"
    done < "$domain_file"
}

_flush_torrent_dns_block() {
    local marker="# FirewallFalcon torrent block"
    sed -i "/$marker/d" /etc/hosts 2>/dev/null
    rm -f /etc/torrent_block_domains
}

ssh_banner_menu() {
    while true; do
        show_banner
        local banner_mode
        local banner_status
        banner_mode=$(get_ssh_banner_mode)
        case "$banner_mode" in
            dynamic) banner_status="${C_STATUS_A}Dynamic${C_RESET}" ;;
            static) banner_status="${C_STATUS_A}Static${C_RESET}" ;;
            *) banner_status="${C_STATUS_I}Disabled${C_RESET}" ;;
        esac

        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}🎨 SSH BANNER MODE: ${banner_status} ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        echo -e "${C_DIM}Static mode uses 'Banner $SSH_BANNER_FILE'. Dynamic mode shows per-user account info.${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✨ Enable Dynamic Account Banner"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📋 Paste or Replace Static Banner"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "👁️ View Current Static Banner"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "📝 Preview Dynamic Banner"
        printf "     ${C_DANGER}[ 5]${C_RESET} %-40s\n" "🗑️ Disable All SSH Banners"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return to Main Menu"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                if setup_ssh_login_info; then
                    echo -e "\n${C_GREEN}✅ Dynamic account banner enabled.${C_RESET}"
                    echo -e "${C_DIM}Users will now see their account info banner instead of the static banner.${C_RESET}"
                fi
                press_enter
                ;;
            2) set_ssh_banner_paste ;;
            3) view_ssh_banner ;;
            4) preview_dynamic_ssh_banner ;;
            5) remove_ssh_banner ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

auto_reboot_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Auto-Reboot Management ---${C_RESET}"
    
    # Check status
    local cron_check=$(crontab -l 2>/dev/null | grep "systemctl reboot")
    local status="${C_STATUS_I}Disabled${C_RESET}"
    if [[ -n "$cron_check" ]]; then
        status="${C_STATUS_A}Active (Midnight)${C_RESET}"
    fi
    
    echo -e "\n${C_WHITE}Current Status: ${status}${C_RESET}"
    
    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🕐 Enable Daily Reboot (00:00 midnight)"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "❌ Disable Auto-Reboot"
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " r_choice
    
    case $r_choice in
        1)
            # Remove existing to prevent duplicates
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            # Add new job
            (crontab -l 2>/dev/null; echo "0 0 * * * systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot scheduled for every day at 00:00.${C_RESET}"
            press_enter
            ;;
        2)
            (crontab -l 2>/dev/null | grep -v "systemctl reboot") | crontab -
            echo -e "\n${C_GREEN}✅ Auto-reboot disabled.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}


press_enter() {
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return to the menu..." && read -r || true
}
invalid_option() {
    echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1
}

list_all_accounts() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ Brak użytkowników w bazie danych.${C_RESET}"
        return
    fi

    local current_ts
    current_ts=$(date +%s)

    # Build sortable rows: sort_key|user|pass|expiry_display|days_display
    local -a rows=()
    while IFS=: read -r user pass expiry limit _rest; do
        [[ -z "$user" || "$user" == \#* ]] && continue

        local expiry_display days_display sort_key

        if [[ -z "$expiry" || "$expiry" == "Never" ]]; then
            expiry_display="Never"
            days_display="∞"
            sort_key="9999999"
        else
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            expiry_display=$(date -d "$expiry" +"%d-%m-%Y" 2>/dev/null || echo "$expiry")

            if [[ "$expiry_ts" -le 0 ]]; then
                days_display="N/D"
                sort_key="9999998"
            elif (( expiry_ts < current_ts )); then
                local diff_past=$(( (current_ts - expiry_ts) / 86400 ))
                days_display="-${diff_past}d WYGAS."
                # Wygasłe na samym dole - klucz większy niż "Never" (9999999)
                sort_key="$(printf '%010d' 9999990)"
            else
                local diff_secs=$(( expiry_ts - current_ts ))
                local days_left=$(( diff_secs / 86400 ))
                days_display="${days_left} dni"
                sort_key="$(printf '%010d' "$days_left")"
            fi
        fi

        # Truncate long passwords to 18 chars to keep layout tight
        local pass_display="$pass"
        if (( ${#pass} > 18 )); then
            pass_display="${pass:0:15}..."
        fi

        rows+=("${sort_key}|${user}|${pass_display}|${expiry_display}|${days_display}")
    done < "$DB_FILE"

    local total="${#rows[@]}"
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

    echo -e "  ${C_BOLD}${C_WHITE}🗂️  LISTA KONT${C_RESET}  ${C_DIM}(od najkrótszego do najdłuższego)${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-14s  %-18s  %-12s  %s${C_RESET}\n" "UŻYTKOWNIK" "HASŁO" "WYGASA" "DNI"
    echo -e "$div"

    while IFS='|' read -r _sortkey user pass_display expiry_display days_display; do
        local rc="$C_WHITE"
        if [[ "$days_display" == *"WYGAS."* ]]; then
            rc="$C_RED"
        elif [[ "$days_display" =~ ^([0-9]+)\ dni$ ]]; then
            (( BASH_REMATCH[1] <= 7 )) && rc="$C_YELLOW"
        elif [[ "$days_display" == "∞" ]]; then
            rc="$C_CYAN"
        fi
        printf "  ${rc}%-14s${C_RESET}  ${C_WHITE}%-18s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${rc}%s${C_RESET}\n" \
            "$user" "$pass_display" "$expiry_display" "$days_display"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n)

    echo -e "$div"
    echo -e "  ${C_DIM}Razem: ${total} kont  •  ${C_RED}Czerwony${C_RESET}${C_DIM}=wygasłe  ${C_YELLOW}Żółty${C_RESET}${C_DIM}=≤7 dni  ${C_CYAN}Cyjan${C_RESET}${C_DIM}=bez limitu${C_RESET}\n"
}

BAN_LOG="/etc/firewallfalcon/ban_history.log"

show_ban_history() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚫 HISTORIA BANÓW (przekroczenie sesji) ---${C_RESET}\n"

    if [[ ! -f "$BAN_LOG" || ! -s "$BAN_LOG" ]]; then
        echo -e "${C_YELLOW}ℹ️ Brak zapisanych banów.${C_RESET}"
        echo -e "${C_DIM}Bany są rejestrowane automatycznie gdy konto przekroczy limit połączeń.${C_RESET}\n"
        return
    fi

    local div="${C_BLUE}  ────────────────────────────────────────────────────────${C_RESET}"

    # Count bans per user and find last ban date
    declare -A ban_count=()
    declare -A ban_last=()
    declare -A ban_last_sessions=()

    while IFS=$'\t' read -r ts user sessions _rest; do
        [[ -z "$user" ]] && continue
        ban_count["$user"]=$(( ${ban_count["$user"]:-0} + 1 ))
        ban_last["$user"]="$ts"
        ban_last_sessions["$user"]="$sessions"
    done < "$BAN_LOG"

    local total_bans=0
    for u in "${!ban_count[@]}"; do
        total_bans=$(( total_bans + ban_count["$u"] ))
    done

    echo -e "  ${C_BOLD}${C_WHITE}🚫 BANY — LISTA UŻYTKOWNIKÓW${C_RESET}  ${C_DIM}(łącznie: ${total_bans} banów)${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-16s  %-6s  %-20s  %s${C_RESET}\n" "UŻYTKOWNIK" "ILE" "OSTATNI BAN" "SESJE"
    echo -e "$div"

    # Sort by ban count descending
    for user in $(for k in "${!ban_count[@]}"; do echo "${ban_count[$k]} $k"; done | sort -rn | awk '{print $2}'); do
        local cnt="${ban_count[$user]}"
        local last_ts="${ban_last[$user]}"
        local last_sess="${ban_last_sessions[$user]:-?}"
        local uc="$C_YELLOW"
        (( cnt >= 10 )) && uc="$C_RED"
        printf "  ${uc}%-16s${C_RESET}  ${C_RED}%-6s${C_RESET}  ${C_WHITE}%-20s${C_RESET}  ${C_CYAN}%s${C_RESET}\n" \
            "$user" "$cnt" "$last_ts" "$last_sess"
    done

    echo -e "$div"
    echo -e "  ${C_DIM}Plik logu: $BAN_LOG${C_RESET}\n"

    echo -e "  ${C_CHOICE}[ 1]${C_RESET} 📋 Pokaż szczegółowy dziennik banów"
    echo -e "  ${C_CHOICE}[ 2]${C_RESET} 🗑️  Wyczyść historię banów"
    echo -e "  ${C_WARN}[ 0]${C_RESET} ↩️  Powrót\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz opcję: ${C_RESET}")" bch

    case "$bch" in
        1)
            clear; show_banner
            echo -e "${C_BOLD}${C_PURPLE}--- 📋 SZCZEGÓŁOWY DZIENNIK BANÓW ---${C_RESET}\n"
            local line_div="${C_BLUE}  ────────────────────────────────────────────────────────${C_RESET}"
            echo -e "$line_div"
            # Show last 200 lines newest first with full details
            tail -n 200 "$BAN_LOG" | tac | while IFS=$'\t' read -r ts user sessions pids scans; do
                [[ -z "$user" ]] && continue
                echo -e "$line_div"
                echo -e "  ${C_YELLOW}${user}${C_RESET}  ${C_RED}${sessions} sesji${C_RESET}  ${C_DIM}${ts}${C_RESET}"
                if [[ -n "$pids" ]]; then
                    echo -e "  ${C_DIM}PIDs: ${pids}${C_RESET}"
                    echo -e "  ${C_DIM}Licznik skanów: ${scans}${C_RESET}"
                fi
            done
            echo -e "$line_div\n"
            press_enter
            ;;
        2)
            read -r -p "$(echo -e "${C_WARN}  ⚠️  Na pewno wyczyścić całą historię banów? (t/n): ${C_RESET}")" confirm
            if [[ "$confirm" == "t" || "$confirm" == "T" || "$confirm" == "y" || "$confirm" == "Y" ]]; then
                > "$BAN_LOG"
                echo -e "\n${C_GREEN}✅ Historia banów wyczyszczona.${C_RESET}"
            else
                echo -e "\n${C_YELLOW}❌ Anulowano.${C_RESET}"
            fi
            press_enter
            ;;
        *) return ;;
    esac
}

show_data_usage() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 📈 ZUŻYCIE DANYCH ---${C_RESET}\n"

        if [[ ! -s "$DB_FILE" ]]; then
            echo -e "${C_YELLOW}ℹ️ Brak użytkowników.${C_RESET}"
            press_enter; return
        fi

        local today; today=$(date +%Y-%m-%d)
        local month; month=$(date +%Y-%m)
        local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

        echo -e "  ${C_CHOICE}[1]${C_RESET} 📅 Dzienne   ${C_CHOICE}[2]${C_RESET} 📆 Miesięczne   ${C_CHOICE}[3]${C_RESET} 📊 Ogólne   ${C_CHOICE}[4]${C_RESET} 📋 Wszystkie"
        echo -e "  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"
        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz widok: ${C_RESET}")" view_choice

        case "$view_choice" in
            0) return ;;
            1|2|3|4) ;;
            *) continue ;;
        esac

        # Zbierz dane
        declare -A d_bytes=()
        declare -A m_bytes=()
        declare -A t_bytes=()
        local -a all_users=()

        while IFS=: read -r _u _rest; do
            [[ -z "$_u" || "$_u" == \#* ]] && continue
            all_users+=("$_u")
            d_bytes["$_u"]=0
            m_bytes["$_u"]=0
            t_bytes["$_u"]=0

            local _line _sd _sb _sm _smb _tb
            if [[ -f "$STATS_DIR/${_u}.daily" ]]; then
                _line=$(cat "$STATS_DIR/${_u}.daily" 2>/dev/null)
                _sd="${_line%% *}"
                _sb="${_line##* }"
                [[ "$_sd" == "$today" && "$_sb" =~ ^[0-9]+$ ]] && d_bytes["$_u"]=$_sb
            fi
            if [[ -f "$STATS_DIR/${_u}.monthly" ]]; then
                _line=$(cat "$STATS_DIR/${_u}.monthly" 2>/dev/null)
                _sm="${_line%% *}"
                _smb="${_line##* }"
                [[ "$_sm" == "$month" && "$_smb" =~ ^[0-9]+$ ]] && m_bytes["$_u"]=$_smb
            fi
            if [[ -f "$BANDWIDTH_DIR/${_u}.usage" ]]; then
                _tb=$(cat "$BANDWIDTH_DIR/${_u}.usage" 2>/dev/null)
                [[ "$_tb" =~ ^[0-9]+$ ]] && t_bytes["$_u"]=$_tb
            fi
        done < "$DB_FILE"

        # Format bajtów
        _fmt() {
            local b="${1:-0}"
            [[ "$b" =~ ^[0-9]+$ ]] || b=0
            if (( b >= 1073741824 )); then
                awk -v x="$b" 'BEGIN {printf "%.2f GB", x/1073741824}'
            elif (( b >= 1048576 )); then
                awk -v x="$b" 'BEGIN {printf "%.1f MB", x/1048576}'
            elif (( b >= 1024 )); then
                awk -v x="$b" 'BEGIN {printf "%.0f KB", x/1024}'
            else
                echo "${b} B"
            fi
        }

        # Kolor
        _col() {
            local b="${1:-0}" r="$2" y="$3"
            (( b >= r )) && echo "$C_RED" && return
            (( b >= y )) && echo "$C_YELLOW" && return
            echo "$C_WHITE"
        }

        # Sortuj użytkowników po bajach malejąco, zwróć tablicę "user:bajty"
        _sort_users() {
            local period="$1"
            local -a tmp=()
            for _u in "${all_users[@]}"; do
                local b=0
                case "$period" in
                    daily)   b=${d_bytes[$_u]:-0} ;;
                    monthly) b=${m_bytes[$_u]:-0} ;;
                    total)   b=${t_bytes[$_u]:-0} ;;
                esac
                tmp+=("$(printf '%020d' $b):${_u}:${b}")
            done
            # Sortuj i wypisz "user:bajty" bez klucza sortowania
            printf '%s\n' "${tmp[@]}" | sort -rn | while IFS=: read -r _ _u _b; do
                echo "${_u}:${_b}"
            done
        }

        # Wyświetl jedną tabelę z paginacją (2 kolumny)
        _show_table() {
            local title="$1" period="$2"
            local tr tm
            case "$period" in
                daily)   tr=1073741824;   tm=104857600 ;;
                monthly) tr=10737418240;  tm=1073741824 ;;
                total)   tr=107374182400; tm=10737418240 ;;
            esac

            # Wczytaj posortowane dane do tablicy
            local -a sorted_data=()
            while IFS= read -r line; do
                sorted_data+=("$line")
            done < <(_sort_users "$period")

            local total_rows=${#sorted_data[@]}
            local cols=2
            local rows_per_page=20
            local items_per_page=$(( rows_per_page * cols ))
            local total_pages=$(( (total_rows + items_per_page - 1) / items_per_page ))
            (( total_pages < 1 )) && total_pages=1
            local page=0

            while true; do
                clear; show_banner
                echo -e "${C_BOLD}${C_PURPLE}--- 📈 $title ---${C_RESET}"
                echo -e "${C_DIM}  Strona $((page+1))/$total_pages  •  $total_rows użytkowników${C_RESET}\n"
                echo -e "$div"
                printf "  ${C_BOLD}${C_WHITE}%-3s %-14s %-12s  %-3s %-14s %-12s${C_RESET}\n" \
                    "#" "UŻYTKOWNIK" "ZUŻYCIE" "#" "UŻYTKOWNIK" "ZUŻYCIE"
                echo -e "$div"

                local si=$(( page * items_per_page ))
                local ei=$(( si + items_per_page ))
                (( ei > total_rows )) && ei=$total_rows
                local rank=$(( si + 1 ))

                # Wyświetl po 2 w rzędzie
                local i=$si
                while (( i < ei )); do
                    # Lewa kolumna
                    local lu="" lb=0 lf="" lc=""
                    if (( i < total_rows )); then
                        IFS=: read -r lu lb <<< "${sorted_data[$i]}"
                        lf=$(_fmt "$lb")
                        lc=$(_col "$lb" "$tr" "$tm")
                    fi

                    # Prawa kolumna
                    local ru="" rb=0 rf="" rc=""
                    (( i+1 < total_rows )) && {
                        IFS=: read -r ru rb <<< "${sorted_data[$((i+1))]}"
                        rf=$(_fmt "$rb")
                        rc=$(_col "$rb" "$tr" "$tm")
                    }

                    if [[ -n "$ru" ]]; then
                        printf "  ${C_DIM}%-3s${C_RESET} ${lc}%-14s${C_RESET} ${C_CYAN}%-12s${C_RESET}  ${C_DIM}%-3s${C_RESET} ${rc}%-14s${C_RESET} ${C_CYAN}%s${C_RESET}\n" \
                            "${rank}." "$lu" "$lf" "$((rank+1))." "$ru" "$rf"
                    else
                        printf "  ${C_DIM}%-3s${C_RESET} ${lc}%-14s${C_RESET} ${C_CYAN}%s${C_RESET}\n" \
                            "${rank}." "$lu" "$lf"
                    fi

                    (( i += 2 ))
                    (( rank += 2 ))
                done

                echo -e "$div"
                echo -e "  ${C_DIM}Czerwony=duże  Żółty=średnie  Biały=małe${C_RESET}\n"

                if (( total_pages > 1 )); then
                    echo -e "  ${C_CHOICE}[n]${C_RESET} Następna   ${C_CHOICE}[p]${C_RESET} Poprzednia   ${C_WARN}[0]${C_RESET} Powrót"
                else
                    echo -e "  ${C_WARN}[0]${C_RESET} Powrót"
                fi

                read -r -p "$(echo -e "${C_PROMPT}  👉 : ${C_RESET}")" nav
                case "$nav" in
                    n|N) (( page < total_pages-1 )) && (( page++ )) ;;
                    p|P) (( page > 0 )) && (( page-- )) ;;
                    0|"") break ;;
                esac
            done
        }

        case "$view_choice" in
            1) _show_table "DZIENNE — dziś: $today" "daily" ;;
            2) _show_table "MIESIĘCZNE — $month" "monthly" ;;
            3) _show_table "OGÓLNE — od początku" "total" ;;
            4)
                clear; show_banner
                echo -e "${C_BOLD}${C_PURPLE}--- 📈 ZUŻYCIE DANYCH — TOP 10 ---${C_RESET}\n"

                local -a _periods=("daily" "monthly" "total")
                local -a _ptitles=("📅 DZIENNE (dziś: $today)" "📆 MIESIĘCZNE ($month)" "📊 OGÓLNE (od początku)")
                local -a _ptr=(1073741824 10737418240 107374182400)
                local -a _ptm=(104857600 1073741824 10737418240)

                for _pi in 0 1 2; do
                    local _period="${_periods[$_pi]}"
                    local _ptitle="${_ptitles[$_pi]}"
                    local _tr="${_ptr[$_pi]}"
                    local _tm="${_ptm[$_pi]}"

                    local -a sdata=()
                    while IFS= read -r line; do sdata+=("$line"); done < <(_sort_users "$_period")

                    echo -e "  ${C_BOLD}${C_WHITE}${_ptitle}${C_RESET}"
                    printf "  ${C_BOLD}%-3s %-14s %-12s  %-3s %-14s %-12s${C_RESET}\n" \
                        "#" "UŻYTKOWNIK" "ZUŻYCIE" "#" "UŻYTKOWNIK" "ZUŻYCIE"
                    echo -e "${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"

                    local _max=$(( ${#sdata[@]} < 10 ? ${#sdata[@]} : 10 ))
                    local _i=0 _rank=1
                    while (( _i < _max )); do
                        local _lu _lb=0 _lf _lc
                        IFS=: read -r _lu _lb <<< "${sdata[$_i]}"
                        _lf=$(_fmt "$_lb"); _lc=$(_col "$_lb" "$_tr" "$_tm")

                        local _ru="" _rb=0 _rf="" _rc=""
                        if (( _i+1 < _max )); then
                            IFS=: read -r _ru _rb <<< "${sdata[$((_i+1))]}"
                            _rf=$(_fmt "$_rb"); _rc=$(_col "$_rb" "$_tr" "$_tm")
                        fi

                        if [[ -n "$_ru" ]]; then
                            printf "  ${C_DIM}%-3s${C_RESET} ${_lc}%-14s${C_RESET} ${C_CYAN}%-12s${C_RESET}  ${C_DIM}%-3s${C_RESET} ${_rc}%-14s${C_RESET} ${C_CYAN}%s${C_RESET}\n" \
                                "${_rank}." "$_lu" "$_lf" "$((_rank+1))." "$_ru" "$_rf"
                        else
                            printf "  ${C_DIM}%-3s${C_RESET} ${_lc}%-14s${C_RESET} ${C_CYAN}%s${C_RESET}\n" "${_rank}." "$_lu" "$_lf"
                        fi
                        (( _i+=2, _rank+=2 ))
                    done
                    echo
                done
                press_enter
                ;;
        esac

        unset d_bytes m_bytes t_bytes
    done
}


show_service_status() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🔍 STATUS SERWISÓW ---${C_RESET}
"

        local div="${C_BLUE}  ──────────────────────────────────────────────${C_RESET}"

        # Funkcja pomocnicza: status serwisu
        _svc_status() {
            local name="$1" label="$2" extra="$3"
            if systemctl is-active --quiet "$name" 2>/dev/null; then
                printf "  ${C_GREEN}●${C_RESET} %-20s ${C_GREEN}AKTYWNY${C_RESET}  %s
" "$label" "$extra"
            elif systemctl list-unit-files --quiet "$name" 2>/dev/null | grep -q "$name"; then
                printf "  ${C_RED}●${C_RESET} %-20s ${C_RED}NIEAKTYWNY${C_RESET}  %s
" "$label" "$extra"
            else
                printf "  ${C_DIM}●${C_RESET} %-20s ${C_DIM}NIE ZAINSTALOWANY${C_RESET}
" "$label"
            fi
        }

        # Funkcja: sprawdź port TCP
        _port_open() {
            local port="$1"
            if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                echo -e "${C_GREEN}:${port}${C_RESET}"
            else
                echo -e "${C_DIM}:${port}${C_RESET}"
            fi
        }

        echo -e "  ${C_BOLD}${C_WHITE}🌐 SERWISY SIECIOWE${C_RESET}"
        echo -e "$div"

        # SSH
        local ssh_port
        ssh_port=$(ss -tlnp 2>/dev/null | awk '/sshd/{match($4,/:([0-9]+)$/,a); if(a[1]) print a[1]}' | head -1)
        _svc_status "ssh" "SSH" "${C_DIM}port: ${ssh_port:-22}${C_RESET}"

        # HAProxy
        local haproxy_ports=""
        if systemctl is-active --quiet haproxy 2>/dev/null; then
            haproxy_ports=$(ss -tlnp 2>/dev/null | awk '/haproxy/{match($4,/:([0-9]+)$/,a); if(a[1]) printf a[1]" "}')
            haproxy_ports="${C_DIM}porty: ${haproxy_ports}${C_RESET}"
        fi
        _svc_status "haproxy" "HAProxy" "$haproxy_ports"

        # Nginx
        local nginx_ports=""
        if systemctl is-active --quiet nginx 2>/dev/null; then
            nginx_ports=$(ss -tlnp 2>/dev/null | awk '/nginx/{match($4,/:([0-9]+)$/,a); if(a[1]) printf a[1]" "}')
            nginx_ports="${C_DIM}porty: ${nginx_ports}${C_RESET}"
        fi
        _svc_status "nginx" "Nginx" "$nginx_ports"

        # FalconProxy
        local fp_extra=""
        if systemctl is-active --quiet falconproxy 2>/dev/null; then
            if [[ -f "$FALCONPROXY_CONFIG_FILE" ]]; then
                source "$FALCONPROXY_CONFIG_FILE" 2>/dev/null
                fp_extra="${C_DIM}port: ${PORTS} ver: ${INSTALLED_VERSION:-?}${C_RESET}"
            fi
        fi
        _svc_status "falconproxy" "FalconProxy" "$fp_extra"

        # UDP-Custom
        local udp_extra=""
        if systemctl is-active --quiet udp-custom 2>/dev/null; then
            local udp_port
            udp_port=$(ss -ulnp 2>/dev/null | awk '/udp/{match($4,/:([0-9]+)$/,a); if(a[1] && a[1]!="53") print a[1]}' | head -1)
            udp_extra="${C_DIM}port UDP: ${udp_port:-?}${C_RESET}"
        fi
        _svc_status "udp-custom" "UDP-Custom" "$udp_extra"

        # BadVPN
        _svc_status "badvpn" "BadVPN" "${C_DIM}UDP 7300${C_RESET}"

        # ZiVPN
        _svc_status "zivpn" "ZiVPN" "${C_DIM}UDP 5667${C_RESET}"

        # DNSTT
        _svc_status "dnstt" "DNSTT" "${C_DIM}port 53${C_RESET}"

        # WARP
        if ip link show wgcf &>/dev/null 2>/dev/null || systemctl is-active --quiet wg-quick@wgcf 2>/dev/null; then
            printf "  ${C_GREEN}●${C_RESET} %-20s ${C_GREEN}AKTYWNY${C_RESET}
" "Cloudflare WARP"
        else
            printf "  ${C_DIM}●${C_RESET} %-20s ${C_DIM}NIE ZAINSTALOWANY${C_RESET}
" "Cloudflare WARP"
        fi

        # FirewallFalcon limiter
        _svc_status "firewallfalcon-limiter" "FF Limiter" ""

        echo -e "
$div"
        echo -e "  ${C_BOLD}${C_WHITE}🔌 OTWARTE PORTY (nasłuchujące)${C_RESET}"
        echo -e "$div"
        ss -tlnp 2>/dev/null | awk 'NR>1 {
            n=split($4,addr,":")
            port=addr[n]
            if (port+0>0) {
                svc=""
                if (match($0,/"([a-zA-Z0-9_-]+)"/,a)) svc=a[1]
                printf "  %-8s %s\n", port, svc
            }
        }' | sort -n | uniq | head -20

        echo -e "\n$div"
        # BBR status
        local bbr_current; bbr_current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        local bbr_status="${C_STATUS_I}Wyłączone${C_RESET}"
        [[ "$bbr_current" == "bbr" ]] && bbr_status="${C_STATUS_A}Aktywne (${bbr_current})${C_RESET}"

        echo -e "  ${C_DIM}TCP Congestion: ${bbr_status}${C_RESET}"
        echo -e "  ${C_CHOICE}[1]${C_RESET} 🚀 Speedtest  ${C_CHOICE}[2]${C_RESET} ⚡ BBR  ${C_CHOICE}[3]${C_RESET} 🛡️ Fail2Ban  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"
        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" ss_choice

        case "$ss_choice" in
            1)
                clear; show_banner
                echo -e "${C_BOLD}${C_PURPLE}--- 🚀 SPEEDTEST ---${C_RESET}\n"
                # Instaluj oficjalny Speedtest® by Ookla®
                if ! command -v speedtest &>/dev/null || ! speedtest --version 2>/dev/null | grep -qi "ookla"; then
                    echo -e "${C_BLUE}📦 Instalowanie Speedtest® by Ookla®...${C_RESET}"
                    # Usuń stary speedtest-cli jeśli jest
                    pip3 uninstall speedtest-cli -y &>/dev/null
                    apt-get remove -y speedtest-cli &>/dev/null
                    # Metoda 1: oficjalne repo Ookla
                    local arch; arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
                    local codename; codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
                    # Ubuntu 24.04 (noble) → użyj jammy repo
                    [[ "$codename" == "noble" || "$codename" == "oracular" ]] && codename="jammy"
                    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh |                         os=ubuntu dist="$codename" bash &>/dev/null
                    apt-get install -y speedtest &>/dev/null
                    # Metoda 2: bezpośrednie pobranie binarki
                    if ! command -v speedtest &>/dev/null; then
                        echo -e "${C_YELLOW}Próba alternatywnej instalacji...${C_RESET}"
                        local st_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
                        [[ "$arch" == "arm64" || "$arch" == "aarch64" ]] &&                             st_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
                        wget -q -O /tmp/speedtest.tgz "$st_url" &&                             tar -xzf /tmp/speedtest.tgz -C /tmp/ &&                             mv /tmp/speedtest /usr/local/bin/speedtest &&                             chmod +x /usr/local/bin/speedtest
                        rm -f /tmp/speedtest.tgz /tmp/speedtest.md /tmp/speedtest.5 2>/dev/null
                    fi
                    if ! command -v speedtest &>/dev/null; then
                        echo -e "${C_RED}❌ Nie udało się zainstalować Speedtest® by Ookla®.${C_RESET}"
                        press_enter; continue
                    fi
                fi
                echo -e "${C_CYAN}Trwa test Speedtest® by Ookla®...${C_RESET}\n"
                speedtest
                press_enter
                ;;

            2)
                clear; show_banner
                echo -e "${C_BOLD}${C_PURPLE}--- ⚡ BBR — Congestion Control ---${C_RESET}\n"

                local bbr_cur; bbr_cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
                local bbr_avail; bbr_avail=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
                local bbr_qdisc; bbr_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
                local kernel_ver; kernel_ver=$(uname -r)
                local kernel_major; kernel_major=$(uname -r | cut -d. -f1)
                local kernel_minor; kernel_minor=$(uname -r | cut -d. -f2)

                # Określ wersję BBR na podstawie kernela
                local bbr_ver="v1"
                if (( kernel_major > 6 )) || (( kernel_major == 6 && kernel_minor >= 5 )); then
                    bbr_ver="v3"
                elif (( kernel_major == 6 && kernel_minor >= 0 )); then
                    bbr_ver="v2/v3"
                fi

                echo -e "  ${C_CYAN}Aktualny algorytm:${C_RESET}  ${C_YELLOW}${bbr_cur}${C_RESET}"
                echo -e "  ${C_CYAN}Dostępne:${C_RESET}          ${C_DIM}${bbr_avail}${C_RESET}"
                echo -e "  ${C_CYAN}Queue discipline:${C_RESET}  ${C_DIM}${bbr_qdisc}${C_RESET}"
                echo -e "  ${C_CYAN}Kernel:${C_RESET}            ${C_DIM}${kernel_ver}${C_RESET}"
                echo -e "  ${C_CYAN}Wersja BBR:${C_RESET}        ${C_GREEN}${bbr_ver}${C_RESET} ${C_DIM}(zależna od kernela)${C_RESET}\n"

                if [[ "$bbr_cur" == "bbr" ]]; then
                    echo -e "  ${C_GREEN}✅ BBR jest aktywny${C_RESET}\n"
                    echo -e "  ${C_CHOICE}[1]${C_RESET} 🔓 Wyłącz BBR (przywróć cubic)"
                else
                    echo -e "  ${C_YELLOW}⚠️  BBR nie jest aktywny${C_RESET}\n"
                    echo -e "  ${C_CHOICE}[1]${C_RESET} ⚡ Włącz BBR"
                fi
                echo -e "  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"

                read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" bbr_choice
                case "$bbr_choice" in
                    1)
                        if [[ "$bbr_cur" == "bbr" ]]; then
                            # Wyłącz BBR
                            sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf 2>/dev/null
                            sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf 2>/dev/null
                            sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null
                            sysctl -w net.core.default_qdisc=pfifo_fast &>/dev/null
                            echo -e "\n${C_GREEN}✅ BBR wyłączony — przywrócono cubic${C_RESET}"
                        else
                            # Włącz BBR
                            echo -e "\n${C_BLUE}⚡ Włączanie BBR...${C_RESET}"
                            # Załaduj moduł
                            modprobe tcp_bbr 2>/dev/null
                            # Zapisz do modułów (ładuj przy starcie)
                            if ! grep -q "tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
                                echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
                            fi
                            # Sprawdź czy BBR dostępny
                            if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
                                echo -e "${C_RED}❌ BBR niedostępny w tym kernelu.${C_RESET}"
                                echo -e "${C_DIM}Kernel: $(uname -r)${C_RESET}"
                                press_enter; continue
                            fi
                            # Usuń stare wpisy
                            sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
                            sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null
                            # Dodaj nowe
                            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                            sysctl -p &>/dev/null
                            local bbr_new; bbr_new=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
                            if [[ "$bbr_new" == "bbr" ]]; then
                                echo -e "${C_GREEN}✅ BBR aktywny! (kernel: $(uname -r))${C_RESET}"
                                echo -e "${C_DIM}Ustawienie zostanie zachowane po restarcie.${C_RESET}"
                            else
                                echo -e "${C_RED}❌ Nie udało się włączyć BBR.${C_RESET}"
                            fi
                        fi
                        press_enter
                        ;;
                    0|"") ;;
                esac
                ;;
            3) fail2ban_menu ;;
            0|"") return ;;
            *) ;;
        esac
    done
}






# ============================================================
# V2Ray/Xray User Management
# ============================================================

























 w bloku server





show_scheduled_activations() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📅 ZAPLANOWANE AKTYWACJE ---${C_RESET}\n"

    local today; today=$(date +%Y-%m-%d)
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"
    local found=0

    # Wyczyść przeterminowane crony (data aktywacji już minęła)
    local cleaned=0
    while IFS= read -r cron_line; do
        [[ -z "$cron_line" || "$cron_line" == \#* ]] && continue
        [[ "$cron_line" == *"ff_unlock_"* ]] || continue
        local uname; uname=$(echo "$cron_line" | grep -oP 'ff_unlock_\K[^ #]+')
        [[ -z "$uname" ]] && continue
        local cday cmonth cyear
        cday=$(echo "$cron_line" | awk '{print $3}')
        cmonth=$(echo "$cron_line" | awk '{print $4}')
        cyear=$(date +%Y)
        local act_date; act_date=$(printf "%04d-%02d-%02d" "$cyear" "$cmonth" "$cday" 2>/dev/null)
        if [[ "$act_date" < "$today" || "$act_date" == "$today" ]]; then
            crontab -l 2>/dev/null | grep -v "ff_unlock_${uname}" | crontab - 2>/dev/null
            (( cleaned++ ))
        fi
    done < <(crontab -l 2>/dev/null)
    [[ $cleaned -gt 0 ]] && echo -e "  ${C_DIM}🧹 Usunięto $cleaned wykonanych wpisów.${C_RESET}\n"

    # Pokaż aktywne zaplanowane aktywacje (tylko przyszłe)
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-16s  %-12s  %-12s  %s${C_RESET}\n" "UŻYTKOWNIK" "AKTYWACJA" "WYGASA" "STATUS"
    echo -e "$div"

    while IFS= read -r cron_line; do
        [[ -z "$cron_line" || "$cron_line" == \#* ]] && continue
        [[ "$cron_line" == *"ff_unlock_"* ]] || continue

        local uname; uname=$(echo "$cron_line" | grep -oP 'ff_unlock_\K[^ #]+')
        [[ -z "$uname" ]] && continue

        local cday cmonth cyear
        cday=$(echo "$cron_line" | awk '{print $3}')
        cmonth=$(echo "$cron_line" | awk '{print $4}')
        cyear=$(date +%Y)
        local act_date; act_date=$(printf "%04d-%02d-%02d" "$cyear" "$cmonth" "$cday" 2>/dev/null)

        # Pomiń daty które już minęły lub są dzisiejsze (już wykonane)
        [[ "$act_date" < "$today" || "$act_date" == "$today" ]] && continue

        local act_display; act_display=$(date -d "$act_date" +%d-%m-%Y 2>/dev/null || echo "$act_date")
        local exp_date; exp_date=$(awk -F: -v u="$uname" '$1==u{print $3; exit}' "$DB_FILE" 2>/dev/null)
        local exp_display
        [[ -n "$exp_date" ]] && exp_display=$(date -d "$exp_date" +%d-%m-%Y 2>/dev/null || echo "$exp_date") || exp_display="—"

        local acc_locked=false
        passwd -S "$uname" 2>/dev/null | awk '{print $2}' | grep -q "^L$" && acc_locked=true

        local status_str
        if $acc_locked; then
            status_str="${C_YELLOW}⏳ Zablokowane do $act_display${C_RESET}"
        else
            status_str="${C_GREEN}✅ Aktywne (odblokowane)${C_RESET}"
        fi

        printf "  ${C_WHITE}%-16s${C_RESET}  ${C_CYAN}%-12s${C_RESET}  ${C_DIM}%-12s${C_RESET}  %b\n" \
            "$uname" "$act_display" "$exp_display" "$status_str"
        (( found++ ))
    done < <(crontab -l 2>/dev/null)

    if (( found == 0 )); then
        echo -e "  ${C_YELLOW}ℹ️  Brak zaplanowanych aktywacji.${C_RESET}"
        echo -e "  ${C_DIM}Zaplanuj przez: [3] Odnów konto → [3] Od konkretnej daty${C_RESET}"
    fi
    echo -e "$div\n"

    if (( found > 0 )); then
        echo -e "  ${C_CHOICE}[1]${C_RESET} 🗑️  Anuluj zaplanowaną aktywację"
        echo -e "  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"
        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" sa_choice
        if [[ "$sa_choice" == "1" ]]; then
            read -r -p "👉 Podaj nazwę użytkownika do anulowania: " cancel_user
            if [[ -n "$cancel_user" ]]; then
                crontab -l 2>/dev/null | grep -v "ff_unlock_${cancel_user}" | crontab -
                usermod -U "$cancel_user" 2>/dev/null
                rm -f "/run/ff_sessionban_${cancel_user}" "/run/ff_grace/exceed_${cancel_user}" 2>/dev/null
                echo -e "${C_GREEN}✅ Anulowano aktywację dla: $cancel_user — konto odblokowane.${C_RESET}"
                press_enter
            fi
        fi
    else
        press_enter
    fi
}

# ============================================================
# STUNNEL4 FUNCTIONS
# ============================================================

stunnel_status() {
    if systemctl is-active --quiet stunnel4 2>/dev/null; then
        echo "${C_STATUS_A}(Aktywny)${C_RESET}"
    elif command -v stunnel4 &>/dev/null || command -v stunnel &>/dev/null; then
        echo "${C_STATUS_I}(Zainstalowany - nieaktywny)${C_RESET}"
    else
        echo "${C_STATUS_I}(Nie zainstalowany)${C_RESET}"
    fi
}

install_stunnel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Instalacja Stunnel4 ---${C_RESET}\n"
    echo -e "${C_DIM}Stunnel4 tworzy zaszyfrowane tunele SSL/TLS.${C_RESET}"
    echo -e "${C_DIM}Porty: 222 (SSH), 333 (Dropbear), 777 (TOR/WSS)${C_RESET}\n"

    apt-get update -qq
    apt-get install -y stunnel4

    if ! command -v stunnel4 &>/dev/null && ! command -v stunnel &>/dev/null; then
        echo -e "${C_RED}❌ Instalacja Stunnel4 nie powiodła się.${C_RESET}"
        press_enter; return 1
    fi

    echo -e "${C_BLUE}🔑 Generowanie certyfikatu SSL...${C_RESET}"
    mkdir -p /etc/stunnel

    # Użyj istniejącego certyfikatu jeśli jest
    if [[ -f "$SSL_CERT_CHAIN_FILE" && -f "$SSL_CERT_KEY_FILE" ]]; then
        cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > /etc/stunnel/stunnel.pem
        echo -e "${C_GREEN}✅ Użyto istniejącego certyfikatu SSL.${C_RESET}"
    else
        # Self-signed
        openssl genrsa -out /tmp/stunnel_key.pem 2048 2>/dev/null
        openssl req -new -x509 -key /tmp/stunnel_key.pem -out /tmp/stunnel_cert.pem -days 3650 \
            -subj "/C=PL/ST=Warsaw/L=Warsaw/O=FirewallFalcon/CN=localhost" 2>/dev/null
        cat /tmp/stunnel_cert.pem /tmp/stunnel_key.pem > /etc/stunnel/stunnel.pem
        rm -f /tmp/stunnel_key.pem /tmp/stunnel_cert.pem
        echo -e "${C_YELLOW}⚠️ Użyto certyfikatu self-signed.${C_RESET}"
    fi
    chmod 600 /etc/stunnel/stunnel.pem

    # Konfiguracja
    cat > /etc/stunnel/stunnel.conf << 'EOF'
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# SSH over TLS
[ssh-tls]
accept = 222
connect = 127.0.0.1:22

# Dropbear over TLS
[dropbear-tls]
accept = 333
connect = 127.0.0.1:109

# WSS over TLS (WebSocket SSL)
[wss-tls]
accept = 777
connect = 127.0.0.1:80
EOF

    # Enable
    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || \
        echo 'ENABLED=1' > /etc/default/stunnel4

    systemctl daemon-reload
    systemctl enable stunnel4
    systemctl restart stunnel4

    if systemctl is-active --quiet stunnel4; then
        echo -e "\n${C_GREEN}✅ Stunnel4 zainstalowany i aktywny!${C_RESET}"
        echo -e "  ${C_DIM}Port 222 → SSH (:22) przez TLS${C_RESET}"
        echo -e "  ${C_DIM}Port 333 → Dropbear (:109) przez TLS${C_RESET}"
        echo -e "  ${C_DIM}Port 777 → WebSocket (:80) przez TLS${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Stunnel4 nie uruchomił się.${C_RESET}"
        journalctl -u stunnel4 -n 5 --no-pager 2>/dev/null
    fi
    press_enter
}

uninstall_stunnel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Odinstaluj Stunnel4 ---${C_RESET}\n"
    read -r -p "$(echo -e "${C_WARN}⚠️ Na pewno odinstalować Stunnel4? (t/n): ${C_RESET}")" confirm
    [[ "$confirm" != "t" ]] && return
    systemctl stop stunnel4 2>/dev/null
    systemctl disable stunnel4 2>/dev/null
    apt-get remove -y stunnel4 2>/dev/null
    rm -f /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem
    echo -e "${C_GREEN}✅ Stunnel4 odinstalowany.${C_RESET}"
    press_enter
}

stunnel_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Stunnel4 Manager ---${C_RESET}\n"
        local st_status; st_status=$(stunnel_status)
        echo -e "  ${C_BOLD}${C_WHITE}Status:${C_RESET} $st_status\n"

        if command -v stunnel4 &>/dev/null || command -v stunnel &>/dev/null; then
            echo -e "  ${C_DIM}Konfiguracja: /etc/stunnel/stunnel.conf${C_RESET}"
            echo -e "  ${C_DIM}Port 222 → SSH (:22) przez TLS${C_RESET}"
            echo -e "  ${C_DIM}Port 333 → Dropbear (:109) przez TLS${C_RESET}"
            echo -e "  ${C_DIM}Port 777 → WebSocket (:80) przez TLS${C_RESET}\n"
            printf "  ${C_CHOICE}[1]${C_RESET} ▶️  Uruchom Stunnel4\n"
            printf "  ${C_CHOICE}[2]${C_RESET} ⏹️  Zatrzymaj Stunnel4\n"
            printf "  ${C_CHOICE}[3]${C_RESET} 🔄 Restart Stunnel4\n"
            printf "  ${C_CHOICE}[4]${C_RESET} ⚙️  Edytuj konfigurację\n"
            printf "  ${C_CHOICE}[5]${C_RESET} 🔑 Odnów certyfikat\n"
            printf "  ${C_DANGER}[6]${C_RESET} 🗑️  Odinstaluj\n"
        else
            printf "  ${C_CHOICE}[1]${C_RESET} 📦 Zainstaluj Stunnel4\n"
        fi
        echo -e "\n  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" sc
        case "$sc" in
            1)
                if command -v stunnel4 &>/dev/null || command -v stunnel &>/dev/null; then
                    systemctl start stunnel4
                    echo -e "${C_GREEN}✅ Stunnel4 uruchomiony.${C_RESET}"
                    press_enter
                else
                    install_stunnel
                fi
                ;;
            2) systemctl stop stunnel4; echo -e "${C_YELLOW}⏹️ Zatrzymano.${C_RESET}"; press_enter ;;
            3) systemctl restart stunnel4; echo -e "${C_GREEN}✅ Zrestartowano.${C_RESET}"; press_enter ;;
            4) ${EDITOR:-nano} /etc/stunnel/stunnel.conf; systemctl restart stunnel4 2>/dev/null ;;
            5)
                echo -e "${C_BLUE}🔑 Odnawiam certyfikat...${C_RESET}"
                if [[ -f "$SSL_CERT_CHAIN_FILE" && -f "$SSL_CERT_KEY_FILE" ]]; then
                    cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > /etc/stunnel/stunnel.pem
                    chmod 600 /etc/stunnel/stunnel.pem
                    systemctl restart stunnel4
                    echo -e "${C_GREEN}✅ Certyfikat odnowiony.${C_RESET}"
                else
                    echo -e "${C_YELLOW}Brak certyfikatu SSL — używam self-signed.${C_RESET}"
                    openssl genrsa -out /tmp/sk.pem 2048 2>/dev/null
                    openssl req -new -x509 -key /tmp/sk.pem -out /tmp/sc.pem -days 3650 \
                        -subj "/C=PL/CN=localhost" 2>/dev/null
                    cat /tmp/sc.pem /tmp/sk.pem > /etc/stunnel/stunnel.pem
                    rm -f /tmp/sk.pem /tmp/sc.pem
                    chmod 600 /etc/stunnel/stunnel.pem
                    systemctl restart stunnel4
                    echo -e "${C_GREEN}✅ Certyfikat self-signed wygenerowany.${C_RESET}"
                fi
                press_enter
                ;;
            6) uninstall_stunnel ;;
            0) return ;;
        esac
    done
}

# ============================================================
# DROPBEAR FUNCTIONS
# ============================================================

dropbear_status() {
    if systemctl is-active --quiet dropbear 2>/dev/null; then
        echo "${C_STATUS_A}(Aktywny - porty 109, 143)${C_RESET}"
    elif command -v dropbear &>/dev/null; then
        echo "${C_STATUS_I}(Zainstalowany - nieaktywny)${C_RESET}"
    else
        echo "${C_STATUS_I}(Nie zainstalowany)${C_RESET}"
    fi
}

install_dropbear() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 💧 Instalacja Dropbear ---${C_RESET}\n"
    echo -e "${C_DIM}Dropbear to lekki alternatywny serwer SSH.${C_RESET}"
    echo -e "${C_DIM}Porty: 109 (POP3), 143 (IMAP) — rzadko blokowane przez operatorów.${C_RESET}\n"

    apt-get update -qq
    apt-get install -y dropbear

    if ! command -v dropbear &>/dev/null; then
        echo -e "${C_RED}❌ Instalacja Dropbear nie powiodła się.${C_RESET}"
        press_enter; return 1
    fi

    # Konfiguracja
    cat > /etc/default/dropbear << 'EOF'
# Dropbear SSH daemon configuration
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    # Dodaj /bin/false i nologin do shells jeśli nie ma
    grep -q "^/bin/false$" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells
    grep -q "^/usr/sbin/nologin$" /etc/shells 2>/dev/null || echo "/usr/sbin/nologin" >> /etc/shells

    # Generuj klucze
    mkdir -p /etc/dropbear
    [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]] && \
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null
    [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]] && \
        dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null
    [[ ! -f /etc/dropbear/dropbear_ed25519_host_key ]] && \
        dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null

    systemctl daemon-reload
    systemctl enable dropbear
    systemctl restart dropbear

    if systemctl is-active --quiet dropbear; then
        echo -e "\n${C_GREEN}✅ Dropbear zainstalowany i aktywny!${C_RESET}"
        echo -e "  ${C_DIM}Port 109 (POP3) — SSH przez port pocztowy${C_RESET}"
        echo -e "  ${C_DIM}Port 143 (IMAP) — SSH przez port pocztowy${C_RESET}"
        echo -e "  ${C_DIM}Użytkownicy SSH mają dostęp przez te same konta.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Dropbear nie uruchomił się.${C_RESET}"
        journalctl -u dropbear -n 5 --no-pager 2>/dev/null
    fi
    press_enter
}

uninstall_dropbear() {
    clear; show_banner
    read -r -p "$(echo -e "${C_WARN}⚠️ Na pewno odinstalować Dropbear? (t/n): ${C_RESET}")" confirm
    [[ "$confirm" != "t" ]] && return
    systemctl stop dropbear 2>/dev/null
    systemctl disable dropbear 2>/dev/null
    apt-get remove -y dropbear 2>/dev/null
    echo -e "${C_GREEN}✅ Dropbear odinstalowany.${C_RESET}"
    press_enter
}

dropbear_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 💧 Dropbear Manager ---${C_RESET}\n"
        local db_status; db_status=$(dropbear_status)
        echo -e "  ${C_BOLD}${C_WHITE}Status:${C_RESET} $db_status\n"

        if command -v dropbear &>/dev/null; then
            echo -e "  ${C_DIM}Port 109 i 143 — SSH przez porty pocztowe${C_RESET}\n"
            printf "  ${C_CHOICE}[1]${C_RESET} ▶️  Uruchom Dropbear\n"
            printf "  ${C_CHOICE}[2]${C_RESET} ⏹️  Zatrzymaj Dropbear\n"
            printf "  ${C_CHOICE}[3]${C_RESET} 🔄 Restart Dropbear\n"
            printf "  ${C_DANGER}[4]${C_RESET} 🗑️  Odinstaluj\n"
        else
            printf "  ${C_CHOICE}[1]${C_RESET} 📦 Zainstaluj Dropbear\n"
        fi
        echo -e "\n  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" dc
        case "$dc" in
            1)
                if command -v dropbear &>/dev/null; then
                    systemctl start dropbear
                    echo -e "${C_GREEN}✅ Dropbear uruchomiony.${C_RESET}"; press_enter
                else
                    install_dropbear
                fi
                ;;
            2) systemctl stop dropbear; echo -e "${C_YELLOW}⏹️ Zatrzymano.${C_RESET}"; press_enter ;;
            3) systemctl restart dropbear; echo -e "${C_GREEN}✅ Zrestartowano.${C_RESET}"; press_enter ;;
            4) uninstall_dropbear ;;
            0) return ;;
        esac
    done
}

# ============================================================
# XRAY / V2RAY FUNCTIONS
# Based on AutoScriptXray architecture:
# - Xray binds on 127.0.0.1 only (no port conflicts)
# - Nginx proxies TLS/non-TLS to Xray
# - Users managed via jq in config.json
# - Expiry tracked in /etc/xray/user_expiry.txt
# ============================================================

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_DIR="/usr/local/etc/xray"
XRAY_EXPIRY="/etc/xray/user_expiry.txt"

xray_is_installed() {
    command -v xray &>/dev/null || [[ -f /usr/local/bin/xray ]]
}

xray_running() {
    systemctl is-active --quiet xray 2>/dev/null
}

xray_status_str() {
    if xray_running; then
        echo "${C_STATUS_A}(Aktywny)${C_RESET}"
    elif xray_is_installed; then
        echo "${C_STATUS_I}(Zainstalowany - nieaktywny)${C_RESET}"
    else
        echo "${C_STATUS_I}(Nie zainstalowany)${C_RESET}"
    fi
}

xray_get_domain() {
    cat "$XRAY_DIR/domain" 2>/dev/null || cat /root/domain 2>/dev/null || \
        curl -s -4 https://icanhazip.com 2>/dev/null | tr -d '\n'
}

xray_gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        openssl rand -hex 16 2>/dev/null
}

xray_ensure_jq() {
    if ! command -v jq &>/dev/null; then
        apt-get install -y jq -qq 2>/dev/null
    fi
}

xray_backup_config() {
    local backup="$XRAY_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    cp "$XRAY_CONFIG" "$backup" 2>/dev/null && echo "$backup"
}

xray_restore_config() {
    local backup="$1"
    [[ -f "$backup" ]] && cp "$backup" "$XRAY_CONFIG" && systemctl restart xray 2>/dev/null
}

xray_get_expiry() {
    local user="$1"
    grep "^$user " "$XRAY_EXPIRY" 2>/dev/null | awk '{print $2}'
}

xray_set_expiry() {
    local user="$1" exp="$2"
    mkdir -p "$(dirname "$XRAY_EXPIRY")"
    sed -i "/^$user /d" "$XRAY_EXPIRY" 2>/dev/null
    echo "$user $exp" >> "$XRAY_EXPIRY"
}

xray_install() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⚡ Instalacja Xray ---${C_RESET}\n"

    if xray_is_installed; then
        local ver; ver=$(xray version 2>/dev/null | head -1)
        echo -e "${C_YELLOW}ℹ️ Xray już zainstalowany: $ver${C_RESET}\n"
        read -r -p "👉 Reinstalować? (t/n): " ri
        [[ "$ri" != "t" ]] && return
    fi

    echo -e "${C_BLUE}📥 Instalowanie Xray (oficjalny skrypt)...${C_RESET}"
    local install_script; install_script=$(mktemp)
    curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$install_script" 2>/dev/null
    chmod +x "$install_script"
    bash "$install_script"
    rm -f "$install_script"

    if ! xray_is_installed; then
        echo -e "${C_RED}❌ Instalacja Xray nie powiodła się.${C_RESET}"
        press_enter; return 1
    fi

    echo -e "${C_GREEN}✅ Xray zainstalowany: $(xray version 2>/dev/null | head -1)${C_RESET}"

    # Utwórz katalogi
    mkdir -p "$XRAY_DIR" /var/log/xray /etc/xray
    touch /var/log/xray/access.log /var/log/xray/error.log
    id xray &>/dev/null || useradd -r -s /usr/sbin/nologin xray 2>/dev/null
    chown -R xray:xray "$XRAY_DIR" /var/log/xray 2>/dev/null

    xray_ensure_jq

    # Zapisz domenę
    read -r -p "👉 Podaj domenę (lub Enter dla IP): " xray_domain
    if [[ -n "$xray_domain" ]]; then
        echo "$xray_domain" > "$XRAY_DIR/domain"
        echo "$xray_domain" > /root/domain
    fi

    echo -e "\n${C_CYAN}Teraz skonfiguruj Xray przez [9] Konfiguruj Xray w menu.${C_RESET}"
    press_enter
}

xray_setup_nginx_proxy() {
    # Konfiguruje Nginx jako proxy dla Xray WebSocket
    # Bazuje na architekturze AutoScriptXray:
    # Nginx:8080 (non-TLS) i Nginx:4433 (TLS) → Xray:10001-10008
    local cert_file="$SSL_CERT_CHAIN_FILE"
    local key_file="$SSL_CERT_KEY_FILE"
    local has_tls=false
    [[ -f "$cert_file" && -f "$key_file" ]] && has_tls=true

    # Użyj certyfikatu Xray jeśli jest
    if [[ -f "$XRAY_DIR/xray.crt" && -f "$XRAY_DIR/xray.key" ]]; then
        cert_file="$XRAY_DIR/xray.crt"
        key_file="$XRAY_DIR/xray.key"
        has_tls=true
    fi

    cat > /etc/nginx/conf.d/xray.conf << NGINXEOF
# FirewallFalcon Xray Proxy Config
server {
    listen 127.0.0.1:20080;
    server_name _;

    location /vless {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /vmess {
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /trojan-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /ss-ws {
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
}
NGINXEOF

    # Dodaj blok TLS jeśli mamy certyfikat
    if $has_tls; then
        cat >> /etc/nginx/conf.d/xray.conf << TLSEOF

server {
    listen 127.0.0.1:20443 ssl http2;
    server_name _;

    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1h;

    location /vless {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /vmess {
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /trojan-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /ss-ws {
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10005;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        proxy_buffering off;
        client_max_body_size 0;
    }
    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10006;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        proxy_buffering off;
        client_max_body_size 0;
    }
    location /trojan-grpc {
        grpc_pass grpc://127.0.0.1:10007;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        proxy_buffering off;
        client_max_body_size 0;
    }
    location /ss-grpc {
        grpc_pass grpc://127.0.0.1:10008;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        proxy_buffering off;
        client_max_body_size 0;
    }
}
TLSEOF
    fi

    if nginx -t &>/dev/null 2>&1; then
        systemctl reload nginx 2>/dev/null
        echo -e "${C_GREEN}✅ Nginx proxy dla Xray skonfigurowany.${C_RESET}"
        $has_tls && echo -e "  ${C_DIM}TLS: Nginx:20443 → Xray:10001-10008${C_RESET}"
        echo -e "  ${C_DIM}non-TLS: Nginx:20080 → Xray:10001-10004${C_RESET}"
    else
        echo -e "${C_RED}❌ Błąd konfiguracji Nginx.${C_RESET}"
        nginx -t 2>&1
        rm -f /etc/nginx/conf.d/xray.conf
    fi
}

xray_setup_config() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⚙️ Konfiguracja Xray ---${C_RESET}\n"
    echo -e "${C_DIM}Xray nasłuchuje tylko na localhost (127.0.0.1)${C_RESET}"
    echo -e "${C_DIM}Nginx przekazuje ruch z portów 80/443 do Xray${C_RESET}\n"

    local uuid; uuid=$(xray_gen_uuid)
    local domain; domain=$(xray_get_domain)

    echo -e "${C_DIM}Domena/IP: $domain${C_RESET}"
    echo -e "${C_DIM}UUID startowy: $uuid${C_RESET}\n"

    # Utwórz config.json — Xray binduje tylko na 127.0.0.1
    mkdir -p "$XRAY_DIR"
    cat > "$XRAY_CONFIG" << XRAYEOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/10001/vless" }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/10002/vmess" }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/10003/trojan-ws" }
      }
    },
    {
      "tag": "ss-ws",
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/10004/ss-ws" }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "10005/vless-grpc" }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "10006/vmess-grpc" }
      }
    },
    {
      "tag": "trojan-grpc",
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "10007/trojan-grpc" }
      }
    },
    {
      "tag": "ss-grpc",
      "listen": "127.0.0.1",
      "port": 10008,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "10008/ss-grpc" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" }
    ]
  }
}
XRAYEOF

    # Systemd service
    cat > /etc/systemd/system/xray.service << 'SVCEOF'
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SVCEOF

    id xray &>/dev/null || useradd -r -s /usr/sbin/nologin xray 2>/dev/null
    chown -R xray:xray "$XRAY_DIR" /var/log/xray 2>/dev/null
    chmod 644 "$XRAY_CONFIG" 2>/dev/null
    chmod 755 "$XRAY_DIR" 2>/dev/null
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 2

    if xray_running; then
        echo -e "${C_GREEN}✅ Xray uruchomiony pomyślnie!${C_RESET}"
        # Skonfiguruj Nginx proxy
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "${C_BLUE}⚙️ Konfigurowanie Nginx proxy...${C_RESET}"
            xray_setup_nginx_proxy
        fi
    else
        echo -e "${C_RED}❌ Xray nie uruchomił się.${C_RESET}"
        xray run -config "$XRAY_CONFIG" 2>&1 | tail -5
    fi

    # Dodaj do HAProxy routing WebSocket (jeśli HAProxy jest aktywny)
    xray_update_haproxy_routing

    press_enter
}

xray_update_haproxy_routing() {
    # Dodaje routing WebSocket do HAProxy przez Nginx
    # Port 80 → HAProxy → Nginx:8880 → /vless,/vmess,/trojan-ws,/ss-ws → Xray
    # Port 443 → HAProxy → Nginx:8443 → /vless,/vmess → Xray
    # Nginx już jest skonfigurowany w istniejącym projekcie
    # Tylko upewniamy się że Nginx ma routing do Xray na 20080
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        return 0
    fi

    # Sprawdź czy Nginx ma port 8880 (istniejący config)
    local nginx_conf
    nginx_conf=$(nginx -T 2>/dev/null | grep -o "listen [0-9]*" | awk '{print $2}' | sort -u | tr '\n' ' ')
    echo -e "${C_DIM}Nginx nasłuchuje na portach: $nginx_conf${C_RESET}"
    echo -e "${C_DIM}Ruch WebSocket: port 80/443 → HAProxy → Nginx → Xray (127.0.0.1:10001-10004)${C_RESET}"
}

xray_add_user() {
    local protocol="$1"
    local tag_ws tag_grpc proto_name
    case "$protocol" in
        vless)   tag_ws="vless-ws";  tag_grpc="vless-grpc";  proto_name="VLess" ;;
        vmess)   tag_ws="vmess-ws";  tag_grpc="vmess-grpc";  proto_name="VMess" ;;
        trojan)  tag_ws="trojan-ws"; tag_grpc="trojan-grpc"; proto_name="Trojan" ;;
        ss)      tag_ws="ss-ws";     tag_grpc="ss-grpc";     proto_name="Shadowsocks" ;;
        *) return 1 ;;
    esac

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Utwórz konto $proto_name ---${C_RESET}\n"

    if ! xray_is_installed || [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${C_RED}❌ Xray nie jest zainstalowany lub brak konfiguracji.${C_RESET}"
        press_enter; return 1
    fi
    xray_ensure_jq

    read -r -p "👉 Nazwa użytkownika: " user
    [[ -z "$user" || "$user" == "0" ]] && return
    if ! [[ "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${C_RED}❌ Nazwa może zawierać tylko litery, cyfry i _${C_RESET}"
        press_enter; return
    fi

    # Sprawdź czy istnieje
    if jq -e ".inbounds[] | select(.tag == \"$tag_ws\") | .settings.clients[]? | select(.email == \"$user\")" \
        "$XRAY_CONFIG" > /dev/null 2>&1; then
        echo -e "${C_RED}❌ Użytkownik '$user' już istnieje.${C_RESET}"
        press_enter; return
    fi

    read -r -p "🗓️ Czas trwania w dniach [30]: " days
    days=${days:-30}; [[ ! "$days" =~ ^[0-9]+$ ]] && days=30

    local uuid; uuid=$(xray_gen_uuid)
    local exp; exp=$(date -d "+${days} days" +%Y-%m-%d)
    local domain; domain=$(xray_get_domain)
    local backup; backup=$(xray_backup_config)

    # Dodaj do WS inbound
    local new_client
    case "$protocol" in
        vless) new_client="{\"id\": \"$uuid\", \"email\": \"$user\"}" ;;
        vmess) new_client="{\"id\": \"$uuid\", \"alterId\": 0, \"email\": \"$user\"}" ;;
        trojan|ss) new_client="{\"password\": \"$uuid\", \"email\": \"$user\"}" ;;
    esac

    # Użyj Python do bezpiecznego dodania użytkownika — unika problemów z uprawnieniami
    python3 - "$XRAY_CONFIG" "$tag_ws" "$tag_grpc" "$new_client" << 'PYEOF'
import json, sys, os

config_file = sys.argv[1]
tag_ws = sys.argv[2]
tag_grpc = sys.argv[3]
new_client_str = sys.argv[4]

try:
    new_client = json.loads(new_client_str)
except:
    print("ERROR: invalid client JSON", file=sys.stderr)
    sys.exit(1)

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    print("ERROR: cannot read config", file=sys.stderr)
    sys.exit(1)

# Dodaj do WS i gRPC
for ib in config.get('inbounds', []):
    if ib.get('tag') in [tag_ws, tag_grpc]:
        clients = ib.get('settings', {}).get('clients', [])
        # Sprawdź czy już istnieje
        email = new_client.get('email', '')
        if not any(c.get('email') == email or c.get('password') == email for c in clients):
            clients.append(new_client)
            ib['settings']['clients'] = clients

# Zapisz z poprawnymi uprawnieniami
import tempfile, shutil
tmp = config_file + '.writing'
with open(tmp, 'w') as f:
    json.dump(config, f, indent=2)

# Ustaw uprawnienia zanim przeniesiemy
try:
    import pwd
    xray_uid = pwd.getpwnam('xray').pw_uid
    xray_gid = pwd.getpwnam('xray').pw_gid
    os.chown(tmp, xray_uid, xray_gid)
except:
    pass
os.chmod(tmp, 0o644)
shutil.move(tmp, config_file)
print("OK")
PYEOF

    local py_result=$?
    if [[ $py_result -ne 0 ]]; then
        echo -e "${C_RED}❌ Błąd dodawania użytkownika.${C_RESET}"
        xray_restore_config "$backup"; press_enter; return
    fi

    # Zapisz expiry
    xray_set_expiry "$user" "$exp"

    # Restart
    systemctl restart xray 2>/dev/null
    sleep 3

    if ! xray_running; then
        echo -e "${C_RED}❌ Xray nie uruchomił się — przywracam backup.${C_RESET}"
        xray_restore_config "$backup"; press_enter; return
    fi
    rm -f "$backup"

    # Generuj linki
    # Xray nasłuchuje na 127.0.0.1:10001-10008
    # Nginx routing: GET /10002/vmess → proxy_pass 127.0.0.1:10002/vmess
    # Klient łączy się na port 80 lub 443, ścieżka = /XRAY_PORT/PROTO_PATH
    local tls_port=443 ntls_port=80
    local link_tls link_ntls link_grpc
    local xray_ws_port
    case "$protocol" in
        vless)  xray_ws_port=10001 ;;
        vmess)  xray_ws_port=10002 ;;
        trojan) xray_ws_port=10003 ;;
        ss)     xray_ws_port=10004 ;;
    esac
    local ws_path grpc_svc
    case "$protocol" in
        vless)  ws_path="vless";     grpc_svc="vless-grpc" ;;
        vmess)  ws_path="vmess";     grpc_svc="vmess-grpc" ;;
        trojan) ws_path="trojan-ws"; grpc_svc="trojan-grpc" ;;
        ss)     ws_path="ss-ws";     grpc_svc="ss-grpc" ;;
    esac
    # Nginx dynamic path: /PORT/PATH
    local nginx_path="/${xray_ws_port}/${ws_path}"
    local nginx_path_enc
    nginx_path_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$nginx_path" 2>/dev/null || echo "%2F${xray_ws_port}%2F${ws_path}")

    case "$protocol" in
        vless)
            link_tls="vless://${uuid}@${domain}:${tls_port}?path=${nginx_path_enc}&security=tls&encryption=none&type=ws&sni=${domain}&host=${domain}#${user}"
            link_ntls="vless://${uuid}@${domain}:${ntls_port}?path=${nginx_path_enc}&security=none&encryption=none&type=ws&host=${domain}#${user}"
            link_grpc="vless://${uuid}@${domain}:${tls_port}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${grpc_svc}&sni=${domain}#${user}-gRPC"
            ;;
        vmess)
            local ws_tls_json="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$tls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"$nginx_path\",\"host\":\"$domain\",\"tls\":\"tls\",\"sni\":\"$domain\"}"
            local ws_ntls_json="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$ntls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"$nginx_path\",\"host\":\"$domain\",\"tls\":\"none\"}"
            local grpc_json="{\"v\":\"2\",\"ps\":\"$user-gRPC\",\"add\":\"$domain\",\"port\":\"$tls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"grpc\",\"path\":\"$grpc_svc\",\"host\":\"$domain\",\"tls\":\"tls\",\"sni\":\"$domain\"}"
            link_tls="vmess://$(echo -n "$ws_tls_json" | base64 -w 0)"
            link_ntls="vmess://$(echo -n "$ws_ntls_json" | base64 -w 0)"
            link_grpc="vmess://$(echo -n "$grpc_json" | base64 -w 0)"
            ;;
        trojan)
            link_tls="trojan://${uuid}@${domain}:${tls_port}?path=${nginx_path_enc}&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
            link_ntls="trojan://${uuid}@${domain}:${ntls_port}?path=${nginx_path_enc}&security=none&host=${domain}&type=ws#${user}"
            link_grpc="trojan://${uuid}@${domain}:${tls_port}?security=tls&type=grpc&serviceName=${grpc_svc}&sni=${domain}#${user}-gRPC"
            ;;
        ss)
            local cipher="aes-128-gcm"
            local ss_path_enc
            ss_path_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$nginx_path" 2>/dev/null || echo "%2F${xray_ws_port}%2F${ws_path}")
            link_tls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${tls_port}?plugin=v2ray-plugin%3Bpath%3D${ss_path_enc}%3Bhost%3D${domain}%3Btls#${user}"
            link_ntls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${ntls_port}?plugin=v2ray-plugin%3Bpath%3D${ss_path_enc}%3Bhost%3D${domain}#${user}"
            link_grpc=""
            ;;
    esac

    # Wyświetl wynik
    clear; show_banner
    echo -e "${C_GREEN}✅ Konto $proto_name '${C_YELLOW}$user${C_GREEN}' utworzone!${C_RESET}\n"
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"
    echo -e "$div"
    echo -e "  ${C_CYAN}Użytkownik:${C_RESET}  $user"
    echo -e "  ${C_CYAN}UUID/Hasło:${C_RESET}  $uuid"
    echo -e "  ${C_CYAN}Protokół:${C_RESET}    $proto_name WebSocket"
    echo -e "  ${C_CYAN}Domena:${C_RESET}      $domain"
    echo -e "  ${C_CYAN}Wygasa:${C_RESET}      $exp"
    echo -e "$div\n"
    echo -e "  ${C_BOLD}🔗 Link TLS (port 443):${C_RESET}"
    echo -e "  ${C_YELLOW}$link_tls${C_RESET}\n"
    echo -e "  ${C_BOLD}🔗 Link non-TLS (port 80):${C_RESET}"
    echo -e "  ${C_YELLOW}$link_ntls${C_RESET}\n"
    [[ -n "$link_grpc" ]] && echo -e "  ${C_BOLD}🔗 Link gRPC:${C_RESET}\n  ${C_YELLOW}$link_grpc${C_RESET}\n"
    if command -v qrencode &>/dev/null; then
        echo -e "  ${C_DIM}QR kod (TLS):${C_RESET}"
        qrencode -t ANSIUTF8 "$link_tls" 2>/dev/null
    fi
    press_enter
}

xray_del_user() {
    local protocol="$1"
    local tag_ws tag_grpc proto_name
    case "$protocol" in
        vless)  tag_ws="vless-ws";  tag_grpc="vless-grpc";  proto_name="VLess" ;;
        vmess)  tag_ws="vmess-ws";  tag_grpc="vmess-grpc";  proto_name="VMess" ;;
        trojan) tag_ws="trojan-ws"; tag_grpc="trojan-grpc"; proto_name="Trojan" ;;
        ss)     tag_ws="ss-ws";     tag_grpc="ss-grpc";     proto_name="Shadowsocks" ;;
    esac

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Usuń konto $proto_name ---${C_RESET}\n"
    xray_ensure_jq

    # Lista użytkowników
    local users
    users=$(jq -r ".inbounds[] | select(.tag == \"$tag_ws\") | .settings.clients[]? | .email // .password" \
        "$XRAY_CONFIG" 2>/dev/null)

    if [[ -z "$users" ]]; then
        echo -e "${C_YELLOW}ℹ️ Brak użytkowników $proto_name.${C_RESET}"
        press_enter; return
    fi

    local i=1; local -a ulist=()
    while IFS= read -r u; do
        local exp; exp=$(xray_get_expiry "$u")
        printf "  ${C_CHOICE}[%2d]${C_RESET} %-16s ${C_DIM}%s${C_RESET}\n" "$i" "$u" "${exp:-brak daty}"
        ulist+=("$u"); (( i++ ))
    done <<< "$users"

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" sel
    [[ "$sel" == "0" || -z "$sel" ]] && return
    [[ ! "$sel" =~ ^[0-9]+$ || $sel -lt 1 || $sel -gt ${#ulist[@]} ]] && return
    local user="${ulist[$((sel-1))]}"

    read -r -p "⚠️ Na pewno usunąć '$user'? (t/n): " confirm
    [[ "$confirm" != "t" ]] && return

    local backup; backup=$(xray_backup_config)
    local tmp; tmp=$(mktemp)

    # Usuń z WS i gRPC
    jq "(.inbounds[] | select(.tag == \"$tag_ws\").settings.clients) |= map(select(.email != \"$user\" and .password != \"$user\"))" \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    tmp=$(mktemp)
    jq "(.inbounds[] | select(.tag == \"$tag_grpc\").settings.clients) |= map(select(.email != \"$user\" and .password != \"$user\"))" \
        "$XRAY_CONFIG" > "$tmp" 2>/dev/null && mv "$tmp" "$XRAY_CONFIG"
    rm -f "$tmp"

    # Usuń expiry
    sed -i "/^$user /d" "$XRAY_EXPIRY" 2>/dev/null

    systemctl restart xray 2>/dev/null
    rm -f "$backup"
    echo -e "${C_GREEN}✅ Usunięto konto: $user${C_RESET}"
    press_enter
}

xray_list_users() {
    local protocol="$1"
    local tag_ws proto_name
    case "$protocol" in
        vless)  tag_ws="vless-ws";  proto_name="VLess" ;;
        vmess)  tag_ws="vmess-ws";  proto_name="VMess" ;;
        trojan) tag_ws="trojan-ws"; proto_name="Trojan" ;;
        ss)     tag_ws="ss-ws";     proto_name="Shadowsocks" ;;
        all)    tag_ws=""; proto_name="Wszystkie" ;;
    esac

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗂️ Lista kont $proto_name ---${C_RESET}\n"
    xray_ensure_jq

    local today; today=$(date +%Y-%m-%d)
    local div="${C_BLUE}  ────────────────────────────────────────────────────────${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-16s  %-12s  %-10s  %s${C_RESET}\n" "UŻYTKOWNIK" "WYGASA" "PROTOKÓŁ" "STATUS"
    echo -e "$div"

    for tag in "vless-ws" "vmess-ws" "trojan-ws" "ss-ws"; do
        [[ -n "$tag_ws" && "$tag" != "$tag_ws" ]] && continue
        local proto_label
        case "$tag" in
            vless-ws)  proto_label="VLess" ;;
            vmess-ws)  proto_label="VMess" ;;
            trojan-ws) proto_label="Trojan" ;;
            ss-ws)     proto_label="SS" ;;
        esac

        while IFS= read -r user; do
            [[ -z "$user" ]] && continue
            local exp; exp=$(xray_get_expiry "$user")
            local sc="$C_GREEN" status="Aktywny"
            if [[ -n "$exp" && "$exp" < "$today" ]]; then
                sc="$C_RED"; status="Wygasłe"
            elif [[ -z "$exp" ]]; then
                status="Brak daty"
            fi
            local diff=""
            [[ -n "$exp" && "$exp" > "$today" ]] && \
                diff=$(( ($(date -d "$exp" +%s) - $(date +%s)) / 86400 ))d
            printf "  ${sc}%-16s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${C_CYAN}%-10s${C_RESET}  ${sc}%s${C_RESET}\n" \
                "$user" "${exp:-—}" "$proto_label" "$status"
        done < <(jq -r ".inbounds[] | select(.tag == \"$tag\") | .settings.clients[]? | .email // .password" \
            "$XRAY_CONFIG" 2>/dev/null)
    done

    echo -e "$div\n"
    press_enter
}

xray_show_link() {
    local protocol="$1"
    local tag_ws proto_name
    case "$protocol" in
        vless)  tag_ws="vless-ws";  proto_name="VLess" ;;
        vmess)  tag_ws="vmess-ws";  proto_name="VMess" ;;
        trojan) tag_ws="trojan-ws"; proto_name="Trojan" ;;
        ss)     tag_ws="ss-ws";     proto_name="Shadowsocks" ;;
    esac

    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔗 Link konfiguracyjny $proto_name ---${C_RESET}\n"
    xray_ensure_jq

    local users
    users=$(jq -r ".inbounds[] | select(.tag == \"$tag_ws\") | .settings.clients[]? | .email // .password" \
        "$XRAY_CONFIG" 2>/dev/null)

    if [[ -z "$users" ]]; then
        echo -e "${C_YELLOW}ℹ️ Brak użytkowników.${C_RESET}"; press_enter; return
    fi

    local i=1; local -a ulist=() uuids=()
    while IFS= read -r u; do
        local uuid; uuid=$(jq -r ".inbounds[] | select(.tag == \"$tag_ws\") | .settings.clients[]? | select((.email // .password) == \"$u\") | .id // .password" \
            "$XRAY_CONFIG" 2>/dev/null | head -1)
        printf "  ${C_CHOICE}[%2d]${C_RESET} %-16s\n" "$i" "$u"
        ulist+=("$u"); uuids+=("$uuid"); (( i++ ))
    done <<< "$users"

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" sel
    [[ "$sel" == "0" || -z "$sel" ]] && return
    [[ ! "$sel" =~ ^[0-9]+$ || $sel -lt 1 || $sel -gt ${#ulist[@]} ]] && return

    local user="${ulist[$((sel-1))]}"
    local uuid="${uuids[$((sel-1))]}"
    local domain; domain=$(xray_get_domain)
    # Xray nasłuchuje na 127.0.0.1:10001-10008
    # Nginx routing: GET /10002/vmess → proxy_pass 127.0.0.1:10002/vmess
    # Klient łączy się na port 80 lub 443, ścieżka = /XRAY_PORT/PROTO_PATH
    local tls_port=443 ntls_port=80
    local link_tls link_ntls link_grpc
    local xray_ws_port
    case "$protocol" in
        vless)  xray_ws_port=10001 ;;
        vmess)  xray_ws_port=10002 ;;
        trojan) xray_ws_port=10003 ;;
        ss)     xray_ws_port=10004 ;;
    esac
    local ws_path grpc_svc
    case "$protocol" in
        vless)  ws_path="vless";     grpc_svc="vless-grpc" ;;
        vmess)  ws_path="vmess";     grpc_svc="vmess-grpc" ;;
        trojan) ws_path="trojan-ws"; grpc_svc="trojan-grpc" ;;
        ss)     ws_path="ss-ws";     grpc_svc="ss-grpc" ;;
    esac
    # Nginx dynamic path: /PORT/PATH
    local nginx_path="/${xray_ws_port}/${ws_path}"
    local nginx_path_enc
    nginx_path_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$nginx_path" 2>/dev/null || echo "%2F${xray_ws_port}%2F${ws_path}")

    case "$protocol" in
        vless)
            link_tls="vless://${uuid}@${domain}:${tls_port}?path=${nginx_path_enc}&security=tls&encryption=none&type=ws&sni=${domain}&host=${domain}#${user}"
            link_ntls="vless://${uuid}@${domain}:${ntls_port}?path=${nginx_path_enc}&security=none&encryption=none&type=ws&host=${domain}#${user}"
            link_grpc="vless://${uuid}@${domain}:${tls_port}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${grpc_svc}&sni=${domain}#${user}-gRPC"
            ;;
        vmess)
            local ws_tls_json="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$tls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"$nginx_path\",\"host\":\"$domain\",\"tls\":\"tls\",\"sni\":\"$domain\"}"
            local ws_ntls_json="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$ntls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"$nginx_path\",\"host\":\"$domain\",\"tls\":\"none\"}"
            local grpc_json="{\"v\":\"2\",\"ps\":\"$user-gRPC\",\"add\":\"$domain\",\"port\":\"$tls_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"grpc\",\"path\":\"$grpc_svc\",\"host\":\"$domain\",\"tls\":\"tls\",\"sni\":\"$domain\"}"
            link_tls="vmess://$(echo -n "$ws_tls_json" | base64 -w 0)"
            link_ntls="vmess://$(echo -n "$ws_ntls_json" | base64 -w 0)"
            link_grpc="vmess://$(echo -n "$grpc_json" | base64 -w 0)"
            ;;
        trojan)
            link_tls="trojan://${uuid}@${domain}:${tls_port}?path=${nginx_path_enc}&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
            link_ntls="trojan://${uuid}@${domain}:${ntls_port}?path=${nginx_path_enc}&security=none&host=${domain}&type=ws#${user}"
            link_grpc="trojan://${uuid}@${domain}:${tls_port}?security=tls&type=grpc&serviceName=${grpc_svc}&sni=${domain}#${user}-gRPC"
            ;;
        ss)
            local cipher="aes-128-gcm"
            local ss_path_enc
            ss_path_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$nginx_path" 2>/dev/null || echo "%2F${xray_ws_port}%2F${ws_path}")
            link_tls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${tls_port}?plugin=v2ray-plugin%3Bpath%3D${ss_path_enc}%3Bhost%3D${domain}%3Btls#${user}"
            link_ntls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${ntls_port}?plugin=v2ray-plugin%3Bpath%3D${ss_path_enc}%3Bhost%3D${domain}#${user}"
            link_grpc=""
            ;;
    esac

    echo -e "\n  ${C_BOLD}$proto_name — $user${C_RESET}"
    echo -e "\n  ${C_BOLD}🔗 TLS (443):${C_RESET}\n  ${C_YELLOW}$link_tls${C_RESET}"
    echo -e "\n  ${C_BOLD}🔗 non-TLS (80):${C_RESET}\n  ${C_YELLOW}$link_ntls${C_RESET}"
    [[ -n "$link_grpc" ]] && echo -e "\n  ${C_BOLD}🔗 gRPC:${C_RESET}\n  ${C_YELLOW}$link_grpc${C_RESET}"
    if command -v qrencode &>/dev/null; then
        echo -e "\n  ${C_DIM}QR kod (TLS):${C_RESET}"
        qrencode -t ANSIUTF8 "$link_tls" 2>/dev/null
    fi
    echo
    press_enter
}

xray_cleanup_expired_users() {
    [[ ! -f "$XRAY_EXPIRY" || ! -f "$XRAY_CONFIG" ]] && return 0
    xray_ensure_jq

    local today; today=$(date +%Y-%m-%d)
    local count=0

    while IFS=' ' read -r user exp; do
        [[ -z "$user" || -z "$exp" ]] && continue
        [[ "$exp" < "$today" ]] || continue

        # Usuń z wszystkich inboundów
        local tmp; tmp=$(mktemp)
        jq "(.inbounds[].settings.clients) |= map(select((.email // .password) != \"$user\"))" \
            "$XRAY_CONFIG" > "$tmp" 2>/dev/null && jq empty "$tmp" 2>/dev/null && mv "$tmp" "$XRAY_CONFIG"
        rm -f "$tmp"
        sed -i "/^$user /d" "$XRAY_EXPIRY" 2>/dev/null
        echo -e " 🧹 Usunięto wygasłe: ${C_YELLOW}$user${C_RESET} (wygasło: $exp)"
        (( count++ ))
    done < "$XRAY_EXPIRY"

    (( count > 0 )) && systemctl restart xray 2>/dev/null
    [[ $count -eq 0 ]] && echo -e " ${C_GREEN}✅ Brak wygasłych kont Xray.${C_RESET}"
    return 0
}

# ============================================================
# PROTOCOL SUBMENU: VLess, VMess, Trojan, Shadowsocks
# ============================================================

xray_protocol_submenu() {
    local protocol="$1"
    local proto_name
    local emoji
    case "$protocol" in
        vless)  proto_name="VLess";       emoji="🔵" ;;
        vmess)  proto_name="VMess";       emoji="🟣" ;;
        trojan) proto_name="Trojan";      emoji="🔴" ;;
        ss)     proto_name="Shadowsocks"; emoji="🟤" ;;
    esac

    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- $emoji $proto_name Manager ---${C_RESET}\n"

        if ! xray_is_installed; then
            echo -e "  ${C_RED}❌ Xray nie jest zainstalowany.${C_RESET}"
            echo -e "  Wróć do menu Xray i zainstaluj najpierw.\n"
            press_enter; return
        fi

        local user_count
        local tag_ws
        case "$protocol" in
            vless)  tag_ws="vless-ws" ;;
            vmess)  tag_ws="vmess-ws" ;;
            trojan) tag_ws="trojan-ws" ;;
            ss)     tag_ws="ss-ws" ;;
        esac
        user_count=$(jq -r ".inbounds[] | select(.tag == \"$tag_ws\") | .settings.clients[]? | .email // .password" \
            "$XRAY_CONFIG" 2>/dev/null | grep -c .)

        echo -e "  ${C_DIM}Użytkownicy $proto_name: $user_count${C_RESET}\n"

        printf "  ${C_CHOICE}[1]${C_RESET} ✨ Utwórz konto\n"
        printf "  ${C_CHOICE}[2]${C_RESET} 🗑️  Usuń konto\n"
        printf "  ${C_CHOICE}[3]${C_RESET} 🗂️  Lista kont\n"
        printf "  ${C_CHOICE}[4]${C_RESET} 🔗 Pokaż link / QR kod\n"
        echo -e "\n  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" pc
        case "$pc" in
            1) xray_add_user "$protocol" ;;
            2) xray_del_user "$protocol" ;;
            3) xray_list_users "$protocol" ;;
            4) xray_show_link "$protocol" ;;
            0) return ;;
        esac
    done
}

# ============================================================
# GŁÓWNE MENU XRAY
# ============================================================


xray_quick_show_link() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔗 Pokaż link użytkownika Xray ---${C_RESET}\n"
    if ! xray_is_installed; then
        echo -e "${C_RED}❌ Xray nie jest zainstalowany.${C_RESET}"
        press_enter; return
    fi
    echo -e "  ${C_CHOICE}[1]${C_RESET} 🔵 VLess"
    echo -e "  ${C_CHOICE}[2]${C_RESET} 🟣 VMess"
    echo -e "  ${C_CHOICE}[3]${C_RESET} 🔴 Trojan"
    echo -e "  ${C_CHOICE}[4]${C_RESET} 🟤 Shadowsocks"
    echo -e "\n  ${C_WARN}[0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Protokół [1]: ${C_RESET}")" pc
    pc=${pc:-1}
    case "$pc" in
        1) xray_show_link vless ;;
        2) xray_show_link vmess ;;
        3) xray_show_link trojan ;;
        4) xray_show_link ss ;;
    esac
}

xray_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- ⚡ Xray/V2Ray Manager ---${C_RESET}\n"

        local xray_st; xray_st=$(xray_status_str)
        local ver=""; xray_is_installed && ver="${C_DIM}($(xray version 2>/dev/null | head -1 | grep -oP 'Xray \S+'))${C_RESET}"
        local domain; domain=$(xray_get_domain)

        echo -e "  ${C_BOLD}${C_WHITE}Status:${C_RESET}    $xray_st $ver"
        echo -e "  ${C_BOLD}${C_WHITE}Domena:${C_RESET}    ${C_DIM}${domain}${C_RESET}\n"

        local div="${C_BLUE}  ────────────────────────────────────${C_RESET}"
        echo -e "  ${C_TITLE}${C_BOLD}🌐 PROTOKOŁY${C_RESET}"
        echo -e "$div"
        printf "  ${C_CHOICE}[1]${C_RESET} 🔵 VLess WebSocket + gRPC\n"
        printf "  ${C_CHOICE}[2]${C_RESET} 🟣 VMess WebSocket + gRPC\n"
        printf "  ${C_CHOICE}[3]${C_RESET} 🔴 Trojan WebSocket + gRPC\n"
        printf "  ${C_CHOICE}[4]${C_RESET} 🟤 Shadowsocks WebSocket + gRPC\n"
        printf "  ${C_CHOICE}[5]${C_RESET} 🔗 Pokaż link użytkownika\n"
        printf "  ${C_CHOICE}[6]${C_RESET} 🗂️  Lista wszystkich kont\n"
        printf "  ${C_CHOICE}[7]${C_RESET} 🧹 Usuń wygasłe konta\n"
        echo
        echo -e "  ${C_TITLE}${C_BOLD}⚙️  SERWER${C_RESET}"
        echo -e "$div"
        printf "  ${C_CHOICE}[8]${C_RESET} 📦 Zainstaluj Xray\n"
        printf "  ${C_CHOICE}[9]${C_RESET} ⚙️  Skonfiguruj Xray (config.json + Nginx)\n"
        printf "  ${C_CHOICE}[10]${C_RESET} 🔄 Restart Xray\n"
        printf "  ${C_CHOICE}[11]${C_RESET} 📋 Logi Xray\n"
        printf "  ${C_DANGER}[12]${C_RESET} 🗑️  Odinstaluj Xray\n"
        echo
        printf "  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n\n"

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" xc
        case "$xc" in
            1) xray_protocol_submenu vless ;;
            2) xray_protocol_submenu vmess ;;
            3) xray_protocol_submenu trojan ;;
            4) xray_protocol_submenu ss ;;
            5) xray_quick_show_link ;;
            6) xray_list_users all ;;
            7) xray_cleanup_expired_users; press_enter ;;
            8) xray_install ;;
            9) xray_setup_config ;;
            10) systemctl restart xray 2>/dev/null; echo -e "${C_GREEN}✅ Xray zrestartowany.${C_RESET}"; press_enter ;;
            11)
                clear; show_banner
                echo -e "${C_BOLD}${C_PURPLE}--- 📋 Logi Xray ---${C_RESET}\n"
                journalctl -u xray -n 30 --no-pager 2>/dev/null
                echo -e "\n${C_DIM}Access log:${C_RESET}"
                tail -20 /var/log/xray/access.log 2>/dev/null || echo "(brak)"
                press_enter
                ;;
            12)
                read -r -p "$(echo -e "${C_WARN}⚠️ Na pewno odinstalować Xray? (t/n): ${C_RESET}")" confirm
                if [[ "$confirm" == "t" ]]; then
                    echo -e "${C_BLUE}🗑️ Odinstalowuję Xray...${C_RESET}"
                    systemctl stop xray 2>/dev/null
                    systemctl disable xray 2>/dev/null
                    local rm_script; rm_script=$(mktemp)
                    curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$rm_script" 2>/dev/null
                    chmod +x "$rm_script"
                    "$rm_script" remove --purge 2>&1 | tail -10
                    rm -f "$rm_script"
                    # Usuń ręcznie jeśli zostało
                    rm -f /usr/local/bin/xray
                    rm -rf /usr/local/etc/xray /var/log/xray
                    rm -f /etc/systemd/system/xray.service
                    rm -rf /etc/systemd/system/xray.service.d
                    rm -f /etc/nginx/conf.d/xray.conf
                    systemctl daemon-reload
                    systemctl reload nginx 2>/dev/null
                    if ! command -v xray &>/dev/null && [[ ! -f /usr/local/bin/xray ]]; then
                        echo -e "${C_GREEN}✅ Xray odinstalowany pomyślnie.${C_RESET}"
                    else
                        echo -e "${C_RED}❌ Xray nadal jest obecny - sprawdź ręcznie.${C_RESET}"
                    fi
                    press_enter
                fi
                ;;
            0) return ;;
        esac
    done
}


list_active_sessions() {
    clear; show_banner
    refresh_ssh_session_cache
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"
    echo -e "\n  ${C_BOLD}${C_WHITE}📋 AKTYWNE SESJE${C_RESET}  ${C_DIM}(od największej liczby sesji)${C_RESET}"
    echo -e "$div"

    local found=0
    local -a rows=()
    while IFS=: read -r user pass expiry limit _rest; do
        local online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        if (( online_count > 0 )); then
            # Format: liczba_sesji|user|expiry|online/limit (sortowanie po pierwszej kolumnie)
            rows+=("$(printf '%05d' "$online_count")|$user|$expiry|$online_count/$limit")
            (( found++ ))
        fi
    done < "$DB_FILE"

    if (( found == 0 )); then
        echo -e "  ${C_YELLOW}ℹ️  Brak aktywnych sesji.${C_RESET}"
        echo -e "$div"
        return
    fi

    printf "  ${C_BOLD}${C_WHITE}%-16s  %-12s  %s${C_RESET}\n" "UŻYTKOWNIK" "WYGASA" "SESJE"
    echo -e "$div"
    # Sortuj malejąco po liczbie sesji (-r reverse)
    while IFS='|' read -r _count user expiry sessions; do
        printf "  ${C_GREEN}%-16s${C_RESET}  ${C_YELLOW}%-12s${C_RESET}  ${C_CYAN}%s${C_RESET}\n" \
            "$user" "${expiry:-—}" "$sessions"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1nr)
    echo -e "$div"
    echo -e "  ${C_DIM}Łącznie: ${found} aktywnych użytkowników${C_RESET}\n"
}



xray_quick_add() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Utwórz konto Xray ---${C_RESET}\n"
    if ! xray_is_installed; then
        echo -e "${C_RED}❌ Xray nie jest zainstalowany. Wejdź w [15] Pełny menedżer Xray.${C_RESET}"
        press_enter; return
    fi
    echo -e "  ${C_CHOICE}[1]${C_RESET} 🔵 VLess"
    echo -e "  ${C_CHOICE}[2]${C_RESET} 🟣 VMess"
    echo -e "  ${C_CHOICE}[3]${C_RESET} 🔴 Trojan"
    echo -e "  ${C_CHOICE}[4]${C_RESET} 🟤 Shadowsocks"
    echo -e "\n  ${C_WARN}[0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Protokół [1]: ${C_RESET}")" pc
    pc=${pc:-1}
    case "$pc" in
        1) xray_add_user vless ;;
        2) xray_add_user vmess ;;
        3) xray_add_user trojan ;;
        4) xray_add_user ss ;;
    esac
}

xray_quick_del() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Usuń konto Xray ---${C_RESET}\n"
    if ! xray_is_installed; then
        echo -e "${C_RED}❌ Xray nie jest zainstalowany.${C_RESET}"
        press_enter; return
    fi
    echo -e "  ${C_CHOICE}[1]${C_RESET} 🔵 VLess"
    echo -e "  ${C_CHOICE}[2]${C_RESET} 🟣 VMess"
    echo -e "  ${C_CHOICE}[3]${C_RESET} 🔴 Trojan"
    echo -e "  ${C_CHOICE}[4]${C_RESET} 🟤 Shadowsocks"
    echo -e "\n  ${C_WARN}[0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Protokół [1]: ${C_RESET}")" pc
    pc=${pc:-1}
    case "$pc" in
        1) xray_del_user vless ;;
        2) xray_del_user vmess ;;
        3) xray_del_user trojan ;;
        4) xray_del_user ss ;;
    esac
}

xray_renew_user_quick() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Odnów konto Xray ---${C_RESET}\n"
    if ! xray_is_installed || [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${C_RED}❌ Xray nie jest zainstalowany.${C_RESET}"
        press_enter; return
    fi
    xray_ensure_jq

    # Lista wszystkich użytkowników z wszystkich protokołów
    local div="${C_BLUE}  ──────────────────────────────────────────────────${C_RESET}"
    echo -e "$div"
    printf "  ${C_BOLD}${C_WHITE}%-4s  %-16s  %-12s  %s${C_RESET}\n" "NR" "UŻYTKOWNIK" "WYGASA" "PROTOKÓŁ"
    echo -e "$div"

    local i=1
    local -a ulist=() plist=()
    for tag in "vless-ws" "vmess-ws" "trojan-ws" "ss-ws"; do
        local proto_label
        case "$tag" in
            vless-ws)  proto_label="VLess" ;;
            vmess-ws)  proto_label="VMess" ;;
            trojan-ws) proto_label="Trojan" ;;
            ss-ws)     proto_label="SS" ;;
        esac
        while IFS= read -r user; do
            [[ -z "$user" ]] && continue
            local exp; exp=$(xray_get_expiry "$user")
            printf "  ${C_CHOICE}[%2d]${C_RESET}  %-16s  ${C_YELLOW}%-12s${C_RESET}  ${C_CYAN}%s${C_RESET}\n" \
                "$i" "$user" "${exp:-—}" "$proto_label"
            ulist+=("$user")
            plist+=("$tag")
            (( i++ ))
        done < <(jq -r ".inbounds[] | select(.tag == \"$tag\") | .settings.clients[]? | .email // .password" \
            "$XRAY_CONFIG" 2>/dev/null)
    done
    echo -e "$div"

    if (( i == 1 )); then
        echo -e "  ${C_YELLOW}ℹ️ Brak użytkowników Xray.${C_RESET}"
        press_enter; return
    fi

    echo -e "\n  ${C_WARN}[ 0]${C_RESET} Anuluj\n"
    read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz numer: ${C_RESET}")" sel
    [[ "$sel" == "0" || -z "$sel" ]] && return
    [[ ! "$sel" =~ ^[0-9]+$ || $sel -lt 1 || $sel -gt ${#ulist[@]} ]] && return

    local user="${ulist[$((sel-1))]}"

    read -r -p "👉 Liczba dni do dodania [30]: " days
    days=${days:-30}; [[ ! "$days" =~ ^[0-9]+$ ]] && days=30

    local today; today=$(date +%Y-%m-%d)
    local cur_exp; cur_exp=$(xray_get_expiry "$user")
    local base_date="$today"
    [[ -n "$cur_exp" && "$cur_exp" > "$today" ]] && base_date="$cur_exp"
    local new_exp; new_exp=$(date -d "$base_date +$days days" +%Y-%m-%d)

    xray_set_expiry "$user" "$new_exp"
    echo -e "${C_GREEN}✅ Konto '${C_YELLOW}$user${C_GREEN}' odnowione do ${C_CYAN}$new_exp${C_RESET}"
    press_enter
}


update_script() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⬆️ Update FirewallFalcon Manager ---${C_RESET}\n"
    echo -e "${C_DIM}Pobieram najnowszą wersję z GitHub...${C_RESET}\n"

    local backup_file="/usr/local/bin/menu.bak.$(date +%Y%m%d%H%M%S)"
    cp /usr/local/bin/menu "$backup_file" 2>/dev/null
    echo -e "${C_DIM}Backup: $backup_file${C_RESET}"

    if curl -L -o /usr/local/bin/menu "https://raw.githubusercontent.com/taifunss/FirewallFalcon-Manager/main/menu.sh" 2>&1 | tail -3; then
        chmod +x /usr/local/bin/menu
        if bash -n /usr/local/bin/menu 2>/dev/null; then
            echo -e "\n${C_GREEN}✅ Update zakończony pomyślnie!${C_RESET}"
            echo -e "${C_YELLOW}⚠️  Uruchom menu ponownie aby załadować nową wersję.${C_RESET}"
            press_enter
            exit 0
        else
            echo -e "\n${C_RED}❌ Pobrany plik ma błędy składni — przywracam backup.${C_RESET}"
            cp "$backup_file" /usr/local/bin/menu
            chmod +x /usr/local/bin/menu
        fi
    else
        echo -e "\n${C_RED}❌ Nie udało się pobrać pliku.${C_RESET}"
    fi
    press_enter
}


fail2ban_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🛡️ Fail2Ban Manager ---${C_RESET}\n"

        local f2b_status="${C_STATUS_I}Nie zainstalowany${C_RESET}"
        if command -v fail2ban-client &>/dev/null; then
            if systemctl is-active --quiet fail2ban 2>/dev/null; then
                f2b_status="${C_STATUS_A}Aktywny${C_RESET}"
            else
                f2b_status="${C_YELLOW}Zatrzymany${C_RESET}"
            fi
        fi
        echo -e "  ${C_BOLD}${C_WHITE}Status:${C_RESET}  $f2b_status\n"

        if command -v fail2ban-client &>/dev/null; then
            # Pokaż statystyki
            local banned_count
            banned_count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -oP '\d+' | head -1)
            [[ -z "$banned_count" ]] && banned_count="0"
            echo -e "  ${C_DIM}Aktualnie zbanowanych IP: ${C_YELLOW}${banned_count}${C_RESET}\n"

            printf "  ${C_CHOICE}[1]${C_RESET} 📋 Pokaż listę banów\n"
            printf "  ${C_CHOICE}[2]${C_RESET} 🔓 Odbanuj IP\n"
            printf "  ${C_CHOICE}[3]${C_RESET} ⚙️  Edytuj konfigurację (jail.local)\n"
            printf "  ${C_CHOICE}[4]${C_RESET} ▶️  Uruchom Fail2Ban\n"
            printf "  ${C_CHOICE}[5]${C_RESET} ⏹️  Zatrzymaj Fail2Ban\n"
            printf "  ${C_CHOICE}[6]${C_RESET} 🔄 Restart Fail2Ban\n"
            printf "  ${C_DANGER}[7]${C_RESET} 🗑️  Odinstaluj Fail2Ban\n"
        else
            printf "  ${C_CHOICE}[1]${C_RESET} 📦 Zainstaluj Fail2Ban\n"
        fi
        echo -e "\n  ${C_WARN}[0]${C_RESET} ↩️  Powrót\n"

        read -r -p "$(echo -e "${C_PROMPT}  👉 Wybierz: ${C_RESET}")" fc
        case "$fc" in
            1)
                if ! command -v fail2ban-client &>/dev/null; then
                    # Instalacja
                    echo -e "${C_BLUE}📥 Instaluję Fail2Ban...${C_RESET}"
                    apt-get update -qq
                    apt-get install -y fail2ban

                    # Konfiguracja
                    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = iptables-multiport
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF
                    systemctl enable fail2ban
                    systemctl restart fail2ban
                    echo -e "${C_GREEN}✅ Fail2Ban zainstalowany.${C_RESET}"
                    press_enter
                else
                    # Pokaż listę banów
                    clear; show_banner
                    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Lista zbanowanych IP ---${C_RESET}\n"
                    fail2ban-client status sshd 2>/dev/null
                    echo
                    press_enter
                fi
                ;;
            2)
                read -r -p "👉 Podaj IP do odbanowania: " ip_to_unban
                if [[ -n "$ip_to_unban" ]]; then
                    fail2ban-client set sshd unbanip "$ip_to_unban" 2>&1
                    echo -e "${C_GREEN}✅ IP $ip_to_unban odbanowane.${C_RESET}"
                fi
                press_enter
                ;;
            3)
                ${EDITOR:-nano} /etc/fail2ban/jail.local
                systemctl restart fail2ban 2>/dev/null
                ;;
            4) systemctl start fail2ban; echo -e "${C_GREEN}✅ Uruchomiony.${C_RESET}"; press_enter ;;
            5) systemctl stop fail2ban; echo -e "${C_YELLOW}⏹️ Zatrzymany.${C_RESET}"; press_enter ;;
            6) systemctl restart fail2ban; echo -e "${C_GREEN}✅ Zrestartowany.${C_RESET}"; press_enter ;;
            7)
                read -r -p "$(echo -e "${C_WARN}⚠️ Na pewno odinstalować? (t/n): ${C_RESET}")" confirm
                if [[ "$confirm" == "t" ]]; then
                    systemctl stop fail2ban 2>/dev/null
                    systemctl disable fail2ban 2>/dev/null
                    apt-get remove -y fail2ban
                    rm -f /etc/fail2ban/jail.local
                    echo -e "${C_GREEN}✅ Odinstalowany.${C_RESET}"; press_enter
                fi
                ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        export UNINSTALL_MODE="interactive"
        show_banner

        local SEP="${C_BLUE}  ────────────────────────────────────${C_RESET}"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}👤 ZARZĄDZANIE SSH${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[ 1]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 2]${C_RESET}  %-2s %s\n" "✨" "Utwórz użytkownika"     "🗑️ " "Usuń użytkownika"
        printf "  ${C_CHOICE}[ 3]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 4]${C_RESET}  %-2s %s\n" "🔄" "Odnów konto"            "✏️ " "Edytuj użytkownika"
        printf "  ${C_CHOICE}[ 5]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 6]${C_RESET}  %-2s %s\n" "🔒" "Zablokuj konto"         "🔓" "Odblokuj konto"
        printf "  ${C_CHOICE}[ 7]${C_RESET}  %-2s %-26s  ${C_CHOICE}[ 8]${C_RESET}  %-2s %s\n" "📱" "Konfiguracja klienta"   "📊" "Pasmo użytkownika"
        printf "  ${C_CHOICE}[ 9]${C_RESET}  %-2s %s\n"                                       "📅" "Zaplanowane aktywacje"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}📊 PODGLĄD I STATYSTYKI${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[10]${C_RESET}  %-2s %-26s  ${C_CHOICE}[11]${C_RESET}  %-2s %s\n" "🗂️ " "Lista kont SSH"         "📋" "Aktywne sesje"
        printf "  ${C_CHOICE}[12]${C_RESET}  %-2s %-26s  ${C_CHOICE}[13]${C_RESET}  %-2s %s\n" "📈" "Zużycie danych"         "🚫" "Historia banów"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}🌐 VPN I PROTOKOŁY${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[14]${C_RESET}  %-2s %-26s  ${C_CHOICE}[15]${C_RESET}  %-2s %s\n" "⚡" "Xray/V2Ray Manager"     "🔌" "Menedżer protokołów"
        printf "  ${C_CHOICE}[16]${C_RESET}  %-2s %-26s  ${C_CHOICE}[17]${C_RESET}  %-2s %s\n" "📈" "Monitor ruchu"          "🚫" "Blokuj torrenty (P2P)"

        echo
        echo -e "  ${C_TITLE}${C_BOLD}⚙️  SYSTEM${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[18]${C_RESET}  %-2s %-26s  ${C_CHOICE}[19]${C_RESET}  %-2s %s\n" "💾" "Backup & Przywróć"      "🔄" "Auto-restart"
        printf "  ${C_CHOICE}[20]${C_RESET}  %-2s %-26s  ${C_CHOICE}[21]${C_RESET}  %-2s %s\n" "🎨" "Banner SSH"             "☁️ " "Domena CloudFlare"
        printf "  ${C_CHOICE}[22]${C_RESET}  %-2s %-26s  ${C_CHOICE}[23]${C_RESET}  %-2s %s\n" "🔍" "Status + Speedtest"     "🧹" "Wyczyść wygasłe"

        echo
        echo -e "  ${C_DANGER}${C_BOLD}🔥 STREFA NIEBEZPIECZNA${C_RESET}"
        echo -e "$SEP"
        printf "  ${C_CHOICE}[24]${C_RESET}  %-2s %-26s  ${C_DANGER}[99]${C_RESET}  %-2s %s\n" "⬆️ " "Update skryptu"          "🗑️ " "Odinstaluj skrypt"
        printf "  ${C_WARN}[ 0]${C_RESET}  %-2s %s\n"                                          "🚪" "Wyjście"
        echo

        if ! read -r -p "$(echo -e ${C_PROMPT}"  👉 Wybierz opcję: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) create_user; press_enter ;;
            2) delete_user; press_enter ;;
            3) renew_user; press_enter ;;
            4) edit_user; press_enter ;;
            5) lock_user; press_enter ;;
            6) unlock_user; press_enter ;;
            7) client_config_menu; press_enter ;;
            8) view_user_bandwidth; press_enter ;;
            9) show_scheduled_activations; press_enter ;;

            10) list_all_accounts; press_enter ;;
            11) list_active_sessions; press_enter ;;
            12) show_data_usage; press_enter ;;
            13) show_ban_history; press_enter ;;

            14) xray_menu ;;
            15) protocol_menu ;;
            16) traffic_monitor_menu ;;
            17) torrent_block_menu ;;

            18) backup_menu ;;
            19) auto_reboot_menu ;;
            20) ssh_banner_menu ;;
            21) dns_menu; press_enter ;;
            22) show_service_status ;;
            23) cleanup_expired; press_enter ;;

            24) update_script ;;
            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}

if [[ "$1" == "--install-setup" ]]; then
    initial_setup
    exit 0
fi

require_interactive_terminal
sync_runtime_components_if_needed
main_menu
!/bin/bash

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# Premium Color Palette
C_RED=$'\033[38;5;196m'      # Bright Red
C_GREEN=$'\033[38;5;46m'     # Neon Green
C_YELLOW=$'\033[38;5;226m'   # Bright Yellow
C_BLUE=$'\033[38;5;39m'      # Deep Sky Blue
C_PURPLE=$'\033[38;5;135m'   # Light Purple
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;208m'   # Orange

# Semantic Aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

DB_DIR="/etc/firewallfalcon"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"
BADVPN_SERVICE_FILE="/etc/systemd/system/badvpn.service"
BADVPN_BUILD_DIR="/root/badvpn-build"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"
SSL_CERT_DIR="/etc/firewallfalcon/ssl"
SSL_CERT_FILE="$SSL_CERT_DIR/firewallfalcon.pem"
SSL_CERT_CHAIN_FILE="$SSL_CERT_DIR/firewallfalcon.crt"
SSL_CERT_KEY_FILE="$SSL_CERT_DIR/firewallfalcon.key"
EDGE_CERT_INFO_FILE="$DB_DIR/edge_cert.conf"
NGINX_PORTS_FILE="$DB_DIR/nginx_ports.conf"
EDGE_PUBLIC_HTTP_PORT="80"
EDGE_PUBLIC_TLS_PORT="443"
NGINX_INTERNAL_HTTP_PORT="8880"
NGINX_INTERNAL_TLS_PORT="8443"
HAPROXY_INTERNAL_DECRYPT_PORT="10443"
DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="/etc/firewallfalcon/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"
UDP_CUSTOM_DIR="/root/udp"
UDP_CUSTOM_SERVICE_FILE="/etc/systemd/system/udp-custom.service"
SSH_BANNER_FILE="/etc/bannerssh"
FALCONPROXY_SERVICE_FILE="/etc/systemd/system/falconproxy.service"
FALCONPROXY_BINARY="/usr/local/bin/falconproxy"
FALCONPROXY_CONFIG_FILE="$DB_DIR/falconproxy_config.conf"
LIMITER_SCRIPT="/usr/local/bin/firewallfalcon-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/firewallfalcon-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
STATS_DIR="$DB_DIR/stats"
BANDWIDTH_SCRIPT="/usr/local/bin/firewallfalcon-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/firewallfalcon-bandwidth.service"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/firewallfalcon-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/firewallfalcon-login-info.sh"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/firewallfalcon.conf"

# --- ZiVPN Variables ---
ZIVPN_DIR="/etc/zivpn"
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE_FILE="/etc/systemd/system/zivpn.service"
ZIVPN_CONFIG_FILE="$ZIVPN_DIR/config.json"
ZIVPN_CERT_FILE="$ZIVPN_DIR/zivpn.crt"
ZIVPN_KEY_FILE="$ZIVPN_DIR/zivpn.key"

DESEC_TOKEN="V55cFY8zTictLCPfviiuX5DHjs15"
DESEC_DOMAIN="manager.firewallfalcon.qzz.io"
# Jeśli istnieje plik z tokenem, wczytaj z niego (nadpisuje powyższe)
_DESEC_CONF="/etc/firewallfalcon/desec.conf"
if [[ -f "$_DESEC_CONF" ]]; then
    source "$_DESEC_CONF"
fi

SELECTED_USER=""
UNINSTALL_MODE="interactive"
BANNER_CACHE_TTL=15
BANNER_CACHE_TS=0
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE=""
BANNER_CACHE_CPU_LOAD=""
BANNER_CACHE_ONLINE_USERS=0
BANNER_CACHE_TOTAL_USERS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
FF_USERS_GROUP="ffusers"
declare -A SSH_SESSION_COUNTS=()
declare -A SSH_SESSION_PIDS=()

if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
   exit 1
fi

# Mandatory Dependency Check (Added jq and curl)
# Bezpieczna aktualizacja linii w DB — odporna na znaki specjalne w hasłach (/,&,\)
