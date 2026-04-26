#!/usr/bin/env bash
set -euo pipefail

# Calculate project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# 1. Host Preparation
if ! command -v ansible >/dev/null 2>&1; then
    echo "Ansible not found. Installing..."
    sudo apt update && sudo apt install -y ansible
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required but not installed."
    exit 1
fi

# 2. Provision K3s & Isolated User
echo "Provisioning k3s-admin user and cluster..."
ansible-playbook -K -i ansible/inventory.ini ansible/setup_k3s_demo.yml

# Helper to run kubectl as the isolated user
kadmin() {
    sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

# 3. Setup Local HTTPS
echo "Generating self-signed certificate for localhost..."
mkdir -p .certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout .certs/tls.key -out .certs/tls.crt \
    -subj "/CN=localhost/O=LeantimeDemo" 2>/dev/null
sudo chown k3s-admin:k3s .certs/tls.*

echo "Creating Kubernetes TLS secret..."
kadmin create secret tls leantime-tls \
    --cert=.certs/tls.crt \
    --key=.certs/tls.key \
    --dry-run=client -o yaml | kadmin apply -f -

if [ ! -f kubernetes/apps/leantime/demo-standalone.yaml ]; then
    echo "Missing manifest: kubernetes/apps/leantime/demo-standalone.yaml"
    exit 1
fi

# 4. Cloudflare Tunnel Setup
echo "Checking for Cloudflare Tunnel Token..."
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    echo "----------------------------------------------------"
    echo "INFO: CLOUDFLARE_TUNNEL_TOKEN environment variable is not set."
    echo "Cloudflare Tunnel will not be deployed."
    echo "To deploy the tunnel, run:"
    echo "  export CLOUDFLARE_TUNNEL_TOKEN=<your-token>"
    echo "  ./scripts/bootstrap.sh"
    echo "----------------------------------------------------"
else
    if [ ! -f kubernetes/platform/cloudflared/kustomization.yaml ]; then
        echo "Missing kustomization: kubernetes/platform/cloudflared/kustomization.yaml"
        exit 1
    fi

    echo "Creating Cloudflare Tunnel Token secret..."
    kadmin create secret generic cloudflare-tunnel-token \
        -n kube-system \
        --from-literal=token="$CLOUDFLARE_TUNNEL_TOKEN" \
        --dry-run=client -o yaml | kadmin apply -f -

    echo "Deploying Cloudflare Tunnel..."
    kadmin apply -k kubernetes/platform/cloudflared

    echo "Waiting for Cloudflare Tunnel to be ready..."
    kadmin wait --for=condition=available --timeout=300s deployment/cloudflared -n kube-system
fi

# 5. Deploy Leantime
echo "Deploying Leantime Demo..."
kadmin apply -f kubernetes/apps/leantime/demo-standalone.yaml

# 6. Wait for Readiness
echo "Waiting for MariaDB to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime-mariadb

echo "Waiting for Mailpit to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime-mailpit

echo "Waiting for Leantime to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime

# 7. Smoke Tests
if command -v curl >/dev/null 2>&1; then
    echo "Running HTTPS smoke test..."
    curl -skI https://localhost >/dev/null

    echo "Running Mailpit smoke test..."
    curl -sfI http://localhost:30082 >/dev/null
fi

echo ""
echo "===================================================="
echo "Demo is ready! (Isolated via k3s-admin user)"
echo "Local Access: https://localhost"
echo "Mail inbox (demo SMTP sink): http://localhost:30082"
echo ""
echo "If onboarding redirects you to login before password setup,"
echo "open Mailpit and use the invite/reset link."
if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    echo ""
    echo "Cloudflare tunnel is deployed."
    echo "This demo bootstrap does not configure platform SSO."
    echo "For Authentik-based production SSO, use the GitOps path in README.md."
fi
echo "===================================================="
