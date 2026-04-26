#!/usr/bin/env bash
# DEPRECATED: Use ansible-playbook with platform roles instead.
# See README.md for the new Ansible-first workflow.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
RENDERED_PROJECT="kubernetes/gitops/root/platform-project.yaml"
RENDERED_ROOT="kubernetes/gitops/root/platform-root.application.yaml"
RENDERED_APPS="kubernetes/gitops/apps/platform-applications.yaml"

if [ -z "${GITOPS_REPO_URL}" ]; then
  echo "Missing required environment variable: GITOPS_REPO_URL"
  echo "Example:"
  echo "  export GITOPS_REPO_URL=ssh://git@<host>/<path>/resolve-ansible-boilerplate.git"
  echo "  export GITOPS_REVISION=feature/productionReadyK8s"
  echo "  bash scripts/bootstrap-gitops.sh"
  exit 1
fi

for required_file in "${RENDERED_PROJECT}" "${RENDERED_ROOT}" "${RENDERED_APPS}"; do
  if [ ! -f "${required_file}" ]; then
    echo "Missing rendered GitOps file: ${required_file}"
    echo "Run scripts/render-gitops-apps.sh, commit the rendered files, and re-run bootstrap."
    exit 1
  fi
done

if grep -R "REPLACE_ME_GITOPS_" "${RENDERED_PROJECT}" "${RENDERED_ROOT}" "${RENDERED_APPS}" >/dev/null 2>&1; then
  echo "Rendered GitOps files still contain placeholders."
  echo "Run scripts/render-gitops-apps.sh with GITOPS_REPO_URL and GITOPS_REVISION, then commit the results."
  exit 1
fi

for rendered_file in "${RENDERED_PROJECT}" "${RENDERED_ROOT}" "${RENDERED_APPS}"; do
  if ! grep -F "${GITOPS_REPO_URL}" "${rendered_file}" >/dev/null 2>&1; then
    echo "Rendered GitOps file ${rendered_file} does not match GITOPS_REPO_URL=${GITOPS_REPO_URL}"
    echo "Run scripts/render-gitops-apps.sh, commit the rendered files, and re-run bootstrap."
    exit 1
  fi
done

for rendered_file in "${RENDERED_ROOT}" "${RENDERED_APPS}"; do
  if ! grep -F "targetRevision: ${GITOPS_REVISION}" "${rendered_file}" >/dev/null 2>&1; then
    echo "Rendered GitOps file ${rendered_file} does not match GITOPS_REVISION=${GITOPS_REVISION}"
    echo "Run scripts/render-gitops-apps.sh, commit the rendered files, and re-run bootstrap."
    exit 1
  fi
done

kadmin() {
  sudo -u k3s-admin -H env KUBECONFIG=/home/k3s-admin/.kube/config kubectl "$@"
}

if ! kadmin get nodes >/dev/null 2>&1; then
  echo "Cannot reach cluster as k3s-admin."
  echo "Bootstrap k3s first via ansible/setup_k3s_production.yml."
  exit 1
fi

echo "Installing/updating Argo CD..."
kadmin apply -k kubernetes/platform/argocd
kadmin wait --for=condition=available --timeout=900s deployment/argocd-server -n argocd

echo "Applying AppProject..."
kadmin apply -f "${RENDERED_PROJECT}"

if [ "$(kadmin get secret -n argocd -l argocd.argoproj.io/secret-type=repository --no-headers 2>/dev/null | wc -l)" -eq 0 ]; then
  echo "No Argo CD repository secret detected."
  echo "If repo access is private SSH, run:"
  echo "  export GITOPS_SSH_PRIVATE_KEY_PATH=/path/to/key"
  echo "  bash scripts/argocd-configure-repo-ssh.sh"
fi

echo "Applying platform applications..."
kadmin apply -f "${RENDERED_APPS}"
kadmin apply -f "${RENDERED_ROOT}"

echo "Waiting for root app to reconcile..."
kadmin wait --for=jsonpath='{.status.sync.status}'=Synced --timeout=900s application/platform-root -n argocd
kadmin wait --for=jsonpath='{.status.health.status}'=Healthy --timeout=900s application/platform-root -n argocd

echo ""
echo "GitOps bootstrap complete."
echo "Argo CD URL: https://argocd.thekeepstudios.com"
echo "Repo URL: ${GITOPS_REPO_URL}"
echo "Revision: ${GITOPS_REVISION}"
echo "Next: run launch gate validation with bash scripts/validate-production-gate.sh"
