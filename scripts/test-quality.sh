#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
QUALITY_STRICT="${QUALITY_STRICT:-false}"
QUALITY_REQUIRE_ACTIONLINT="${QUALITY_REQUIRE_ACTIONLINT:-false}"
cd "${PROJECT_ROOT}"
export ANSIBLE_STDOUT_CALLBACK="${ANSIBLE_STDOUT_CALLBACK:-default}"

log() {
  printf '\n== %s ==\n' "$*"
}

repo_files() {
  git ls-files --cached --others --exclude-standard -- "$@" | sort -u
}

count_repo_files() {
  repo_files "$@" | wc -l | tr -d '[:space:]'
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

run_actionlint() {
  local workflow_files=()
  mapfile -t workflow_files < <(repo_files '.github/workflows/*.yml' '.github/workflows/*.yaml')
  if [ "${#workflow_files[@]}" -eq 0 ]; then
    echo "skip actionlint: no GitHub workflow files"
    return
  fi

  if command_available actionlint; then
    actionlint "${workflow_files[@]}"
  elif [ "${QUALITY_REQUIRE_ACTIONLINT}" = "true" ]; then
    echo "Missing required command: actionlint" >&2
    exit 1
  else
    echo "skip actionlint: not installed"
  fi
}

run_optional_linters() {
  if [ "${QUALITY_STRICT}" != "true" ]; then
    echo "skip optional linters: set QUALITY_STRICT=true to run installed strict tools"
    return
  fi

  local shell_files=()
  mapfile -t shell_files < <(repo_files '*.sh')
  if [ "${#shell_files[@]}" -gt 0 ]; then
    if command_available shellcheck; then
      shellcheck "${shell_files[@]}"
    else
      echo "skip shellcheck: not installed"
    fi

    if command_available shfmt; then
      shfmt -d "${shell_files[@]}"
    else
      echo "skip shfmt: not installed"
    fi
  fi

  local yaml_files=()
  mapfile -t yaml_files < <(repo_files '*.yml' '*.yaml')
  if [ "${#yaml_files[@]}" -gt 0 ]; then
    if command_available yamllint; then
      yamllint "${yaml_files[@]}"
    else
      echo "skip yamllint: not installed"
    fi
  fi

  local python_files=()
  mapfile -t python_files < <(repo_files '*.py')
  if [ "${#python_files[@]}" -gt 0 ]; then
    if command_available ruff; then
      ruff check "${python_files[@]}"
    else
      echo "skip ruff: not installed"
    fi
  fi

  local container_files=()
  mapfile -t container_files < <(repo_files 'Dockerfile' '**/Dockerfile' '*.Dockerfile' '*Dockerfile')
  if [ "${#container_files[@]}" -gt 0 ]; then
    if command_available hadolint; then
      hadolint "${container_files[@]}"
    else
      echo "skip hadolint: not installed"
    fi
  fi
}

log "Quality inventory"
printf 'shell_scripts=%s\n' "$(count_repo_files '*.sh')"
printf 'yaml_files=%s\n' "$(count_repo_files '*.yml' '*.yaml')"
printf 'json_files=%s\n' "$(count_repo_files '*.json')"
printf 'ansible_files=%s\n' "$(count_repo_files 'ansible/**')"
printf 'kubernetes_files=%s\n' "$(count_repo_files 'kubernetes/**')"
printf 'python_files=%s\n' "$(count_repo_files '*.py')"
printf 'container_build_files=%s\n' "$(count_repo_files 'Dockerfile' '**/Dockerfile' '*.Dockerfile' '*Dockerfile')"
printf 'github_workflows=%s\n' "$(count_repo_files '.github/workflows/*.yml' '.github/workflows/*.yaml')"
printf 'markdown_files=%s\n' "$(count_repo_files '*.md')"

log "Lightweight secret scan"
"${SCRIPT_DIR}/check-secrets.sh"

log "GitHub Actions lint"
run_actionlint

log "Baseline static checks"
"${SCRIPT_DIR}/test-iac-static.sh"

log "App-instance example checks"
python3 "${SCRIPT_DIR}/test-app-instance-examples.py"

log "Local automation fixture checks"
automation_json="$(mktemp "${TMPDIR:-/tmp}/thekeep-automation.XXXXXX.json")"
trap 'rm -f "${automation_json}"' EXIT
python3 "${SCRIPT_DIR}/run-automation-fixture.py" \
  --fixture "${PROJECT_ROOT}/examples/automation-job-source.fixture.json" \
  --json-output "${automation_json}" \
  --self-test >/dev/null
python3 -m json.tool "${automation_json}" >/dev/null

log "EspoCRM assistant contract checks"
python3 "${SCRIPT_DIR}/test-espocrm-assistant-contract.py"

log "Optional traditional linters"
run_optional_linters

log "Quality checks passed"
