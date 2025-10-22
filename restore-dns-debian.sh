#!/usr/bin/env bash
set -Eeuo pipefail

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

restore_dns() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "⚠️  No DNS backup found at $BACKUP_FILE." >&2
        echo "Use resolvectl or /etc/resolv.conf to restore DNS manually."
        exit 1
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
        echo "⚠️  Backup missing DNS entries. Reverting to DHCP." >&2
        resolvectl revert "$IFACE" >/dev/null 2>&1 || true
    fi
    resolvectl flush-caches >/dev/null 2>&1 || true
    rm -f "$BACKUP_FILE"
    echo "✅ DNS restored."
}

main() {
    assert_root
    require_command resolvectl
    restore_dns
}

main "$@"
