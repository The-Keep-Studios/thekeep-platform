#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"
PROBE_IMAGE="${DEV_PROBE_IMAGE:-curlimages/curl:8.8.0}"
DEFAULT_WAIT_TIMEOUT="${DEV_WAIT_TIMEOUT:-10m}"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

ensure_cluster() {
  require_cmd k3d
  require_cmd kubectl

  if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    "${SCRIPT_DIR}/dev-cluster-up.sh"
  else
    kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
  fi
}

diagnostics_wisemapping() {
  kubectl get pods,deploy,svc,pvc -n wisemapping || true
  kubectl describe deploy/wisemapping -n wisemapping || true
  kubectl logs deploy/wisemapping -n wisemapping --all-containers --tail=200 || true
  kubectl logs deploy/wisemapping-postgres -n wisemapping --all-containers --tail=100 || true
}

diagnostics_leantime() {
  kubectl get pods,deploy,svc,pvc -n default | grep -E 'leantime|NAME' || true
  kubectl describe deploy/leantime -n default || true
  kubectl logs deploy/leantime -n default --all-containers --tail=200 || true
  kubectl logs deploy/leantime-mariadb -n default --all-containers --tail=100 || true
}

smoke_wisemapping() {
  local probe_host="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
  local wait_timeout="${WISEMAPPING_WAIT_TIMEOUT:-${DEFAULT_WAIT_TIMEOUT}}"
  local dev_postgres_password="${WISEMAPPING_DEV_POSTGRES_PASSWORD:-dev-postgres-password-not-for-production}"
  local dev_jwt_secret="${WISEMAPPING_DEV_JWT_SECRET:-dev-jwt-secret-not-for-production}"
  local dev_oauth_token_secret="${WISEMAPPING_DEV_OAUTH_TOKEN_SECRET:-dev-oauth-token-secret-not-for-production}"
  local probe_name

  echo "== WiseMapping smoke =="
  kubectl create namespace wisemapping --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic wisemapping-secrets -n wisemapping \
    --from-literal=WISEMAPPING_POSTGRES_PASSWORD="${dev_postgres_password}" \
    --from-literal=WISEMAPPING_JWT_SECRET="${dev_jwt_secret}" \
    --from-literal=WISEMAPPING_OAUTH_TOKEN_SECRET="${dev_oauth_token_secret}" \
    --from-literal=WISEMAPPING_OAUTH_ENABLED=false \
    --from-literal=SPRING_PROFILES_ACTIVE= \
    --from-literal=OAUTH_GOOGLE_CLIENT_ID= \
    --from-literal=OAUTH_GOOGLE_CLIENT_SECRET= \
    --from-literal=OAUTH_GOOGLE_ISSUER_URI= \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k kubernetes/apps/wisemapping
  kubectl rollout status deploy/wisemapping-postgres -n wisemapping --timeout="${wait_timeout}"
  kubectl rollout status deploy/wisemapping -n wisemapping --timeout="${wait_timeout}"

  probe_name="wisemapping-smoke-$(date +%s)"
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
        -H "Host: '"${probe_host}"'" \
        -H "X-Forwarded-Proto: https" \
        http://wisemapping/api/restful/app/config > /tmp/wisemapping-config.json
      grep -q "apiBaseUrl" /tmp/wisemapping-config.json
      grep -q "uiBaseUrl" /tmp/wisemapping-config.json
      cat /tmp/wisemapping-config.json
    '

  echo "WiseMapping smoke test passed"
}

smoke_leantime() {
  local probe_host="${LEANTIME_PROBE_HOST:-projects.thekeepstudios.com}"
  local wait_timeout="${LEANTIME_WAIT_TIMEOUT:-${DEFAULT_WAIT_TIMEOUT}}"
  local root_password="${LEANTIME_DEV_DB_ROOT_PASSWORD:-dev-leantime-root-password-not-for-production}"
  local db_password="${LEANTIME_DEV_DB_PASSWORD:-dev-leantime-password-not-for-production}"
  local probe_name

  echo "== Leantime smoke =="
  kubectl create secret generic leantime-db -n default \
    --from-literal=MYSQL_ROOT_PASSWORD="${root_password}" \
    --from-literal=MYSQL_PASSWORD="${db_password}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k kubernetes/apps/leantime
  kubectl rollout status deploy/leantime-mariadb -n default --timeout="${wait_timeout}"
  kubectl rollout status deploy/leantime -n default --timeout="${wait_timeout}"

  probe_name="leantime-smoke-$(date +%s)"
  kubectl run -n default "${probe_name}" \
    --rm=true \
    --attach=true \
    -i \
    --restart=Never \
    --image="${PROBE_IMAGE}" \
    --quiet=true \
    -- \
    sh -ceu '
      curl -fsS --max-time 20 \
        -H "Host: '"${probe_host}"'" \
        -H "X-Forwarded-Proto: https" \
        http://leantime/auth/login > /tmp/leantime-login.html
      test -s /tmp/leantime-login.html
      grep -Eiq "leantime|login|email|password" /tmp/leantime-login.html
      head -c 500 /tmp/leantime-login.html
    '

  echo "Leantime smoke test passed"
}

run_target() {
  local target="$1"

  case "${target}" in
    wisemapping)
      if ! smoke_wisemapping; then
        diagnostics_wisemapping
        return 1
      fi
      ;;
    leantime)
      if ! smoke_leantime; then
        diagnostics_leantime
        return 1
      fi
      ;;
    platform)
      run_target wisemapping
      run_target leantime
      ;;
    *)
      echo "Unknown dev smoke target: ${target}" >&2
      echo "Usage: scripts/dev-smoke.sh [wisemapping|leantime|platform]..." >&2
      return 2
      ;;
  esac
}

validate_target() {
  case "$1" in
    wisemapping|leantime|platform)
      ;;
    *)
      echo "Unknown dev smoke target: $1" >&2
      echo "Usage: scripts/dev-smoke.sh [wisemapping|leantime|platform]..." >&2
      return 2
      ;;
  esac
}

main() {
  if [ "$#" -eq 0 ]; then
    set -- platform
  fi

  for target in "$@"; do
    validate_target "${target}"
  done

  ensure_cluster

  for target in "$@"; do
    run_target "${target}"
  done
}

main "$@"
