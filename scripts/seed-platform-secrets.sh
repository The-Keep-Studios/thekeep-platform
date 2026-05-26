#!/usr/bin/env bash
# DEPRECATED: Use ansible-playbook with platform roles instead.
# See README.md for the new Ansible-first workflow.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

if [ ! -f "${SCRIPT_DIR}/production.env" ]; then
  echo "Missing ${SCRIPT_DIR}/production.env"
  echo "Create it from scripts/production.env.example first."
  exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/production.env"

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required variable: ${name}"
    exit 1
  fi
}

AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.thekeepstudios.com}"
# GITLAB_URL="${GITLAB_URL:-https://gitlab.thekeepstudios.com}"
MONITORING_ENABLED="${MONITORING_ENABLED:-true}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"

LEAN_OIDC_ENABLE="${LEAN_OIDC_ENABLE:-false}"
LEAN_OIDC_CLIENT_ID="${LEAN_OIDC_CLIENT_ID:-}"
LEAN_OIDC_CLIENT_SECRET="${LEAN_OIDC_CLIENT_SECRET:-}"
LEAN_OIDC_PROVIDER_URL="${LEAN_OIDC_PROVIDER_URL:-}"
LEAN_OIDC_CREATE_USER="${LEAN_OIDC_CREATE_USER:-true}"
LEAN_OIDC_DEFAULT_ROLE="${LEAN_OIDC_DEFAULT_ROLE:-20}"
LEAN_OIDC_SCOPES="${LEAN_OIDC_SCOPES:-openid,profile,email}"
LEAN_DISABLE_LOGIN_FORM="${LEAN_DISABLE_LOGIN_FORM:-false}"

OIDC_ENABLED="${OIDC_ENABLED:-false}"
OIDC_LABEL="${OIDC_LABEL:-Authentik}"
OIDC_ISSUER="${OIDC_ISSUER:-}"
OIDC_UID_FIELD="${OIDC_UID_FIELD:-sub}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-}"

WISEMAPPING_OAUTH_ENABLED="${WISEMAPPING_OAUTH_ENABLED:-false}"
WISEMAPPING_SPRING_PROFILES_ACTIVE="${WISEMAPPING_SPRING_PROFILES_ACTIVE:-}"
OAUTH_GOOGLE_CLIENT_ID="${OAUTH_GOOGLE_CLIENT_ID:-}"
OAUTH_GOOGLE_CLIENT_SECRET="${OAUTH_GOOGLE_CLIENT_SECRET:-}"
OAUTH_GOOGLE_ISSUER_URI="${OAUTH_GOOGLE_ISSUER_URI:-}"
WISEMAPPING_MAIL_ENABLED="${WISEMAPPING_MAIL_ENABLED:-false}"
WISEMAPPING_MAIL_SENDER_EMAIL="${WISEMAPPING_MAIL_SENDER_EMAIL:-}"
WISEMAPPING_MAIL_HOST="${WISEMAPPING_MAIL_HOST:-}"
WISEMAPPING_MAIL_PORT="${WISEMAPPING_MAIL_PORT:-587}"
WISEMAPPING_MAIL_USERNAME="${WISEMAPPING_MAIL_USERNAME:-}"
WISEMAPPING_MAIL_PASSWORD="${WISEMAPPING_MAIL_PASSWORD:-}"

require_var AUTHENTIK_SECRET_KEY
require_var AUTHENTIK_POSTGRES_PASSWORD
require_var AUTHENTIK_BOOTSTRAP_EMAIL
require_var AUTHENTIK_BOOTSTRAP_PASSWORD
require_var LEANTIME_DB_ROOT_PASSWORD
require_var LEANTIME_DB_PASSWORD
# require_var GITLAB_ROOT_PASSWORD
# require_var GITLAB_ROOT_EMAIL
require_var WISEMAPPING_POSTGRES_PASSWORD
require_var WISEMAPPING_JWT_SECRET
require_var WISEMAPPING_OAUTH_TOKEN_SECRET
require_var CLOUDFLARE_TUNNEL_TOKEN

if [ "${LEAN_OIDC_ENABLE}" = "true" ]; then
  require_var LEAN_OIDC_CLIENT_ID
  require_var LEAN_OIDC_CLIENT_SECRET
  require_var LEAN_OIDC_PROVIDER_URL
fi

if [ "${OIDC_ENABLED}" = "true" ]; then
  require_var OIDC_ISSUER
  require_var OIDC_CLIENT_ID
  require_var OIDC_CLIENT_SECRET
fi

if [ "${WISEMAPPING_OAUTH_ENABLED}" = "true" ]; then
  require_var OAUTH_GOOGLE_CLIENT_ID
  require_var OAUTH_GOOGLE_CLIENT_SECRET
  require_var OAUTH_GOOGLE_ISSUER_URI
  WISEMAPPING_SPRING_PROFILES_ACTIVE="${WISEMAPPING_SPRING_PROFILES_ACTIVE:-oidc}"
fi

if [ "${WISEMAPPING_MAIL_ENABLED}" = "true" ]; then
  require_var WISEMAPPING_MAIL_SENDER_EMAIL
  require_var WISEMAPPING_MAIL_HOST
  require_var WISEMAPPING_MAIL_PORT
  require_var WISEMAPPING_MAIL_USERNAME
  require_var WISEMAPPING_MAIL_PASSWORD
fi

if [ "${MONITORING_ENABLED}" = "true" ]; then
  require_var GRAFANA_ADMIN_USER
  require_var GRAFANA_ADMIN_PASSWORD
fi

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

if ! kadmin get nodes >/dev/null 2>&1; then
  echo "Cannot reach cluster as k3s-admin."
  echo "Bootstrap k3s first via ansible/setup_k3s_production.yml."
  exit 1
fi

echo "Ensuring required namespaces..."
kadmin create namespace identity --dry-run=client -o yaml | kadmin apply -f -
# kadmin create namespace gitlab --dry-run=client -o yaml | kadmin apply -f -
kadmin create namespace wisemapping --dry-run=client -o yaml | kadmin apply -f -
kadmin create namespace monitoring --dry-run=client -o yaml | kadmin apply -f -

echo "Applying Authentik secret material..."
kadmin create secret generic authentik-secrets -n identity \
  --from-literal=AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}" \
  --from-literal=AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD}" \
  --from-literal=AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL}" \
  --from-literal=AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD}" \
  --dry-run=client -o yaml | kadmin apply -f -

echo "Applying Leantime secret material..."
kadmin create secret generic leantime-db -n default \
  --from-literal=MYSQL_ROOT_PASSWORD="${LEANTIME_DB_ROOT_PASSWORD}" \
  --from-literal=MYSQL_PASSWORD="${LEANTIME_DB_PASSWORD}" \
  --dry-run=client -o yaml | kadmin apply -f -

kadmin create secret generic leantime-oidc -n default \
  --from-literal=LEAN_OIDC_ENABLE="${LEAN_OIDC_ENABLE}" \
  --from-literal=LEAN_OIDC_CLIENT_ID="${LEAN_OIDC_CLIENT_ID}" \
  --from-literal=LEAN_OIDC_CLIENT_SECRET="${LEAN_OIDC_CLIENT_SECRET}" \
  --from-literal=LEAN_OIDC_PROVIDER_URL="${LEAN_OIDC_PROVIDER_URL}" \
  --from-literal=LEAN_OIDC_CREATE_USER="${LEAN_OIDC_CREATE_USER}" \
  --from-literal=LEAN_OIDC_DEFAULT_ROLE="${LEAN_OIDC_DEFAULT_ROLE}" \
  --from-literal=LEAN_OIDC_SCOPES="${LEAN_OIDC_SCOPES}" \
  --from-literal=LEAN_DISABLE_LOGIN_FORM="${LEAN_DISABLE_LOGIN_FORM}" \
  --dry-run=client -o yaml | kadmin apply -f -

# echo "Applying GitLab secret material..."
# kadmin create secret generic gitlab-secrets -n gitlab \
#   --from-literal=GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD}" \
#   --from-literal=GITLAB_ROOT_EMAIL="${GITLAB_ROOT_EMAIL}" \
#   --from-literal=GITLAB_EXTERNAL_URL="${GITLAB_URL}" \
#   --from-literal=OIDC_ENABLED="${OIDC_ENABLED}" \
#   --from-literal=OIDC_LABEL="${OIDC_LABEL}" \
#   --from-literal=OIDC_ISSUER="${OIDC_ISSUER}" \
#   --from-literal=OIDC_UID_FIELD="${OIDC_UID_FIELD}" \
#   --from-literal=OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
#   --from-literal=OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET}" \
#   --dry-run=client -o yaml | kadmin apply -f -

echo "Applying Wisemapping secret material..."
kadmin create secret generic wisemapping-secrets -n wisemapping \
  --from-literal=WISEMAPPING_POSTGRES_PASSWORD="${WISEMAPPING_POSTGRES_PASSWORD}" \
  --from-literal=WISEMAPPING_JWT_SECRET="${WISEMAPPING_JWT_SECRET}" \
  --from-literal=WISEMAPPING_OAUTH_TOKEN_SECRET="${WISEMAPPING_OAUTH_TOKEN_SECRET}" \
  --from-literal=WISEMAPPING_OAUTH_ENABLED="${WISEMAPPING_OAUTH_ENABLED}" \
  --from-literal=SPRING_PROFILES_ACTIVE="${WISEMAPPING_SPRING_PROFILES_ACTIVE}" \
  --from-literal=OAUTH_GOOGLE_CLIENT_ID="${OAUTH_GOOGLE_CLIENT_ID}" \
  --from-literal=OAUTH_GOOGLE_CLIENT_SECRET="${OAUTH_GOOGLE_CLIENT_SECRET}" \
  --from-literal=OAUTH_GOOGLE_ISSUER_URI="${OAUTH_GOOGLE_ISSUER_URI}" \
  --dry-run=client -o yaml | kadmin apply -f -

kadmin create secret generic wisemapping-email -n wisemapping \
  --from-literal=WISEMAPPING_MAIL_ENABLED="${WISEMAPPING_MAIL_ENABLED}" \
  --from-literal=WISEMAPPING_MAIL_SENDER_EMAIL="${WISEMAPPING_MAIL_SENDER_EMAIL}" \
  --from-literal=WISEMAPPING_MAIL_HOST="${WISEMAPPING_MAIL_HOST}" \
  --from-literal=WISEMAPPING_MAIL_PORT="${WISEMAPPING_MAIL_PORT}" \
  --from-literal=WISEMAPPING_MAIL_USERNAME="${WISEMAPPING_MAIL_USERNAME}" \
  --from-literal=WISEMAPPING_MAIL_PASSWORD="${WISEMAPPING_MAIL_PASSWORD}" \
  --dry-run=client -o yaml | kadmin apply -f -

if [ "${MONITORING_ENABLED}" = "true" ]; then
  echo "Applying Grafana admin secret..."
  kadmin create secret generic grafana-admin -n monitoring \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kadmin apply -f -
fi

echo "Applying Cloudflare tunnel token..."
kadmin create secret generic cloudflare-tunnel-token -n kube-system \
  --from-literal=token="${CLOUDFLARE_TUNNEL_TOKEN}" \
  --dry-run=client -o yaml | kadmin apply -f -

echo ""
echo "Secret reconciliation complete for GitOps-managed platform workloads."
echo "Authentik URL: ${AUTHENTIK_URL}"
# echo "GitLab URL: ${GITLAB_URL}"
