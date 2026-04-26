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

# 3. Setup HTTPS
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

# 4. Deploy Leantime
echo "Deploying Leantime Demo..."
kadmin apply -f kubernetes/apps/leantime/demo-standalone.yaml

# 5. Wait for Readiness
echo "Waiting for MariaDB to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime-mariadb

echo "Waiting for Mailpit to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime-mailpit

echo "Waiting for Leantime to be ready..."
kadmin wait --for=condition=available --timeout=300s deployment/leantime

# 6. Smoke Test
if command -v curl >/dev/null 2>&1; then
    echo "Running HTTPS smoke test..."
    curl -skI https://localhost >/dev/null
fi

echo ""
echo "===================================================="
echo "Demo is ready! (Isolated via k3s-admin user)"
echo "Access at: https://localhost"
echo "Mail inbox (demo SMTP sink): http://localhost:30082"
echo ""
echo "If onboarding redirects you to login without setting a password,"
echo "open Mailpit and use the invite/reset email link."
echo "===================================================="
