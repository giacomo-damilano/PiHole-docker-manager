#!/usr/bin/env bash
set -Eeuo pipefail

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
        echo "⚠️  No DNS backup found at $BACKUP_FILE." >&2
        echo "Use System Settings → Network to restore DNS manually."
        exit 1
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
    require_command networksetup
    restore_dns
}

main "$@"
