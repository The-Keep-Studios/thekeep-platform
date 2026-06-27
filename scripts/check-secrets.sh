#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "${PROJECT_ROOT}"

failures=0

log() {
  printf '\n== %s ==\n' "$*"
}

record_failure() {
  failures=1
  printf '%s\n' "$*" >&2
}

is_binary() {
  ! LC_ALL=C grep -Iq . "$1"
}

scan_file() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  local matches

  if is_binary "${file}"; then
    return
  fi

  matches="$(LC_ALL=C grep -n -E -- "${pattern}" "${file}" || true)"
  if [ -n "${matches}" ]; then
    record_failure "possible secret exposure: ${description} in ${file}"
    printf '%s\n' "${matches}" >&2
  fi
}

check_private_path() {
  local file="$1"

  case "${file}" in
    ansible/production_vars.yml|ansible/inventory.production.ini|scripts/production.env)
      record_failure "private installation config is tracked or staged: ${file}"
      ;;
    *.kubeconfig|*/kubeconfig|kubeconfig|*.pem|*.key|*id_rsa|*id_ed25519|*id_ecdsa)
      record_failure "high-risk credential filename is tracked or staged: ${file}"
      ;;
  esac
}

log "Secret exposure scan"

while IFS= read -r file; do
  [ -f "${file}" ] || continue

  check_private_path "${file}"
  scan_file "${file}" '-----BEGIN ((RSA|DSA|EC|OPENSSH|PGP) )?PRIVATE KEY( BLOCK)?-----' "private key block"
  scan_file "${file}" '(^|[^A-Za-z0-9_])ghp_[A-Za-z0-9_]{36,}' "GitHub classic token"
  scan_file "${file}" 'github_pat_[A-Za-z0-9_]{20,}' "GitHub fine-grained token"
  scan_file "${file}" 'xox[baprs]-[A-Za-z0-9-]{20,}' "Slack token"
  scan_file "${file}" 'AKIA[0-9A-Z]{16}' "AWS access key id"
  scan_file "${file}" 'AIza[0-9A-Za-z_-]{35}' "Google API key"
  scan_file "${file}" '(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{32,}' "OpenAI-style API key"
  scan_file "${file}" '^[[:space:]]*client-key-data:[[:space:]]*[^#[:space:]]+' "kubeconfig client private key"
done < <(git ls-files --cached --others --exclude-standard | sort -u)

if [ "${failures}" -ne 0 ]; then
  printf '\nSecret exposure scan failed. Remove the secret or move private installation config to ignored local files.\n' >&2
  exit 1
fi

echo "Secret exposure scan passed."
