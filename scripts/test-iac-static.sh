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
for playbook in \
  ansible/setup_k3s_production.yml \
  ansible/configure_espocrm_email.yml
do
  ansible-playbook --syntax-check -i "${inventory}" "${playbook}"
done

log "EspoCRM email configuration validation"
validation_inventory="${tmp_dir}/inventory.ini"
validation_playbook="${tmp_dir}/espocrm-email-validation.yml"
force_guard_playbook="${tmp_dir}/espocrm-email-force-guard.yml"
ansible_roles_path="${PROJECT_ROOT}/ansible/roles${ANSIBLE_ROLES_PATH:+:${ANSIBLE_ROLES_PATH}}"

cat > "${validation_inventory}" <<'EOF'
[k3s_control_plane]
localhost ansible_connection=local ansible_become=false
EOF

cat > "${validation_playbook}" <<'EOF'
- name: Validate EspoCRM email configuration inputs
  hosts: k3s_control_plane
  gather_facts: false
  tasks:
    - name: Validate and resolve configuration
      ansible.builtin.import_role:
        name: espocrm_email_config
        tasks_from: validate

    - name: Assert expected resolved allowlist
      ansible.builtin.assert:
        that:
          - espocrm_email_server_allowed_address_list == expected_allowlist
      when: expected_allowlist is defined
EOF

cat > "${force_guard_playbook}" <<'EOF'
- name: Validate focused-playbook configuration guard
  hosts: k3s_control_plane
  gather_facts: false
  roles:
    - role: espocrm_email_config
      vars:
        espocrm_email_config_force: true
EOF

ANSIBLE_ROLES_PATH="${ansible_roles_path}" ansible-playbook \
  -i "${validation_inventory}" \
  "${validation_playbook}" \
  -e '{"platform_optional_apps":{"espocrm":{"email_server_allowlist_profile":"gmail"}},"expected_allowlist":["imap.gmail.com:993","smtp.gmail.com:587","smtp.gmail.com:465"]}'

if ANSIBLE_ROLES_PATH="${ansible_roles_path}" ansible-playbook \
  -i "${validation_inventory}" \
  "${validation_playbook}" \
  -e '{"platform_optional_apps":{"espocrm":{"email_server_allowed_address_list":["*.gmail.com:993"]}}}'; then
  echo "Wildcard EspoCRM email allowlist entry was accepted unexpectedly" >&2
  exit 1
else
  echo "Rejected wildcard EspoCRM email allowlist entry as expected"
fi

if ANSIBLE_ROLES_PATH="${ansible_roles_path}" ansible-playbook \
  -i "${validation_inventory}" \
  "${validation_playbook}" \
  -e '{"platform_optional_apps":{"espocrm":{"email_server_allowlist_profile":"gmail","email_server_allowed_address_list":["imap.gmail.com:993"]}}}'; then
  echo "Conflicting EspoCRM email profile and explicit list were accepted unexpectedly" >&2
  exit 1
else
  echo "Rejected conflicting EspoCRM email profile and explicit list as expected"
fi

if ANSIBLE_ROLES_PATH="${ansible_roles_path}" ansible-playbook \
  -i "${validation_inventory}" \
  "${force_guard_playbook}"; then
  echo "Focused EspoCRM email playbook guard accepted an empty configuration unexpectedly" >&2
  exit 1
else
  echo "Rejected empty focused EspoCRM email configuration as expected"
fi

log "Static IaC checks passed"
