#!/usr/bin/env bash
set -Eeuo pipefail

PIHOLE_IP=${PIHOLE_IP:-"192.168.1.10"}
BACKUP_DNS=${BACKUP_DNS:-"8.8.8.8"}
COMPOSE_FILE=${COMPOSE_FILE:-"docker-compose.yml"}
MAX_WAIT=${MAX_WAIT:-60}
WAIT_INTERVAL=${WAIT_INTERVAL:-5}
BACKUP_DIR=${XDG_STATE_HOME:-"$HOME/.local/state"}/pihole-docker-manager
BACKUP_FILE="$BACKUP_DIR/old_dns_debian.env"

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

default_interface() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/ default / {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [[ -z "$iface" ]]; then
        echo "❌ Could not determine the default network interface." >&2
        exit 1
    fi
    printf '%s\n' "$iface"
}

extract_value() {
    sed -n 's/.*: //p' | tr -s ' ' ' '
}

read_current_dns() {
    local iface=$1
    local dns
    dns=$(resolvectl dns "$iface" | extract_value | tr -d '\n')
    dns=${dns# }
    dns=${dns% }
    printf '%s\n' "$dns"
}

read_current_domains() {
    local iface=$1
    local domains
    domains=$(resolvectl domain "$iface" | extract_value | tr -d '\n')
    domains=${domains# }
    domains=${domains% }
    printf '%s\n' "$domains"
}

store_backup() {
    local mode=$1
    local dns=$2
    local domains=$3
    local iface=$4
    mkdir -p "$BACKUP_DIR"
    {
        printf 'MODE=%q\n' "$mode"
        printf 'DNS=%q\n' "$dns"
        printf 'DOMAINS=%q\n' "$domains"
        printf 'IFACE=%q\n' "$iface"
    } > "$BACKUP_FILE"
}

restore_dns() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "⚠️  No DNS backup found to restore." >&2
        return
    fi
    # shellcheck disable=SC1090
    source "$BACKUP_FILE"
    echo "Restoring DNS configuration for interface '$IFACE'..."
    if [[ "${MODE:-}" == "dhcp" ]]; then
        resolvectl revert "$IFACE" >/dev/null 2>&1 || true
    elif [[ -n "${DNS:-}" ]]; then
        if ! resolvectl dns "$IFACE" $DNS; then
            echo "⚠️  Failed to restore DNS entries ($DNS)." >&2
        fi
        if [[ -n "${DOMAINS:-}" ]]; then
            resolvectl domain "$IFACE" $DOMAINS >/dev/null 2>&1 || true
        fi
    else
        echo "⚠️  Backup file missing DNS entries, reverting to DHCP." >&2
        resolvectl revert "$IFACE" >/dev/null 2>&1 || true
    fi
    resolvectl flush-caches >/dev/null 2>&1 || true
    rm -f "$BACKUP_FILE"
    echo "✅ DNS restored."
}

main() {
    assert_root
    require_command docker
    require_command resolvectl
    require_command ip

    wait_for_docker

    local iface
    iface=$(default_interface)
    echo "Using default interface: $iface"

    local current_dns current_domains
    current_dns=$(read_current_dns "$iface")
    current_domains=$(read_current_domains "$iface")

    if [[ -z "$current_dns" ]]; then
        echo "No static DNS configured. Assuming DHCP."
        store_backup dhcp "" "$current_domains" "$iface"
    else
        echo "Backing up current DNS: $current_dns"
        store_backup static "$current_dns" "$current_domains" "$iface"
    fi

    trap restore_dns EXIT

    echo "Starting Pi-hole container..."
    docker compose -f "$COMPOSE_FILE" up -d

    echo "Setting DNS to use Pi-hole ($PIHOLE_IP) with backup ($BACKUP_DNS)..."
    resolvectl dns "$iface" $PIHOLE_IP $BACKUP_DNS
    resolvectl domain "$iface" ~.
    resolvectl flush-caches >/dev/null 2>&1 || true
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
