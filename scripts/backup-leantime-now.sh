#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_BACKUP_ROOT="${HOME:-/tmp}/resolve-platform-backups"
BACKUP_DIR="${BACKUP_DIR:-${DEFAULT_BACKUP_ROOT}/leantime}"

if [ -f "${SCRIPT_DIR}/production.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/production.env"
fi

DB_NAMESPACE="${DB_NAMESPACE:-default}"
DB_LABEL_SELECTOR="${DB_LABEL_SELECTOR:-app=leantime-mariadb}"
DB_NAME="${DB_NAME:-leantime}"
DB_USER="${DB_USER:-leantime_user}"
DB_PASSWORD="${DB_PASSWORD:-${LEANTIME_DB_PASSWORD:-}}"

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

if ! kadmin get nodes >/dev/null 2>&1; then
  echo "Cannot reach cluster as k3s-admin."
  exit 1
fi

if [ -z "${DB_PASSWORD}" ]; then
  DB_PASSWORD="$(kadmin get secret leantime-db -n "${DB_NAMESPACE}" -o jsonpath='{.data.MYSQL_PASSWORD}' 2>/dev/null | base64 -d || true)"
fi

if [ -z "${DB_PASSWORD}" ]; then
  echo "Missing Leantime database password."
  echo "Set LEANTIME_DB_PASSWORD in scripts/production.env or seed the leantime-db secret first."
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

pod_name="$(kadmin get pod -n "${DB_NAMESPACE}" -l "${DB_LABEL_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
if [ -z "${pod_name}" ]; then
  echo "No pod found for selector ${DB_LABEL_SELECTOR} in namespace ${DB_NAMESPACE}"
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_file="${BACKUP_DIR}/leantime_${timestamp}.sql.gz"

dump_cmd='dump_bin="mariadb-dump"; if ! command -v "${dump_bin}" >/dev/null 2>&1; then dump_bin="mysqldump"; fi; MYSQL_PWD="$1" "${dump_bin}" --single-transaction --quick -u"$2" "$3"'

echo "Creating backup: ${output_file}"
kadmin exec -n "${DB_NAMESPACE}" "${pod_name}" -- sh -ceu "${dump_cmd}" -- "${DB_PASSWORD}" "${DB_USER}" "${DB_NAME}" | gzip > "${output_file}"

echo "Backup complete: ${output_file}"
