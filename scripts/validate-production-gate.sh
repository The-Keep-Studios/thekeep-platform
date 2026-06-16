#!/usr/bin/env bash
# DEPRECATED: Use ansible-playbook with platform roles instead.
# See README.md for the new Ansible-first workflow.
set -euo pipefail

REQUIRE_EXTERNAL_HTTPS="${REQUIRE_EXTERNAL_HTTPS:-true}"
DIRECT_HTTP_URLS="${DIRECT_HTTP_URLS:-}"

APP_NAMES=(
  platform-root
  platform-cloudflare-tunnel
  platform-authentik
  platform-leantime
  platform-wisemapping
  platform-baserow
  platform-monitoring-prometheus
  platform-monitoring-loki
)

HTTPS_ENDPOINTS=(
  https://auth.thekeepstudios.com
  https://projects.thekeepstudios.com
  https://mindmaps.thekeepstudios.com
  https://baserow.thekeepstudios.com
  https://crm.thekeepstudios.com
  https://grafana.thekeepstudios.com
  https://prometheus.thekeepstudios.com
  https://alerts.thekeepstudios.com
  https://argocd.thekeepstudios.com
)

PROTECTED_HTTPS_ENDPOINTS=(
  https://crm.thekeepstudios.com
  https://prometheus.thekeepstudios.com
  https://alerts.thekeepstudios.com
)

failures=0

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

warn() {
  echo "WARN: $*" >&2
}

check_cluster() {
  if kadmin get nodes >/dev/null 2>&1; then
    pass "cluster reachable as k3s-admin"
  else
    fail "cluster is not reachable as k3s-admin"
  fi
}

check_argocd_apps() {
  for app in "${APP_NAMES[@]}"; do
    if ! kadmin get application "${app}" -n argocd >/dev/null 2>&1; then
      fail "Argo application missing: ${app}"
      continue
    fi

    sync_status="$(kadmin get application "${app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health_status="$(kadmin get application "${app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

    if [ "${sync_status}" = "Synced" ] && [ "${health_status}" = "Healthy" ]; then
      pass "Argo application ${app} is Synced/Healthy"
    else
      fail "Argo application ${app} is sync=${sync_status:-unknown} health=${health_status:-unknown}"
    fi
  done
}

check_cloudflare_tunnel() {
  if kadmin get secret cloudflare-tunnel-token -n kube-system >/dev/null 2>&1; then
    pass "Cloudflare tunnel token secret exists"
  else
    fail "Cloudflare tunnel token secret is missing"
  fi

  if kadmin wait --for=condition=available --timeout=300s deployment/cloudflared -n kube-system >/dev/null 2>&1; then
    pass "Cloudflare tunnel deployment is available"
  else
    fail "Cloudflare tunnel deployment is not available"
  fi
}

check_authentik_forward_auth() {
  if kadmin get middleware authentik-forward-auth -n identity >/dev/null 2>&1; then
    pass "Authentik forward-auth middleware exists"
  else
    fail "Authentik forward-auth middleware is missing"
  fi

  if kadmin get ingress authentik-forward-auth-outpost-routes -n identity >/dev/null 2>&1; then
    pass "Authentik forward-auth outpost routes exist"
  else
    fail "Authentik forward-auth outpost routes are missing"
  fi
}

check_backup_resources() {
  if kadmin get cronjob leantime-db-backup -n default >/dev/null 2>&1; then
    pass "Leantime backup CronJob exists"
  else
    fail "Leantime backup CronJob is missing"
  fi

  if kadmin get cronjob baserow-backup -n baserow >/dev/null 2>&1; then
    pass "Baserow backup CronJob exists"
  else
    fail "Baserow backup CronJob is missing"
  fi
}

check_https_endpoints() {
  if [ "${REQUIRE_EXTERNAL_HTTPS}" != "true" ]; then
    warn "external HTTPS endpoint checks skipped because REQUIRE_EXTERNAL_HTTPS=${REQUIRE_EXTERNAL_HTTPS}"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required for external HTTPS endpoint checks"
    return
  fi

  for url in "${HTTPS_ENDPOINTS[@]}"; do
    status="$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    case "${status}" in
      2*|401|403)
        pass "HTTPS endpoint reachable: ${url} (${status})"
        ;;
      3*)
        fail "HTTPS endpoint check failed: ${url} (${status} - unexpected redirect at edge)"
        ;;
      *)
        fail "HTTPS endpoint check failed: ${url} (${status:-no response})"
        ;;
    esac
  done

  for url in "${PROTECTED_HTTPS_ENDPOINTS[@]}"; do
    # Check for direct 2xx (fail)
    status="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    if [[ "${status}" =~ ^2 ]]; then
      fail "protected endpoint returned unauthenticated success: ${url} (${status})"
      continue
    fi

    # Check after following redirects (should still not be 2xx)
    final_status="$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    case "${final_status}" in
      401|403)
        pass "protected endpoint is not openly accessible: ${url} (final status ${final_status})"
        ;;
      2*)
        fail "protected endpoint returned success after following redirects: ${url} (final status ${final_status})"
        ;;
      *)
        fail "protected endpoint check failed: ${url} (final status ${final_status:-no response})"
        ;;
    esac
  done
}

check_direct_http_urls() {
  if [ -z "${DIRECT_HTTP_URLS}" ]; then
    fail "direct HTTP origin exposure MUST be checked; set DIRECT_HTTP_URLS to origin HTTP URLs that must not answer"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required for direct HTTP exposure checks"
    return
  fi

  for url in ${DIRECT_HTTP_URLS}; do
    status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    if [ -n "${status}" ] && [ "${status}" != "000" ]; then
      fail "direct HTTP URL answered and must be blocked: ${url} (${status})"
    else
      pass "direct HTTP URL did not answer: ${url}"
    fi
  done
}

check_cluster
check_cloudflare_tunnel
check_authentik_forward_auth
check_argocd_apps
check_backup_resources
check_https_endpoints
check_direct_http_urls

if [ "${failures}" -gt 0 ]; then
  echo ""
  echo "Production gate failed with ${failures} issue(s)." >&2
  exit 1
fi

echo ""
echo "Production gate passed."
