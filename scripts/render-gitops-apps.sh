#!/usr/bin/env bash
# DEPRECATED: Rendering is now handled by the platform_gitops Ansible role.
# See README.md for the new Ansible-first workflow.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

GITOPS_REPO_URL="${GITOPS_REPO_URL:-}"
GITOPS_REVISION="${GITOPS_REVISION:-}"

if [ -z "${GITOPS_REPO_URL}" ]; then
  GITOPS_REPO_URL="$(git config --get remote.origin.url || true)"
fi

if [ -z "${GITOPS_REVISION}" ]; then
  GITOPS_REVISION="$(git branch --show-current || true)"
fi

if [ -z "${GITOPS_REPO_URL}" ] || [ -z "${GITOPS_REVISION}" ]; then
  echo "Missing GitOps source."
  echo "Set GITOPS_REPO_URL and GITOPS_REVISION, then re-run this script."
  exit 1
fi

render_template() {
  local template="$1"
  local output="$2"

  sed \
    -e "s|REPLACE_ME_GITOPS_REPO_URL|${GITOPS_REPO_URL}|g" \
    -e "s|REPLACE_ME_GITOPS_REVISION|${GITOPS_REVISION}|g" \
    "${template}" > "${output}"
}

render_template kubernetes/gitops/templates/platform-project.yaml kubernetes/gitops/root/platform-project.yaml
render_template kubernetes/gitops/templates/platform-root.application.yaml kubernetes/gitops/root/platform-root.application.yaml
render_template kubernetes/gitops/templates/platform-applications.yaml kubernetes/gitops/apps/platform-applications.yaml

echo "Rendered GitOps desired state:"
echo "  Repo URL: ${GITOPS_REPO_URL}"
echo "  Revision: ${GITOPS_REVISION}"
echo ""
echo "Review, commit, and push these files before bootstrapping Argo CD:"
echo "  kubernetes/gitops/root/platform-project.yaml"
echo "  kubernetes/gitops/root/platform-root.application.yaml"
echo "  kubernetes/gitops/apps/platform-applications.yaml"
