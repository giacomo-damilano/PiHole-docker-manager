#!/usr/bin/env bash
set -Eeuo pipefail

PIHOLE_IP=${PIHOLE_IP:-"192.168.1.10"}
BACKUP_DNS=${BACKUP_DNS:-"8.8.8.8"}
COMPOSE_FILE=${COMPOSE_FILE:-"docker-compose.yml"}
MAX_WAIT=${MAX_WAIT:-60}
WAIT_INTERVAL=${WAIT_INTERVAL:-5}
BACKUP_DIR=${XDG_STATE_HOME:-"$HOME/.local/state"}/pihole-docker-manager
BACKUP_FILE="$BACKUP_DIR/old_dns_linux.env"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Required command '$1' not found in PATH." >&2
        exit 1
    fi
}

assert_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        echo "❌ This script must be run with root privileges. Use sudo." >&2
        exit 1
    fi
}

wait_for_docker() {
    local elapsed=0
    echo "Checking if Docker daemon is running..."
    until docker info >/dev/null 2>&1; do
        if (( elapsed >= MAX_WAIT )); then
            echo "❌ Docker did not become ready within ${MAX_WAIT}s." >&2
            exit 1
        fi
        printf 'Waiting for Docker to start... (%s/%s s)\n' "$elapsed" "$MAX_WAIT"
        sleep "$WAIT_INTERVAL"
        ((elapsed += WAIT_INTERVAL))
    done
    echo "✅ Docker is running and ready."
}

active_connection() {
    local connection
    connection=$(nmcli -t -f NAME,DEVICE connection show --active | head -n1 | cut -d: -f1)
    if [[ -z "$connection" ]]; then
        echo "❌ Could not determine an active NetworkManager connection." >&2
        exit 1
    fi
    printf '%s\n' "$connection"
}

read_current_dns() {
    local connection=$1
    local line dns=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line=${line//;/ }
        line=${line//,/ }
        line=${line//$'\t'/ }
        line=$(echo "$line" | awk '{for (i=1;i<=NF;++i) if ($i!="") printf "%s%s", (i>1?" ":""), $i}')
        [[ -z "$line" ]] && continue
        if [[ -z "$dns" ]]; then
            dns="$line"
        else
            dns="$dns $line"
        fi
    done < <(nmcli -g ipv4.dns connection show "$connection")
    printf '%s\n' "$dns"
}

store_backup() {
    local mode=$1
    local dns=$2
    local connection=$3
    mkdir -p "$BACKUP_DIR"
    {
        printf 'MODE=%q\n' "$mode"
        printf 'DNS=%q\n' "$dns"
        printf 'CONNECTION=%q\n' "$connection"
    } > "$BACKUP_FILE"
}

restore_dns() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "⚠️  No DNS backup found to restore." >&2
        return
    fi
    # shellcheck disable=SC1090
    source "$BACKUP_FILE"
    echo "Restoring previous DNS settings..."
    if [[ "${MODE:-}" == "dhcp" ]]; then
        if ! nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns no; then
            echo "⚠️  Failed to switch ${CONNECTION} back to auto DNS." >&2
        fi
        if ! nmcli connection modify "$CONNECTION" ipv4.dns ""; then
            echo "⚠️  Failed to clear static DNS entries." >&2
        fi
    elif [[ -n "${DNS:-}" ]]; then
        if ! nmcli connection modify "$CONNECTION" ipv4.dns "$DNS"; then
            echo "⚠️  Failed to restore DNS entries ($DNS)." >&2
        else
            nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns yes >/dev/null 2>&1 || true
        fi
    else
        echo "⚠️  Backup file missing DNS entries, reverting to DHCP." >&2
        nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns no >/dev/null 2>&1 || true
        nmcli connection modify "$CONNECTION" ipv4.dns "" >/dev/null 2>&1 || true
    fi
    nmcli connection up "$CONNECTION" >/dev/null 2>&1 || true
    rm -f "$BACKUP_FILE"
    echo "✅ DNS restored."
}

main() {
    assert_root
    require_command docker
    require_command nmcli

    wait_for_docker

    local connection
    connection=$(active_connection)
    echo "Active connection: $connection"

    local current_dns
    current_dns=$(read_current_dns "$connection")

    if [[ -z "$current_dns" ]]; then
        echo "No static DNS configured. Assuming DHCP."
        store_backup dhcp "" "$connection"
    else
        echo "Backing up current DNS: $current_dns"
        store_backup static "$current_dns" "$connection"
    fi

    trap restore_dns EXIT

    echo "Starting Pi-hole container..."
    docker compose -f "$COMPOSE_FILE" up -d

    echo "Setting DNS to use Pi-hole ($PIHOLE_IP) with backup ($BACKUP_DNS)..."
    nmcli connection modify "$connection" ipv4.dns "$PIHOLE_IP $BACKUP_DNS"
    nmcli connection modify "$connection" ipv4.ignore-auto-dns yes
    nmcli connection up "$connection" >/dev/null 2>&1 || true
    echo "✅ DNS updated."

    echo "Pi-hole is running. Waiting for container to stop (Ctrl+C to exit)..."
    while docker ps --filter "name=pihole" --format '{{.Names}}' | grep -q '.'; do
        sleep 10
    done

    echo "Pi-hole container stopped."
    restore_dns
    trap - EXIT
}

main "$@"
