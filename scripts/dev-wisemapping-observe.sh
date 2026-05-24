#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"
NAMESPACE="${WISEMAPPING_NAMESPACE:-wisemapping}"
SERVICE="${WISEMAPPING_SERVICE:-wisemapping}"
LOCAL_PORT="${WISEMAPPING_OBSERVE_PORT:-18081}"
PROBE_HOST="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
OPEN_BROWSER="${WISEMAPPING_OBSERVE_OPEN:-true}"
CAPTURE_BROWSER="${WISEMAPPING_OBSERVE_CAPTURE:-true}"
HOLD_OPEN="${WISEMAPPING_OBSERVE_HOLD:-true}"
VIEWPORT="${WISEMAPPING_OBSERVE_VIEWPORT:-1440,1000}"
PATCH_LOCAL_CONFIG="${WISEMAPPING_OBSERVE_PATCH_CONFIG:-true}"
ARTIFACT_DIR="${WISEMAPPING_OBSERVE_ARTIFACT_DIR:-.artifacts/wisemapping-observe/$(date -u +%Y%m%dT%H%M%SZ)}"

PORT_FORWARD_PID=""

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

cleanup() {
  if [ -n "${PORT_FORWARD_PID}" ] && kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}

find_chromium() {
  command -v chromium 2>/dev/null ||
    command -v chromium-browser 2>/dev/null ||
    command -v google-chrome 2>/dev/null ||
    command -v google-chrome-stable 2>/dev/null ||
    true
}

wait_for_port_forward() {
  local ready=false

  for _ in $(seq 1 45); do
    if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
      echo "kubectl port-forward exited early." >&2
      cat "${ARTIFACT_DIR}/port-forward.log" >&2 || true
      exit 1
    fi

    if curl -fsS --max-time 2 \
      -H "Host: ${PROBE_HOST}" \
      -H "X-Forwarded-Proto: https" \
      "http://127.0.0.1:${LOCAL_PORT}/api/restful/app/config" \
      > "${ARTIFACT_DIR}/api-config.json" 2> "${ARTIFACT_DIR}/api-config.curl.log"; then
      ready=true
      break
    fi

    sleep 1
  done

  if [ "${ready}" != "true" ]; then
    echo "WiseMapping did not answer the backend config endpoint through the port-forward." >&2
    cat "${ARTIFACT_DIR}/port-forward.log" >&2 || true
    cat "${ARTIFACT_DIR}/api-config.curl.log" >&2 || true
    exit 1
  fi
}

patch_local_config() {
  local local_base_url="http://localhost:${LOCAL_PORT}"
  local config_file="${ARTIFACT_DIR}/application.local.yml"

  echo "Patching local WiseMapping config for browser observation: ${local_base_url}"
  kubectl get configmap wisemapping-config -n "${NAMESPACE}" \
    -o jsonpath='{.data.application\.yml}' \
    > "${ARTIFACT_DIR}/application.original.yml"

  sed \
    -e "s|https://mindmaps.thekeepstudios.com|${local_base_url}|g" \
    -e "s|http://mindmaps.thekeepstudios.com|${local_base_url}|g" \
    "${ARTIFACT_DIR}/application.original.yml" > "${config_file}"

  kubectl create configmap wisemapping-config -n "${NAMESPACE}" \
    --from-file=application.yml="${config_file}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

  kubectl rollout restart deployment/wisemapping -n "${NAMESPACE}"
  kubectl rollout status deployment/wisemapping -n "${NAMESPACE}" --timeout=10m
}

capture_browser_artifacts() {
  local browser_bin="$1"
  local url="$2"

  echo "Capturing browser screenshot and DOM with ${browser_bin}"
  "${browser_bin}" \
    --headless=new \
    --disable-gpu \
    --window-size="${VIEWPORT}" \
    --virtual-time-budget=10000 \
    --screenshot="${ARTIFACT_DIR}/wisemapping-home.png" \
    "${url}" \
    > "${ARTIFACT_DIR}/chromium-screenshot.log" 2>&1 || true

  "${browser_bin}" \
    --headless=new \
    --disable-gpu \
    --window-size="${VIEWPORT}" \
    --virtual-time-budget=10000 \
    --dump-dom \
    "${url}" \
    > "${ARTIFACT_DIR}/wisemapping-home.html" 2> "${ARTIFACT_DIR}/chromium-dom.log" || true
}

require_cmd kubectl
require_cmd curl

mkdir -p "${ARTIFACT_DIR}"
trap cleanup EXIT INT TERM

if command -v k3d >/dev/null 2>&1 && k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
fi

kubectl get service "${SERVICE}" -n "${NAMESPACE}" >/dev/null

if [ "${PATCH_LOCAL_CONFIG}" = "true" ]; then
  patch_local_config
fi

echo "Starting port-forward for ${NAMESPACE}/${SERVICE} on localhost:${LOCAL_PORT}"
kubectl port-forward -n "${NAMESPACE}" "svc/${SERVICE}" "${LOCAL_PORT}:80" \
  > "${ARTIFACT_DIR}/port-forward.log" 2>&1 &
PORT_FORWARD_PID="$!"

wait_for_port_forward

local_url="http://127.0.0.1:${LOCAL_PORT}/"
human_url="http://localhost:${LOCAL_PORT}/"

cat > "${ARTIFACT_DIR}/README.txt" <<EOF
WiseMapping local observation

URL:
  ${human_url}

Local config patched:
  ${PATCH_LOCAL_CONFIG}

Backend API probe:
  curl -fsS -H "Host: ${PROBE_HOST}" -H "X-Forwarded-Proto: https" http://127.0.0.1:${LOCAL_PORT}/api/restful/app/config

Artifacts:
  api-config.json
  wisemapping-home.png
  wisemapping-home.html
  chromium-screenshot.log
  chromium-dom.log
  port-forward.log
EOF

if [ "${CAPTURE_BROWSER}" = "true" ]; then
  browser_bin="$(find_chromium)"
  if [ -n "${browser_bin}" ]; then
    capture_browser_artifacts "${browser_bin}" "${local_url}"
  else
    echo "No Chromium-compatible browser found for headless capture. Skipping screenshot/DOM capture."
  fi
fi

if [ "${OPEN_BROWSER}" = "true" ]; then
  if command -v xdg-open >/dev/null 2>&1; then
    echo "Opening ${human_url}"
    xdg-open "${human_url}" > "${ARTIFACT_DIR}/xdg-open.log" 2>&1 || true
  else
    echo "xdg-open is not available. Open this URL manually:"
    echo "  ${human_url}"
  fi
else
  echo "Open this URL manually:"
  echo "  ${human_url}"
fi

echo ""
echo "Observation artifacts:"
echo "  ${ARTIFACT_DIR}"

if [ "${HOLD_OPEN}" = "true" ]; then
  echo ""
  echo "Port-forward is still running. Press Ctrl-C when finished inspecting the app."
  while true; do
    sleep 3600
  done
fi
