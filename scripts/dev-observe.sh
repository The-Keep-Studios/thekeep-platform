#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

# shellcheck source=scripts/dev-preflight.sh
source "${SCRIPT_DIR}/dev-preflight.sh"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"
OPEN_BROWSER="${DEV_OBSERVE_OPEN:-true}"
CAPTURE_BROWSER="${DEV_OBSERVE_CAPTURE:-true}"
HOLD_OPEN="${DEV_OBSERVE_HOLD:-true}"
VIEWPORT="${DEV_OBSERVE_VIEWPORT:-1440,1000}"
PATCH_LOCAL_CONFIG="${DEV_OBSERVE_PATCH_CONFIG:-true}"
ARTIFACT_ROOT="${DEV_OBSERVE_ARTIFACT_ROOT:-.artifacts/dev-observe/$(date -u +%Y%m%dT%H%M%SZ)}"

PORT_FORWARD_PIDS=()

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

cleanup() {
  local pid
  for pid in "${PORT_FORWARD_PIDS[@]}"; do
    if [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
}

find_chromium() {
  command -v chromium 2>/dev/null ||
    command -v chromium-browser 2>/dev/null ||
    command -v google-chrome 2>/dev/null ||
    command -v google-chrome-stable 2>/dev/null ||
    true
}

ensure_context() {
  require_cmd kubectl
  require_cmd curl

  dev_preflight_check_disk "${PROJECT_ROOT}"

  if command -v k3d >/dev/null 2>&1 && k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
  fi

  dev_preflight_check_kubernetes_node_pressure
}

app_config() {
  local target="$1"

  case "${target}" in
    wisemapping)
      APP_NAMESPACE="wisemapping"
      APP_SERVICE="wisemapping"
      APP_DEPLOYMENT="wisemapping"
      APP_PORT="${WISEMAPPING_OBSERVE_PORT:-18081}"
      APP_HOST="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
      APP_PROBE_PATH="/api/restful/app/config"
      APP_PROBE_PATTERN="apiBaseUrl|uiBaseUrl"
      APP_CONFIG_KIND="wisemapping"
      ;;
    leantime)
      APP_NAMESPACE="default"
      APP_SERVICE="leantime"
      APP_DEPLOYMENT="leantime"
      APP_PORT="${LEANTIME_OBSERVE_PORT:-18080}"
      APP_HOST="${LEANTIME_PROBE_HOST:-projects.thekeepstudios.com}"
      APP_PROBE_PATH="/auth/login"
      APP_PROBE_PATTERN="leantime|login|email|password|install|redirecting"
      APP_CONFIG_KIND="leantime"
      ;;
    baserow)
      APP_NAMESPACE="baserow"
      APP_SERVICE="baserow"
      APP_DEPLOYMENT="baserow"
      APP_PORT="${BASEROW_OBSERVE_PORT:-18082}"
      APP_HOST="${BASEROW_PROBE_HOST:-baserow.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="login|sign|create account"
      APP_CONFIG_KIND="baserow"
      ;;
    twenty)
      APP_NAMESPACE="twenty"
      APP_SERVICE="twenty"
      APP_DEPLOYMENT="twenty-server"
      APP_PORT="${TWENTY_OBSERVE_PORT:-18083}"
      APP_HOST="${TWENTY_PROBE_HOST:-twenty.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="twenty|login|sign|workspace"
      APP_CONFIG_KIND="twenty"
      ;;
    espocrm)
      APP_NAMESPACE="espocrm"
      APP_SERVICE="espocrm"
      APP_DEPLOYMENT="espocrm"
      APP_PORT="${ESPOCRM_OBSERVE_PORT:-18084}"
      APP_HOST="${ESPOCRM_PROBE_HOST:-espocrm.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="espocrm|login|username|password"
      APP_CONFIG_KIND="espocrm"
      ;;
    *)
      echo "Unknown dev observe target: ${target}" >&2
      echo "Usage: scripts/dev-observe.sh [wisemapping|leantime|baserow|twenty|espocrm|optional-crm|crm-bakeoff|platform]" >&2
      return 2
      ;;
  esac
}

patch_local_config() {
  local target="$1"
  local artifact_dir="$2"
  local local_base_url="http://localhost:${APP_PORT}"
  local config_file="${artifact_dir}/${target}.local-config"

  case "${APP_CONFIG_KIND}" in
    wisemapping)
      echo "Patching local WiseMapping config for browser observation: ${local_base_url}"
      kubectl get configmap wisemapping-config -n "${APP_NAMESPACE}" \
        -o jsonpath='{.data.application\.yml}' \
        > "${artifact_dir}/application.original.yml"

      sed \
        -e "s|https://mindmaps.thekeepstudios.com|${local_base_url}|g" \
        -e "s|http://mindmaps.thekeepstudios.com|${local_base_url}|g" \
        "${artifact_dir}/application.original.yml" > "${config_file}"

      kubectl create configmap wisemapping-config -n "${APP_NAMESPACE}" \
        --from-file=application.yml="${config_file}" \
        --dry-run=client \
        -o yaml | kubectl apply -f -
      kubectl rollout restart "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}"
      kubectl rollout status "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}" --timeout=10m
      ;;
    leantime)
      echo "Patching local Leantime config for browser observation: ${local_base_url}"
      kubectl get configmap leantime-runtime-defaults -n "${APP_NAMESPACE}" \
        -o yaml > "${artifact_dir}/leantime-runtime-defaults.original.yaml"
      kubectl patch configmap leantime-runtime-defaults -n "${APP_NAMESPACE}" \
        --type merge \
        -p "{\"data\":{\"LEAN_APP_URL\":\"${local_base_url}\"}}"
      kubectl rollout restart "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}"
      kubectl rollout status "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}" --timeout=10m
      ;;
    baserow)
      local_base_url="http://127.0.0.1:${APP_PORT}"
      APP_HOST="127.0.0.1:${APP_PORT}"
      echo "Patching local Baserow public URL for browser observation: ${local_base_url}"
      kubectl get deployment baserow -n "${APP_NAMESPACE}" \
        -o yaml > "${artifact_dir}/baserow-deployment.original.yaml"
      kubectl set env "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}" \
        BASEROW_PUBLIC_URL="${local_base_url}"
      kubectl patch "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}" \
        --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/startupProbe/httpGet/httpHeaders/0/value\",\"value\":\"${APP_HOST}\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/httpHeaders/0/value\",\"value\":\"${APP_HOST}\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/httpHeaders/0/value\",\"value\":\"${APP_HOST}\"}]"
      kubectl rollout status "deployment/${APP_DEPLOYMENT}" -n "${APP_NAMESPACE}" --timeout=10m
      ;;
    twenty)
      local_base_url="http://127.0.0.1:${APP_PORT}"
      APP_HOST="127.0.0.1:${APP_PORT}"
      echo "Patching local Twenty SERVER_URL for browser observation: ${local_base_url}"
      kubectl get configmap twenty-config -n "${APP_NAMESPACE}" \
        -o yaml > "${artifact_dir}/twenty-config.original.yaml"
      kubectl patch configmap twenty-config -n "${APP_NAMESPACE}" \
        --type merge \
        -p "{\"data\":{\"SERVER_URL\":\"${local_base_url}\"}}"
      kubectl rollout restart deployment/twenty-server -n "${APP_NAMESPACE}"
      kubectl rollout restart deployment/twenty-worker -n "${APP_NAMESPACE}"
      kubectl rollout status deployment/twenty-server -n "${APP_NAMESPACE}" --timeout=10m
      kubectl rollout status deployment/twenty-worker -n "${APP_NAMESPACE}" --timeout=10m
      ;;
    espocrm)
      local_base_url="http://127.0.0.1:${APP_PORT}"
      APP_HOST="127.0.0.1:${APP_PORT}"
      echo "Patching local EspoCRM site URL for browser observation: ${local_base_url}"
      kubectl get deployment espocrm -n "${APP_NAMESPACE}" \
        -o yaml > "${artifact_dir}/espocrm-deployment.original.yaml"
      kubectl set env deployment/espocrm -n "${APP_NAMESPACE}" \
        ESPOCRM_SITE_URL="${local_base_url}"
      kubectl rollout status deployment/espocrm -n "${APP_NAMESPACE}" --timeout=10m
      ;;
  esac
}

wait_for_port_forward() {
  local pid="$1"
  local target="$2"
  local artifact_dir="$3"
  local ready=false

  for _ in $(seq 1 45); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      echo "kubectl port-forward exited early for ${target}." >&2
      cat "${artifact_dir}/port-forward.log" >&2 || true
      exit 1
    fi

    if curl -fsS --max-time 2 \
      -H "Host: ${APP_HOST}" \
      -H "X-Forwarded-Proto: https" \
      "http://127.0.0.1:${APP_PORT}${APP_PROBE_PATH}" \
      > "${artifact_dir}/probe-response.html" 2> "${artifact_dir}/probe.curl.log"; then
      if grep -Eiq "${APP_PROBE_PATTERN}" "${artifact_dir}/probe-response.html"; then
        ready=true
        break
      fi
    fi

    sleep 1
  done

  if [ "${ready}" != "true" ]; then
    echo "${target} did not pass the browser-observation probe through the port-forward." >&2
    cat "${artifact_dir}/port-forward.log" >&2 || true
    cat "${artifact_dir}/probe.curl.log" >&2 || true
    exit 1
  fi
}

capture_browser_artifacts() {
  local target="$1"
  local artifact_dir="$2"
  local browser_bin="$3"
  local url="$4"

  echo "Capturing ${target} browser screenshot and DOM with ${browser_bin}"
  "${browser_bin}" \
    --headless=new \
    --disable-gpu \
    --window-size="${VIEWPORT}" \
    --virtual-time-budget=10000 \
    --screenshot="${artifact_dir}/${target}-home.png" \
    "${url}" \
    > "${artifact_dir}/chromium-screenshot.log" 2>&1 || true

  "${browser_bin}" \
    --headless=new \
    --disable-gpu \
    --window-size="${VIEWPORT}" \
    --virtual-time-budget=10000 \
    --dump-dom \
    "${url}" \
    > "${artifact_dir}/${target}-home.html" 2> "${artifact_dir}/chromium-dom.log" || true
}

open_browser() {
  local url="$1"
  local artifact_dir="$2"

  if [ "${OPEN_BROWSER}" = "true" ]; then
    if command -v xdg-open >/dev/null 2>&1; then
      echo "Opening ${url}"
      xdg-open "${url}" > "${artifact_dir}/xdg-open.log" 2>&1 || true
    else
      echo "xdg-open is not available. Open this URL manually:"
      echo "  ${url}"
    fi
  else
    echo "Open this URL manually:"
    echo "  ${url}"
  fi
}

observe_one() {
  local target="$1"
  local artifact_dir="${ARTIFACT_ROOT}/${target}"
  local pid
  local local_url
  local human_url
  local browser_bin

  app_config "${target}"
  mkdir -p "${artifact_dir}"

  kubectl get service "${APP_SERVICE}" -n "${APP_NAMESPACE}" >/dev/null

  if [ "${PATCH_LOCAL_CONFIG}" = "true" ]; then
    patch_local_config "${target}" "${artifact_dir}"
  fi

  echo "Starting port-forward for ${target}: ${APP_NAMESPACE}/${APP_SERVICE} on localhost:${APP_PORT}"
  kubectl port-forward -n "${APP_NAMESPACE}" "svc/${APP_SERVICE}" "${APP_PORT}:80" \
    > "${artifact_dir}/port-forward.log" 2>&1 &
  pid="$!"
  PORT_FORWARD_PIDS+=("${pid}")

  wait_for_port_forward "${pid}" "${target}" "${artifact_dir}"

  local_url="http://127.0.0.1:${APP_PORT}/"
  human_url="http://localhost:${APP_PORT}/"
  if [ "${APP_CONFIG_KIND}" = "baserow" ] || [ "${APP_CONFIG_KIND}" = "twenty" ] || [ "${APP_CONFIG_KIND}" = "espocrm" ]; then
    human_url="${local_url}"
  fi

  cat > "${artifact_dir}/README.txt" <<EOF
${target} local observation

URL:
  ${human_url}

Local config patched:
  ${PATCH_LOCAL_CONFIG}

Backend/UI probe:
  curl -fsS -H "Host: ${APP_HOST}" -H "X-Forwarded-Proto: https" http://127.0.0.1:${APP_PORT}${APP_PROBE_PATH}

Artifacts:
  probe-response.html
  ${target}-home.png
  ${target}-home.html
  chromium-screenshot.log
  chromium-dom.log
  port-forward.log
EOF

  if [ "${CAPTURE_BROWSER}" = "true" ]; then
    browser_bin="$(find_chromium)"
    if [ -n "${browser_bin}" ]; then
      capture_browser_artifacts "${target}" "${artifact_dir}" "${browser_bin}" "${local_url}"
    else
      echo "No Chromium-compatible browser found for headless capture. Skipping screenshot/DOM capture."
    fi
  fi

  open_browser "${human_url}" "${artifact_dir}"

  echo ""
  echo "${target} observation artifacts:"
  echo "  ${artifact_dir}"
}

main() {
  local targets=("$@")
  local target

  if [ "${#targets[@]}" -eq 0 ]; then
    targets=(platform)
  fi

  for target in "${targets[@]}"; do
    case "${target}" in
      platform|wisemapping|leantime|baserow)
        ;;
      twenty|espocrm|optional-crm|crm-bakeoff)
        ;;
      *)
        echo "Unknown dev observe target: ${target}" >&2
        echo "Usage: scripts/dev-observe.sh [wisemapping|leantime|baserow|twenty|espocrm|optional-crm|crm-bakeoff|platform]" >&2
        exit 2
        ;;
    esac
  done

  ensure_context
  trap cleanup EXIT INT TERM

  for target in "${targets[@]}"; do
    case "${target}" in
      platform)
        observe_one wisemapping
        observe_one leantime
        observe_one baserow
        ;;
      optional-crm|crm-bakeoff)
        observe_one twenty
        observe_one espocrm
        ;;
      wisemapping|leantime|baserow|twenty|espocrm)
        observe_one "${target}"
        ;;
      *)
        echo "Unknown dev observe target: ${target}" >&2
        echo "Usage: scripts/dev-observe.sh [wisemapping|leantime|baserow|twenty|espocrm|optional-crm|crm-bakeoff|platform]" >&2
        exit 2
        ;;
    esac
  done

  echo ""
  echo "Observation artifact root:"
  echo "  ${ARTIFACT_ROOT}"

  if [ "${HOLD_OPEN}" = "true" ]; then
    echo ""
    echo "Port-forwards are still running. Press Ctrl-C when finished inspecting the app(s)."
    while true; do
      sleep 3600
    done
  fi
}

main "$@"
