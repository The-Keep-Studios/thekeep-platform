#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: bash scripts/restore-leantime-backup.sh /path/to/leantime_backup.sql.gz"
  exit 1
fi

backup_file="$1"
if [ ! -f "${backup_file}" ]; then
  echo "Backup file not found: ${backup_file}"
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

pod_name="$(kadmin get pod -n "${DB_NAMESPACE}" -l "${DB_LABEL_SELECTOR}" -o jsonpath='{.items[0].metadata.name}')"
if [ -z "${pod_name}" ]; then
  echo "No pod found for selector ${DB_LABEL_SELECTOR} in namespace ${DB_NAMESPACE}"
  exit 1
fi

echo "Restoring ${backup_file} into ${DB_NAMESPACE}/${pod_name} (${DB_NAME})"

if [[ "${backup_file}" == *.gz ]]; then
  gzip -dc "${backup_file}" | kadmin exec -i -n "${DB_NAMESPACE}" "${pod_name}" -- sh -ceu 'MYSQL_PWD="$1" mysql -u"$2" "$3"' -- "${DB_PASSWORD}" "${DB_USER}" "${DB_NAME}"
else
  cat "${backup_file}" | kadmin exec -i -n "${DB_NAMESPACE}" "${pod_name}" -- sh -ceu 'MYSQL_PWD="$1" mysql -u"$2" "$3"' -- "${DB_PASSWORD}" "${DB_USER}" "${DB_NAME}"
fi

echo "Restore completed."
