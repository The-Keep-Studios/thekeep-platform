#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"
PROBE_HOST="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
PROBE_IMAGE="${WISEMAPPING_PROBE_IMAGE:-curlimages/curl:8.8.0}"
WAIT_TIMEOUT="${WISEMAPPING_WAIT_TIMEOUT:-10m}"
DEV_POSTGRES_PASSWORD="${WISEMAPPING_DEV_POSTGRES_PASSWORD:-dev-postgres-password-not-for-production}"
DEV_JWT_SECRET="${WISEMAPPING_DEV_JWT_SECRET:-dev-jwt-secret-not-for-production}"
DEV_OAUTH_TOKEN_SECRET="${WISEMAPPING_DEV_OAUTH_TOKEN_SECRET:-dev-oauth-token-secret-not-for-production}"
DIAGNOSTICS_ENABLED=false

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

diagnostics() {
  status="$?"
  if [ "${status}" -eq 0 ] || [ "${DIAGNOSTICS_ENABLED}" != "true" ]; then
    return
  fi

  echo ""
  echo "WiseMapping smoke test failed. Recent diagnostics:"
  kubectl get pods,deploy,svc,pvc -n wisemapping || true
  kubectl describe deploy/wisemapping -n wisemapping || true
  kubectl logs deploy/wisemapping -n wisemapping --all-containers --tail=200 || true
  kubectl logs deploy/wisemapping-postgres -n wisemapping --all-containers --tail=100 || true
}

require_cmd k3d
require_cmd kubectl
trap diagnostics EXIT

if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  "${SCRIPT_DIR}/dev-cluster-up.sh"
else
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
fi
DIAGNOSTICS_ENABLED=true

echo "Preparing WiseMapping namespace and dev secrets"
kubectl create namespace wisemapping --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic wisemapping-secrets -n wisemapping \
  --from-literal=WISEMAPPING_POSTGRES_PASSWORD="${DEV_POSTGRES_PASSWORD}" \
  --from-literal=WISEMAPPING_JWT_SECRET="${DEV_JWT_SECRET}" \
  --from-literal=WISEMAPPING_OAUTH_TOKEN_SECRET="${DEV_OAUTH_TOKEN_SECRET}" \
  --from-literal=WISEMAPPING_OAUTH_ENABLED=false \
  --from-literal=SPRING_PROFILES_ACTIVE= \
  --from-literal=OAUTH_GOOGLE_CLIENT_ID= \
  --from-literal=OAUTH_GOOGLE_CLIENT_SECRET= \
  --from-literal=OAUTH_GOOGLE_ISSUER_URI= \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applying WiseMapping manifests"
kubectl apply -k kubernetes/apps/wisemapping

echo "Waiting for WiseMapping database"
kubectl rollout status deploy/wisemapping-postgres -n wisemapping --timeout="${WAIT_TIMEOUT}"

echo "Waiting for WiseMapping application"
kubectl rollout status deploy/wisemapping -n wisemapping --timeout="${WAIT_TIMEOUT}"

probe_name="wisemapping-smoke-$(date +%s)"
echo "Probing WiseMapping backend API through the service"
kubectl run -n wisemapping "${probe_name}" \
  --rm=true \
  --attach=true \
  -i \
  --restart=Never \
  --image="${PROBE_IMAGE}" \
  --quiet=true \
  -- \
  sh -ceu '
    curl -fsS --max-time 20 \
      -H "Host: '"${PROBE_HOST}"'" \
      -H "X-Forwarded-Proto: https" \
      http://wisemapping/api/restful/app/config > /tmp/wisemapping-config.json
    grep -q "apiBaseUrl" /tmp/wisemapping-config.json
    grep -q "uiBaseUrl" /tmp/wisemapping-config.json
    cat /tmp/wisemapping-config.json
  '

echo ""
echo "WiseMapping smoke test passed"
