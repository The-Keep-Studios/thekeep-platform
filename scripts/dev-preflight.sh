#!/usr/bin/env bash

dev_preflight_check_disk() {
  local path="${1:-.}"
  local min_free_gib="${DEV_MIN_FREE_GIB:-80}"
  local min_free_percent="${DEV_MIN_FREE_PERCENT:-8}"
  local df_values
  local size_kib
  local avail_kib
  local avail_gib
  local free_percent

  if [ "${DEV_SKIP_DISK_PREFLIGHT:-false}" = "true" ]; then
    return 0
  fi

  df_values="$(df -Pk "${path}" | awk 'NR == 2 { print $2 " " $4 }')"
  read -r size_kib avail_kib <<< "${df_values}"

  if [ -z "${size_kib:-}" ] || [ -z "${avail_kib:-}" ] || [ "${size_kib}" -le 0 ]; then
    echo "Unable to determine available disk space for ${path}" >&2
    return 1
  fi

  avail_gib=$((avail_kib / 1024 / 1024))
  free_percent=$((avail_kib * 100 / size_kib))

  if [ "${avail_gib}" -lt "${min_free_gib}" ] || [ "${free_percent}" -lt "${min_free_percent}" ]; then
    cat >&2 <<EOF
Local disk preflight failed for ${path}.

Available: ${avail_gib} GiB (${free_percent}%)
Required:  ${min_free_gib} GiB and ${min_free_percent}%

k3d/k3s uses the host filesystem as node ephemeral storage. When the host is
near full, Kubernetes applies disk-pressure taints and evicts local app pods.

Free disk space, lower DEV_MIN_FREE_GIB/DEV_MIN_FREE_PERCENT for a constrained
single-app test, or set DEV_SKIP_DISK_PREFLIGHT=true if you deliberately want to
continue.
EOF
    return 1
  fi
}

dev_preflight_check_kubernetes_node_pressure() {
  local taints
  local pressure_taints

  if [ "${DEV_SKIP_NODE_PRESSURE_PREFLIGHT:-false}" = "true" ]; then
    return 0
  fi

  taints="$(
    kubectl get nodes \
      -o 'custom-columns=NAME:.metadata.name,TAINTS:.spec.taints[*].key' \
      --no-headers 2>/dev/null || true
  )"

  pressure_taints="$(
    printf '%s\n' "${taints}" |
      grep -E 'node\.kubernetes\.io/(disk-pressure|memory-pressure|pid-pressure)' || true
  )"

  if [ -n "${pressure_taints}" ]; then
    cat >&2 <<EOF
Local Kubernetes node preflight failed.

The local k3d node has a pressure taint:
${pressure_taints}

Do not run smoke or observe workflows until this clears. For disk pressure,
free host disk space, then recreate the local cluster with:

  scripts/dev-cluster-down.sh
  scripts/dev-smoke.sh platform

Set DEV_SKIP_NODE_PRESSURE_PREFLIGHT=true only if you deliberately want to
continue against a degraded local cluster.
EOF
    return 1
  fi
}
