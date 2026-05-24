#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"
ANSIBLE_REMOTE_TMP="${ANSIBLE_REMOTE_TMP:-/tmp/ansible-remote}"
IAC_STATIC_INCLUDE_REMOTE="${IAC_STATIC_INCLUDE_REMOTE:-false}"
export ANSIBLE_LOCAL_TEMP ANSIBLE_REMOTE_TMP

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/thekeep-iac-static.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

log() {
  printf '\n== %s ==\n' "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_cmd git
require_cmd bash
require_cmd kubectl
require_cmd ansible-playbook

log "Git whitespace check"
git diff --check

log "Shell syntax check"
while IFS= read -r script; do
  bash -n "${script}"
done < <(find scripts -maxdepth 1 -type f -name "*.sh" | sort)

log "Kustomize render check"
while IFS= read -r kustomization; do
  dir="$(dirname "${kustomization}")"
  if [ "${IAC_STATIC_INCLUDE_REMOTE}" != "true" ] && grep -Eq 'https?://|github.com' "${kustomization}"; then
    echo "skip ${dir} (remote bases; set IAC_STATIC_INCLUDE_REMOTE=true to render)"
    continue
  fi
  out="${tmp_dir}/$(echo "${dir}" | tr '/.' '__').yaml"
  echo "render ${dir}"
  kubectl kustomize "${dir}" > "${out}"
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -ignore-missing-schemas "${out}"
  elif command -v kubeval >/dev/null 2>&1; then
    kubeval --ignore-missing-schemas "${out}"
  fi
done < <(find kubernetes -name kustomization.yaml | sort)

log "Ansible syntax check"
inventory="ansible/inventory.production.ini"
if [ ! -f "${inventory}" ]; then
  inventory="ansible/inventory.production.ini.example"
fi
ansible-playbook --syntax-check -i "${inventory}" ansible/setup_k3s_production.yml

log "Static IaC checks passed"
