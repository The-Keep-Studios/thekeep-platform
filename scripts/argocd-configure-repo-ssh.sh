#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${GITOPS_REPO_URL:-}"
SSH_KEY_PATH="${GITOPS_SSH_PRIVATE_KEY_PATH:-}"
SECRET_NAME="${GITOPS_REPO_SECRET_NAME:-platform-gitops-repo}"

if [ -z "${REPO_URL}" ] || [ -z "${SSH_KEY_PATH}" ]; then
  echo "Usage:"
  echo "  export GITOPS_REPO_URL=ssh://git@<host>/<path>/resolve-ansible-boilerplate.git"
  echo "  export GITOPS_SSH_PRIVATE_KEY_PATH=/path/to/private/key"
  echo "  bash scripts/argocd-configure-repo-ssh.sh"
  exit 1
fi

if [ ! -f "${SSH_KEY_PATH}" ]; then
  echo "Missing SSH key file: ${SSH_KEY_PATH}"
  exit 1
fi

if [[ "${REPO_URL}" == ssh://*@* ]]; then
  host="$(echo "${REPO_URL}" | sed -E 's#ssh://[^@]+@([^/:]+).*$#\1#')"
elif [[ "${REPO_URL}" == *@*:* ]]; then
  host="${REPO_URL#*@}"
  host="${host%%:*}"
else
  host=""
fi

if [ -z "${host}" ]; then
  echo "Could not parse host from GITOPS_REPO_URL: ${REPO_URL}"
  exit 1
fi

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

echo "Ensuring argocd namespace..."
kadmin create namespace argocd --dry-run=client -o yaml | kadmin apply -f -

known_hosts="$(ssh-keyscan -H "${host}" 2>/dev/null || true)"
if [ -z "${known_hosts}" ]; then
  echo "Warning: unable to fetch known_hosts entry for ${host}. Repo access may fail."
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

cat > "${tmp_file}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${REPO_URL}
  sshPrivateKey: |
$(sed 's/^/    /' "${SSH_KEY_PATH}")
  insecure: "false"
  enableLfs: "true"
EOF

if [ -n "${known_hosts}" ]; then
  {
    echo "  sshKnownHosts: |"
    echo "${known_hosts}" | sed 's/^/    /'
  } >> "${tmp_file}"
fi

kadmin apply -f "${tmp_file}"
echo "Configured Argo CD repository secret: ${SECRET_NAME}"
