#!/usr/bin/env bash
set -Eeuo pipefail

PIHOLE_IP=${PIHOLE_IP:-"192.168.1.10"}
BACKUP_DNS=${BACKUP_DNS:-"8.8.8.8"}
COMPOSE_FILE=${COMPOSE_FILE:-"docker-compose.yml"}
MAX_WAIT=${MAX_WAIT:-60}
WAIT_INTERVAL=${WAIT_INTERVAL:-5}
BACKUP_DIR="$HOME/Library/Application Support/PiHoleDockerManager"
BACKUP_FILE="$BACKUP_DIR/old_dns_macos.env"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Required command '$1' not found in PATH." >&2
        exit 1
    fi
}

assert_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        echo "❌ This script must be run with sudo on macOS." >&2
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

primary_device() {
    local device
    device=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
    if [[ -z "$device" ]]; then
        echo "❌ Unable to determine primary network interface." >&2
        exit 1
    fi
    printf '%s\n' "$device"
}

service_from_device() {
    local device=$1
    local port_line service
    while IFS= read -r line; do
        if [[ $line == Hardware\ Port:* ]]; then
            port_line=${line#Hardware Port: }
        elif [[ $line == Device:* ]]; then
            if [[ ${line#Device: } == "$device" ]]; then
                service=$port_line
                break
            fi
        fi
    done < <(networksetup -listallhardwareports)

    if [[ -z "$service" ]]; then
        echo "❌ Could not map device $device to a network service." >&2
        exit 1
    fi
    printf '%s\n' "$service"
}

read_current_dns() {
    local service=$1 output
    if ! output=$(networksetup -getdnsservers "$service" 2>&1); then
        echo "❌ Failed to query DNS servers for $service." >&2
        exit 1
    fi
    if [[ $output == "There aren't any DNS Servers set on $service." ]]; then
        printf ''
    else
        printf '%s\n' "$output" | awk 'NF' | paste -sd ' ' -
    fi
}

read_search_domains() {
    local service=$1 output
    if ! output=$(networksetup -getsearchdomains "$service" 2>&1); then
        echo "❌ Failed to query search domains for $service." >&2
        exit 1
    fi
    if [[ $output == "There aren't any Search Domains set on $service." ]]; then
        printf ''
    else
        printf '%s\n' "$output" | awk 'NF' | paste -sd ' ' -
    fi
}

store_backup() {
    local mode=$1 dns=$2 search=$3 service=$4
    mkdir -p "$BACKUP_DIR"
    {
        printf 'MODE=%q\n' "$mode"
        printf 'DNS=%q\n' "$dns"
        printf 'SEARCH=%q\n' "$search"
        printf 'SERVICE=%q\n' "$service"
    } > "$BACKUP_FILE"
}

set_dns_servers() {
    local service=$1
    shift
    if [[ $# -eq 0 ]]; then
        networksetup -setdnsservers "$service" Empty
    else
        networksetup -setdnsservers "$service" "$@"
    fi
}

set_search_domains() {
    local service=$1
    shift
    if [[ $# -eq 0 ]]; then
        networksetup -setsearchdomains "$service" Empty
    else
        networksetup -setsearchdomains "$service" "$@"
    fi
}

restore_dns() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "⚠️  No DNS backup found to restore." >&2
        return
    fi
    # shellcheck disable=SC1090
    source "$BACKUP_FILE"
    echo "Restoring DNS configuration for service '$SERVICE'..."
    if [[ "${MODE:-}" == "dhcp" ]]; then
        set_dns_servers "$SERVICE"
        set_search_domains "$SERVICE"
    elif [[ -n "${DNS:-}" ]]; then
        IFS=' ' read -r -a dns_array <<< "${DNS}" || true
        set_dns_servers "$SERVICE" "${dns_array[@]}"
        if [[ -n "${SEARCH:-}" ]]; then
            IFS=' ' read -r -a search_array <<< "${SEARCH}" || true
            set_search_domains "$SERVICE" "${search_array[@]}"
        else
            set_search_domains "$SERVICE"
        fi
    else
        echo "⚠️  Backup missing DNS entries. Clearing DNS settings." >&2
        set_dns_servers "$SERVICE"
        set_search_domains "$SERVICE"
    fi
    rm -f "$BACKUP_FILE"
    echo "✅ DNS restored."
}

main() {
    assert_root
    require_command docker
    require_command networksetup
    require_command route

    wait_for_docker

    local device service current_dns search_domains
    device=$(primary_device)
    service=$(service_from_device "$device")
    echo "Using network service: $service (device $device)"

    current_dns=$(read_current_dns "$service")
    search_domains=$(read_search_domains "$service")

    if [[ -z "$current_dns" ]]; then
        echo "No static DNS configured. Assuming DHCP."
        store_backup dhcp "" "$search_domains" "$service"
    else
        echo "Backing up current DNS: $current_dns"
        store_backup static "$current_dns" "$search_domains" "$service"
    fi

    trap restore_dns EXIT

    echo "Starting Pi-hole container..."
    docker compose -f "$COMPOSE_FILE" up -d

    echo "Setting DNS to use Pi-hole ($PIHOLE_IP) with backup ($BACKUP_DNS)..."
    IFS=' ' read -r -a backup_array <<< "$BACKUP_DNS" || true
    set_dns_servers "$service" "$PIHOLE_IP" "${backup_array[@]}"
    set_search_domains "$service"
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
