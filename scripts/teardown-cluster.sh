#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Tearing down K3s cluster..."
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-uninstall.sh
else
    echo "K3s uninstall script not found. Is K3s installed?"
fi

if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-agent-uninstall.sh
fi

echo "Removing demo management account and permissions..."
sudo rm -f /etc/sudoers.d/k3s-admin || true
if id k3s-admin >/dev/null 2>&1; then
    # Ensure no lingering processes keep the account/group locked.
    sudo pkill -u k3s-admin || true
    sleep 1
    sudo deluser --remove-home k3s-admin || true
fi
if getent group k3s >/dev/null 2>&1; then
    sudo delgroup k3s || true
fi

echo "Removing demo TLS artifacts..."
rm -rf "${PROJECT_ROOT}/.certs"

echo "Cleanup complete."
