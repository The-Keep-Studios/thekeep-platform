#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PRODUCTION_LOCK_FILE="${PROJECT_ROOT}/.production-lock"

usage() {
    cat <<'EOF'
Usage:
  TEARDOWN_CONFIRM=destroy-k3s ./teardown-cluster.sh --force

Extra safety for production-like clusters:
  ALLOW_PRODUCTION_TEARDOWN=true TEARDOWN_CONFIRM=destroy-k3s ./teardown-cluster.sh --force

Optional local lock file:
  touch .production-lock
  # blocks teardown unless ALLOW_PRODUCTION_TEARDOWN=true
EOF
}

if [ "${1:-}" != "--force" ]; then
    echo "Refusing teardown without explicit --force flag."
    usage
    exit 1
fi

if [ "${TEARDOWN_CONFIRM:-}" != "destroy-k3s" ]; then
    echo "Refusing teardown: set TEARDOWN_CONFIRM=destroy-k3s"
    usage
    exit 1
fi

is_production_like=false
if id k3s-admin >/dev/null 2>&1 && [ -x /usr/local/bin/kubectl ]; then
    if sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config \
        kubectl get ns identity gitlab wisemapping monitoring >/dev/null 2>&1; then
        is_production_like=true
    fi
fi

if [ -f "${PRODUCTION_LOCK_FILE}" ] || [ "${is_production_like}" = "true" ]; then
    if [ "${ALLOW_PRODUCTION_TEARDOWN:-false}" != "true" ]; then
        echo "Refusing teardown: production safeguards are active."
        echo "Set ALLOW_PRODUCTION_TEARDOWN=true only for intentional full cluster destruction."
        usage
        exit 1
    fi
fi

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
    for _ in 1 2 3 4 5; do
        if ! pgrep -u k3s-admin >/dev/null 2>&1; then
            break
        fi
        sudo pkill -9 -u k3s-admin || true
        sleep 1
    done
    sudo deluser --remove-home k3s-admin || true
fi
if ! id k3s-admin >/dev/null 2>&1 && getent group k3s >/dev/null 2>&1; then
    sudo delgroup k3s || true
fi

echo "Removing demo TLS artifacts..."
rm -rf "${PROJECT_ROOT}/.certs"

echo "Cleanup complete."
