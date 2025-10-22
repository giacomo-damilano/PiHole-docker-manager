#!/usr/bin/env bash
set -Eeuo pipefail

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

restore_dns() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "⚠️  No DNS backup found at $BACKUP_FILE." >&2
        echo "Use NetworkManager or your router settings to restore DNS manually."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$BACKUP_FILE"

    echo "Restoring DNS configuration saved for connection '$CONNECTION'..."
    if [[ "${MODE:-}" == "dhcp" ]]; then
        nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns no >/dev/null 2>&1 || true
        nmcli connection modify "$CONNECTION" ipv4.dns "" >/dev/null 2>&1 || true
    elif [[ -n "${DNS:-}" ]]; then
        if ! nmcli connection modify "$CONNECTION" ipv4.dns "$DNS"; then
            echo "⚠️  Failed to restore DNS entries ($DNS)." >&2
        else
            nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns yes >/dev/null 2>&1 || true
        fi
    else
        echo "⚠️  Backup missing DNS entries. Reverting to DHCP." >&2
        nmcli connection modify "$CONNECTION" ipv4.ignore-auto-dns no >/dev/null 2>&1 || true
        nmcli connection modify "$CONNECTION" ipv4.dns "" >/dev/null 2>&1 || true
    fi
    nmcli connection up "$CONNECTION" >/dev/null 2>&1 || true
    rm -f "$BACKUP_FILE"
    echo "✅ DNS restored."
}

main() {
    assert_root
    require_command nmcli
    restore_dns
}

main "$@"
