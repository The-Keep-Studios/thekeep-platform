#!/usr/bin/env bash
# DEPRECATED: OIDC configuration is now managed via Ansible and GitOps.
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

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

if ! kadmin get nodes >/dev/null 2>&1; then
  echo "Cannot reach cluster as k3s-admin."
  echo "Run the GitOps bootstrap path first and confirm k3s is up."
  exit 1
fi

echo "Applying Leantime OIDC secret..."
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

# GitLab is disabled for the internal pilot. Skipping GitLab OIDC patching.
# if ! kadmin get secret gitlab-secrets -n gitlab >/dev/null 2>&1; then
#   echo "Missing secret gitlab/gitlab-secrets. Run scripts/seed-platform-secrets.sh first."
#   exit 1
# fi
# echo "Patching GitLab OIDC values in existing secret..."
# kadmin patch secret gitlab-secrets -n gitlab --type merge -p "{\"stringData\":{\"OIDC_ENABLED\":\"${OIDC_ENABLED}\",\"OIDC_LABEL\":\"${OIDC_LABEL}\",\"OIDC_ISSUER\":\"${OIDC_ISSUER}\",\"OIDC_UID_FIELD\":\"${OIDC_UID_FIELD}\",\"OIDC_CLIENT_ID\":\"${OIDC_CLIENT_ID}\",\"OIDC_CLIENT_SECRET\":\"${OIDC_CLIENT_SECRET}\"}}"

if ! kadmin get secret wisemapping-secrets -n wisemapping >/dev/null 2>&1; then
  echo "Missing secret wisemapping/wisemapping-secrets. Run scripts/seed-platform-secrets.sh first."
  exit 1
fi
echo "Patching Wisemapping OAuth values in existing secret..."
kadmin patch secret wisemapping-secrets -n wisemapping --type merge -p "{\"stringData\":{\"WISEMAPPING_OAUTH_ENABLED\":\"${WISEMAPPING_OAUTH_ENABLED}\",\"SPRING_PROFILES_ACTIVE\":\"${WISEMAPPING_SPRING_PROFILES_ACTIVE}\",\"OAUTH_GOOGLE_CLIENT_ID\":\"${OAUTH_GOOGLE_CLIENT_ID}\",\"OAUTH_GOOGLE_CLIENT_SECRET\":\"${OAUTH_GOOGLE_CLIENT_SECRET}\",\"OAUTH_GOOGLE_ISSUER_URI\":\"${OAUTH_GOOGLE_ISSUER_URI}\"}}"

echo "Restarting app deployments to consume new env secrets..."
kadmin rollout restart deployment/leantime
# kadmin rollout restart deployment/gitlab -n gitlab
kadmin rollout restart deployment/wisemapping -n wisemapping

echo "Waiting for rollouts..."
kadmin rollout status deployment/leantime --timeout=900s
# kadmin rollout status deployment/gitlab -n gitlab --timeout=1800s
kadmin rollout status deployment/wisemapping -n wisemapping --timeout=900s

echo ""
echo "OIDC/OAuth reconciliation complete."
echo "Leantime OIDC enabled: ${LEAN_OIDC_ENABLE}"
# echo "GitLab OIDC enabled:   ${OIDC_ENABLED}"
echo "Wisemapping OAuth enabled: ${WISEMAPPING_OAUTH_ENABLED}"
