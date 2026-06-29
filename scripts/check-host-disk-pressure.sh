#!/usr/bin/env bash
set -euo pipefail

HOST_DISK_CHECK_PATHS="${HOST_DISK_CHECK_PATHS:-/}"
HOST_DISK_MIN_FREE_GIB="${HOST_DISK_MIN_FREE_GIB:-20}"
HOST_DISK_MAX_USED_PERCENT="${HOST_DISK_MAX_USED_PERCENT:-85}"
HOST_DISK_KUBERNETES_MODE="${HOST_DISK_KUBERNETES_MODE:-auto}"

failures=0

log() {
  printf '\n== %s ==\n' "$*"
}

record_failure() {
  failures=1
  printf 'FAIL: %s\n' "$*" >&2
}

record_info() {
  printf 'INFO: %s\n' "$*"
}

record_pass() {
  printf 'PASS: %s\n' "$*"
}

check_numeric_thresholds() {
  case "${HOST_DISK_MIN_FREE_GIB}" in
    ''|*[!0-9.]*)
      record_failure "HOST_DISK_MIN_FREE_GIB must be numeric."
      ;;
  esac
  case "${HOST_DISK_MAX_USED_PERCENT}" in
    ''|*[!0-9]*)
      record_failure "HOST_DISK_MAX_USED_PERCENT must be an integer."
      ;;
  esac
  case "${HOST_DISK_KUBERNETES_MODE}" in
    auto|require|skip) ;;
    *)
      record_failure "HOST_DISK_KUBERNETES_MODE must be auto, require, or skip."
      ;;
  esac
}

disk_below_min_free() {
  local available_kib="$1"
  awk -v available_kib="${available_kib}" -v min_gib="${HOST_DISK_MIN_FREE_GIB}" \
    'BEGIN { exit !(available_kib < (min_gib * 1024 * 1024)) }'
}

disk_above_max_used() {
  local used_percent="$1"
  [ "${used_percent}" -gt "${HOST_DISK_MAX_USED_PERCENT}" ]
}

format_gib() {
  local kib="$1"
  awk -v kib="${kib}" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }'
}

check_filesystem_path() {
  local path="$1"
  local df_line
  local filesystem
  local size_kib
  local used_kib
  local available_kib
  local used_percent
  local mountpoint
  local free_gib

  if [ ! -e "${path}" ]; then
    record_failure "disk check path does not exist: ${path}"
    return
  fi

  df_line="$(df -Pk "${path}" | awk 'NR == 2 {print}')"
  if [ -z "${df_line}" ]; then
    record_failure "unable to read filesystem usage for ${path}"
    return
  fi

  read -r filesystem size_kib used_kib available_kib used_percent mountpoint <<<"${df_line}"
  used_percent="${used_percent%%%}"
  free_gib="$(format_gib "${available_kib}")"

  printf 'PATH %s mount=%s filesystem=%s used=%s%% free_gib=%s total_gib=%s\n' \
    "${path}" \
    "${mountpoint}" \
    "${filesystem}" \
    "${used_percent}" \
    "${free_gib}" \
    "$(format_gib "${size_kib}")"

  if disk_below_min_free "${available_kib}"; then
    record_failure "${path} has ${free_gib} GiB free; minimum is ${HOST_DISK_MIN_FREE_GIB} GiB."
  fi

  if disk_above_max_used "${used_percent}"; then
    record_failure "${path} is ${used_percent}% used; maximum is ${HOST_DISK_MAX_USED_PERCENT}%."
  fi
}

check_kubernetes_disk_pressure() {
  local disk_pressure_jsonpath
  local node_status

  case "${HOST_DISK_KUBERNETES_MODE}" in
    skip)
      record_info "skipping Kubernetes DiskPressure check by request."
      return
      ;;
  esac

  if ! command -v kubectl >/dev/null 2>&1; then
    if [ "${HOST_DISK_KUBERNETES_MODE}" = "require" ]; then
      record_failure "kubectl is required but is not installed."
    else
      record_info "kubectl not installed; skipping Kubernetes DiskPressure check."
    fi
    return
  fi

  disk_pressure_jsonpath='{range .items[*]}'
  disk_pressure_jsonpath+='{.metadata.name}{"\t"}'
  disk_pressure_jsonpath+='{range .status.conditions[?(@.type=="DiskPressure")]}'
  disk_pressure_jsonpath+='{.status}{"\t"}{.reason}{"\t"}{.message}'
  disk_pressure_jsonpath+='{end}{"\n"}{end}'

  if ! node_status="$(kubectl get nodes -o jsonpath="${disk_pressure_jsonpath}" 2>/dev/null)"; then
    if [ "${HOST_DISK_KUBERNETES_MODE}" = "require" ]; then
      record_failure "unable to read Kubernetes node DiskPressure status."
    else
      record_info "no reachable Kubernetes cluster; skipping DiskPressure check."
    fi
    return
  fi

  if [ -z "${node_status}" ]; then
    if [ "${HOST_DISK_KUBERNETES_MODE}" = "require" ]; then
      record_failure "no Kubernetes nodes were returned."
    else
      record_info "no Kubernetes nodes returned; skipping DiskPressure check."
    fi
    return
  fi

  while IFS=$'\t' read -r node status reason message; do
    [ -n "${node}" ] || continue
    case "${status}" in
      False)
        record_pass "node ${node} DiskPressure=False"
        ;;
      True|Unknown)
        record_failure \
          "node ${node} DiskPressure=${status} reason=${reason:-unknown} message=${message:-none}"
        ;;
      *)
        record_failure "node ${node} has unexpected DiskPressure status: ${status:-missing}"
        ;;
    esac
  done <<<"${node_status}"
}

log "Host filesystem usage"
check_numeric_thresholds
for path in ${HOST_DISK_CHECK_PATHS}; do
  check_filesystem_path "${path}"
done

log "Kubernetes node DiskPressure"
check_kubernetes_disk_pressure

if [ "${failures}" -ne 0 ]; then
  cat >&2 <<EOF

Host disk pressure check failed.

This script is read-only. It does not delete snapshots, prune containers, or
change Kubernetes state. Follow the Host Disk Pressure Check section in README.md
for triage and manual cleanup guidance.
EOF
  exit 1
fi

record_pass "host disk pressure checks passed"
