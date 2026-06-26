#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/*}"
MODE="${1:-sandbox}"

usage() {
  echo "Usage: $0 [static|sandbox]"
}

case "${MODE}" in
  static)
    required=(git bash kubectl ansible-playbook)
    ;;
  sandbox)
    required=(git bash kubectl ansible-playbook docker k3d)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

missing=()
for command_name in "${required[@]}"; do
  command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
done

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Missing required commands: %s\n' "${missing[*]}" >&2
  exit 1
fi

if [ "${MODE}" = "sandbox" ] &&
   [ "${LOCAL_PREREQ_SKIP_DOCKER_INFO:-false}" != "true" ] &&
   ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but unavailable to this user." >&2
  echo "Start Docker and verify that 'docker info' works without sudo." >&2
  exit 1
fi

if [ "${LOCAL_PREREQ_SKIP_DISK:-false}" != "true" ]; then
  # shellcheck source=scripts/dev-preflight.sh
  source "${SCRIPT_DIR}/dev-preflight.sh"
  dev_preflight_check_disk "${PROJECT_ROOT}"
fi

echo "Local ${MODE} prerequisites passed."
if [ "${MODE}" = "static" ]; then
  echo "Next: ansible-playbook -i ansible/inventory.ini ansible/setup_dev_environment.yml -e local_dev_profile=static"
else
  echo "Next: ansible-playbook -i ansible/inventory.ini ansible/setup_dev_environment.yml"
fi
