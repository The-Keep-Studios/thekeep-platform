#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/local-prereqs-test.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_stub() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${tmp_dir}/$1"
  chmod +x "${tmp_dir}/$1"
}

for name in git bash kubectl ansible-playbook docker k3d; do
  make_stub "${name}"
done

PATH="${tmp_dir}" \
LOCAL_PREREQ_SKIP_DISK=true \
LOCAL_PREREQ_SKIP_DOCKER_INFO=true \
  /bin/bash "${SCRIPT_DIR}/check-local-prereqs.sh" sandbox >/dev/null

mv "${tmp_dir}/kubectl" "${tmp_dir}/kubectl.disabled"
if PATH="${tmp_dir}" LOCAL_PREREQ_SKIP_DISK=true \
   /bin/bash "${SCRIPT_DIR}/check-local-prereqs.sh" static >/dev/null 2>&1; then
  echo "Missing kubectl was accepted unexpectedly" >&2
  exit 1
fi

echo "Local prerequisite checker tests passed."
