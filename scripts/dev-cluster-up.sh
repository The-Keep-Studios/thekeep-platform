#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

# shellcheck source=scripts/dev-preflight.sh
source "${SCRIPT_DIR}/dev-preflight.sh"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"
K3S_VERSION="${K3S_VERSION:-v1.35.3+k3s1}"
K3D_IMAGE="${K3D_IMAGE:-rancher/k3s:${K3S_VERSION/+/-}}"
K3D_WAIT_TIMEOUT="${K3D_WAIT_TIMEOUT:-180s}"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd k3d
require_cmd kubectl

dev_preflight_check_disk "${PROJECT_ROOT}"

if k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "k3d cluster already exists: ${CLUSTER_NAME}"
else
  echo "Creating k3d cluster ${CLUSTER_NAME} with image ${K3D_IMAGE}"
  k3d cluster create "${CLUSTER_NAME}" \
    --image "${K3D_IMAGE}" \
    --servers 1 \
    --agents 0 \
    --wait \
    --timeout "${K3D_WAIT_TIMEOUT}"
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
kubectl get nodes
