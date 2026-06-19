#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

# shellcheck source=scripts/dev-preflight.sh
source "${SCRIPT_DIR}/dev-preflight.sh"
# shellcheck source=scripts/dev-app-targets.sh
source "${SCRIPT_DIR}/dev-app-targets.sh"

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

assert_deployment_available() {
  local namespace="$1"
  local deployment="$2"
  local available

  available="$(kubectl get "deployment/${deployment}" -n "${namespace}" -o jsonpath='{.status.availableReplicas}')"
  if ! [[ "${available:-0}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Deployment ${namespace}/${deployment} is not available." >&2
    return 1
  fi
}

ensure_cluster() {
  require_cmd k3d
  require_cmd kubectl

  dev_preflight_check_disk "${PROJECT_ROOT}"

  if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    "${SCRIPT_DIR}/dev-cluster-up.sh"
  else
    kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
  fi

  dev_preflight_check_kubernetes_node_pressure
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

diagnostics_baserow() {
  kubectl get pods,deploy,svc,pvc,cronjob -n baserow || true
  kubectl describe deploy/baserow -n baserow || true
  kubectl logs deploy/baserow -n baserow --all-containers --tail=200 || true
}

diagnostics_optional_crm() {
  kubectl get pods,deploy,svc,pvc,cronjob,ingress -n twenty || true
  kubectl get pods,deploy,svc,pvc,cronjob,ingress -n espocrm || true
  kubectl describe deploy/twenty-server -n twenty || true
  kubectl describe deploy/twenty-worker -n twenty || true
  kubectl describe deploy/espocrm -n espocrm || true
  kubectl logs deploy/twenty-server -n twenty --all-containers --tail=200 || true
  kubectl logs deploy/twenty-worker -n twenty --all-containers --tail=200 || true
  kubectl logs deploy/espocrm -n espocrm --all-containers --tail=200 || true
  kubectl logs deploy/espocrm-daemon -n espocrm --all-containers --tail=200 || true
}

smoke_wisemapping() {
  local probe_host="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
  local wait_timeout="${WISEMAPPING_WAIT_TIMEOUT:-${DEFAULT_WAIT_TIMEOUT}}"
  local dev_postgres_password="${WISEMAPPING_DEV_POSTGRES_PASSWORD:-dev-postgres-password-not-for-production}"
  local dev_jwt_secret="${WISEMAPPING_DEV_JWT_SECRET:-dev-jwt-secret-not-for-production}"
  local dev_oauth_token_secret="${WISEMAPPING_DEV_OAUTH_TOKEN_SECRET:-dev-oauth-token-secret-not-for-production}"
  local probe_name
  local probe_output

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
  assert_deployment_available wisemapping wisemapping-postgres
  assert_deployment_available wisemapping wisemapping

  probe_name="wisemapping-smoke-$(date +%s)"
  probe_output="$(kubectl run -n wisemapping "${probe_name}" \
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
    ' 2>&1)"
  echo "${probe_output}"
  grep -q "apiBaseUrl" <<< "${probe_output}"
  grep -q "uiBaseUrl" <<< "${probe_output}"

  echo "WiseMapping smoke test passed"
}

smoke_leantime() {
  local probe_host="${LEANTIME_PROBE_HOST:-projects.thekeepstudios.com}"
  local wait_timeout="${LEANTIME_WAIT_TIMEOUT:-${DEFAULT_WAIT_TIMEOUT}}"
  local root_password="${LEANTIME_DEV_DB_ROOT_PASSWORD:-dev-leantime-root-password-not-for-production}"
  local db_password="${LEANTIME_DEV_DB_PASSWORD:-dev-leantime-password-not-for-production}"
  local probe_name
  local probe_output

  echo "== Leantime smoke =="
  kubectl create secret generic leantime-db -n default \
    --from-literal=MYSQL_ROOT_PASSWORD="${root_password}" \
    --from-literal=MYSQL_PASSWORD="${db_password}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k kubernetes/apps/leantime
  kubectl rollout status deploy/leantime-mariadb -n default --timeout="${wait_timeout}"
  kubectl rollout status deploy/leantime -n default --timeout="${wait_timeout}"
  assert_deployment_available default leantime-mariadb
  assert_deployment_available default leantime

  probe_name="leantime-smoke-$(date +%s)"
  probe_output="$(kubectl run -n default "${probe_name}" \
    --rm=true \
    --attach=true \
    -i \
    --restart=Never \
    --image="${PROBE_IMAGE}" \
    --quiet=true \
    -- \
    sh -ceu '
      curl -sS --max-time 20 \
        -D /tmp/leantime-root.headers \
        -o /tmp/leantime-root.body \
        -H "Host: '"${probe_host}"'" \
        -H "X-Forwarded-Proto: https" \
        -H "Accept: text/event-stream" \
        http://traefik.kube-system.svc.cluster.local/
      grep -Eq "^HTTP/[0-9.]+ 30[1278]" /tmp/leantime-root.headers
      grep -Eiq "^location: https://'"${probe_host}"'/dashboard/home\r?$" /tmp/leantime-root.headers
      ! grep -Eiq "\"jsonrpc\"" /tmp/leantime-root.body

      curl -fsS --max-time 20 \
        -H "Host: '"${probe_host}"'" \
        -H "X-Forwarded-Proto: https" \
        -H "Accept: text/html" \
        -L \
        http://leantime/dashboard/home > /tmp/leantime-login.html
      test -s /tmp/leantime-login.html
      grep -Eiq "leantime|login|email|password|install|redirecting" /tmp/leantime-login.html
      head -c 500 /tmp/leantime-login.html
      printf "\nLEANTIME_ROUTE_SMOKE_OK\n"
    ' 2>&1)"
  echo "${probe_output}"
  grep -q "^LEANTIME_ROUTE_SMOKE_OK$" <<< "${probe_output}"
  grep -Eiq "leantime|login|email|password|install|redirecting" <<< "${probe_output}"

  echo "Leantime smoke test passed"
}

smoke_baserow() {
  local probe_host="${BASEROW_PROBE_HOST:-baserow.thekeepstudios.com}"
  local wait_timeout="${BASEROW_WAIT_TIMEOUT:-${DEFAULT_WAIT_TIMEOUT}}"
  local probe_name
  local probe_output

  echo "== Baserow smoke =="
  kubectl apply -k kubernetes/apps/baserow
  kubectl rollout status deploy/baserow -n baserow --timeout="${wait_timeout}"
  assert_deployment_available baserow baserow

  probe_name="baserow-smoke-$(date +%s)"
  probe_output="$(kubectl run -n baserow "${probe_name}" \
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
        http://baserow/ > /tmp/baserow.html
      test -s /tmp/baserow.html
      grep -Eiq "baserow|login|sign" /tmp/baserow.html
      head -c 500 /tmp/baserow.html
    ' 2>&1)"
  echo "${probe_output}"
  grep -Eiq "login|sign|create account" <<< "${probe_output}"

  echo "Baserow smoke test passed"
}

smoke_twenty() {
  local probe_host="${TWENTY_PROBE_HOST:-twenty.thekeepstudios.com}"
  local wait_timeout="${TWENTY_WAIT_TIMEOUT:-20m}"
  local pg_password="${TWENTY_DEV_PG_DATABASE_PASSWORD:-dev-twenty-postgres-password}"
  local encryption_key="${TWENTY_DEV_ENCRYPTION_KEY:-dev-twenty-encryption-key-32chars}"
  local app_secret="${TWENTY_DEV_APP_SECRET:-dev-twenty-app-secret-32chars}"
  local probe_name
  local probe_output

  echo "== Twenty CRM smoke =="
  kubectl create namespace twenty --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic twenty-secrets -n twenty \
    --from-literal=PG_DATABASE_PASSWORD="${pg_password}" \
    --from-literal=ENCRYPTION_KEY="${encryption_key}" \
    --from-literal=APP_SECRET="${app_secret}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k kubernetes/apps/twenty
  kubectl rollout status deploy/twenty-postgres -n twenty --timeout="${wait_timeout}"
  kubectl rollout status deploy/twenty-redis -n twenty --timeout="${wait_timeout}"
  kubectl rollout status deploy/twenty-server -n twenty --timeout="${wait_timeout}"
  kubectl rollout status deploy/twenty-worker -n twenty --timeout="${wait_timeout}"
  assert_deployment_available twenty twenty-postgres
  assert_deployment_available twenty twenty-redis
  assert_deployment_available twenty twenty-server
  assert_deployment_available twenty twenty-worker

  probe_name="twenty-smoke-$(date +%s)"
  probe_output="$(kubectl run -n twenty "${probe_name}" \
    --rm=true \
    --attach=true \
    -i \
    --restart=Never \
    --image="${PROBE_IMAGE}" \
    --quiet=true \
    -- \
    sh -ceu '
      curl -fsS --max-time 20 http://twenty/healthz > /tmp/twenty-health.txt
      curl -fsS --max-time 20 \
        -H "Host: '"${probe_host}"'" \
        -H "X-Forwarded-Proto: https" \
        http://twenty/ > /tmp/twenty.html
      test -s /tmp/twenty.html
      grep -Eiq "twenty|login|sign|workspace" /tmp/twenty.html
      head -c 500 /tmp/twenty.html
    ' 2>&1)"
  echo "${probe_output}"
  grep -Eiq "twenty|login|sign|workspace" <<< "${probe_output}"

  echo "Twenty CRM smoke test passed"
}

smoke_espocrm() {
  local probe_host="${ESPOCRM_PROBE_HOST:-espocrm.thekeepstudios.com}"
  local wait_timeout="${ESPOCRM_WAIT_TIMEOUT:-20m}"
  local root_password="${ESPOCRM_DEV_DB_ROOT_PASSWORD:-dev-espocrm-root-password}"
  local db_password="${ESPOCRM_DEV_DB_PASSWORD:-dev-espocrm-db-password}"
  local admin_password="${ESPOCRM_DEV_ADMIN_PASSWORD:-dev-espocrm-admin-password}"
  local probe_name
  local probe_output

  echo "== EspoCRM smoke =="
  kubectl create namespace espocrm --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic espocrm-secrets -n espocrm \
    --from-literal=MARIADB_ROOT_PASSWORD="${root_password}" \
    --from-literal=MARIADB_PASSWORD="${db_password}" \
    --from-literal=ESPOCRM_ADMIN_PASSWORD="${admin_password}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k kubernetes/apps/espocrm
  kubectl rollout status deploy/espocrm-db -n espocrm --timeout="${wait_timeout}"
  kubectl rollout status deploy/espocrm -n espocrm --timeout="${wait_timeout}"
  kubectl rollout status deploy/espocrm-daemon -n espocrm --timeout="${wait_timeout}"
  assert_deployment_available espocrm espocrm-db
  assert_deployment_available espocrm espocrm
  assert_deployment_available espocrm espocrm-daemon

  probe_name="espocrm-smoke-$(date +%s)"
  probe_output="$(kubectl run -n espocrm "${probe_name}" \
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
        http://espocrm/ > /tmp/espocrm.html
      test -s /tmp/espocrm.html
      grep -Eiq "espocrm|login|username|password" /tmp/espocrm.html
      head -c 500 /tmp/espocrm.html
    ' 2>&1)"
  echo "${probe_output}"
  grep -Eiq "espocrm|login|username|password" <<< "${probe_output}"

  echo "EspoCRM smoke test passed"
}

run_target() {
  local target="$1"
  local concrete_target

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
    baserow)
      if ! smoke_baserow; then
        diagnostics_baserow
        return 1
      fi
      ;;
    twenty)
      if ! smoke_twenty; then
        diagnostics_optional_crm
        return 1
      fi
      ;;
    espocrm)
      if ! smoke_espocrm; then
        diagnostics_optional_crm
        return 1
      fi
      ;;
    optional-crm|crm-bakeoff)
      while IFS= read -r concrete_target; do
        run_target "${concrete_target}"
      done < <(dev_app_expand_target "${target}")
      ;;
    platform)
      while IFS= read -r concrete_target; do
        run_target "${concrete_target}"
      done < <(dev_app_expand_target "${target}")
      ;;
    *)
      echo "Unknown dev smoke target: ${target}" >&2
      dev_app_print_usage "scripts/dev-smoke.sh" "..."
      return 2
      ;;
  esac
}

validate_target() {
  if ! dev_app_is_target "$1"; then
    echo "Unknown dev smoke target: $1" >&2
    dev_app_print_usage "scripts/dev-smoke.sh" "..."
    return 2
  fi
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
