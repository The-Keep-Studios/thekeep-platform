#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${K3D_CLUSTER_NAME:-thekeep-dev}"

if ! command -v k3d >/dev/null 2>&1; then
  echo "Missing required command: k3d" >&2
  exit 1
fi

if k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  k3d cluster delete "${CLUSTER_NAME}"
else
  echo "k3d cluster does not exist: ${CLUSTER_NAME}"
fi
