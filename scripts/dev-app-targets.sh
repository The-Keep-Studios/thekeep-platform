#!/usr/bin/env bash

DEV_APP_TARGET_USAGE="wisemapping|leantime|baserow|twenty|espocrm|optional-crm|crm-bakeoff|platform"

dev_app_print_usage() {
  local script_name="$1"
  local suffix="${2:-}"

  echo "Usage: ${script_name} [${DEV_APP_TARGET_USAGE}]${suffix}" >&2
}

dev_app_is_target() {
  case "$1" in
    wisemapping|leantime|baserow|twenty|espocrm|optional-crm|crm-bakeoff|platform)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

dev_app_expand_target() {
  case "$1" in
    platform)
      printf '%s\n' wisemapping leantime baserow
      ;;
    optional-crm|crm-bakeoff)
      printf '%s\n' twenty espocrm
      ;;
    wisemapping|leantime|baserow|twenty|espocrm)
      printf '%s\n' "$1"
      ;;
    *)
      return 2
      ;;
  esac
}

dev_app_observe_config() {
  local target="$1"

  case "${target}" in
    wisemapping)
      APP_NAMESPACE="wisemapping"
      APP_SERVICE="wisemapping"
      APP_DEPLOYMENT="wisemapping"
      APP_PORT="${WISEMAPPING_OBSERVE_PORT:-18081}"
      APP_HOST="${WISEMAPPING_PROBE_HOST:-mindmaps.thekeepstudios.com}"
      APP_PROBE_PATH="/api/restful/app/config"
      APP_PROBE_PATTERN="apiBaseUrl|uiBaseUrl"
      APP_CONFIG_KIND="wisemapping"
      ;;
    leantime)
      APP_NAMESPACE="default"
      APP_SERVICE="leantime"
      APP_DEPLOYMENT="leantime"
      APP_PORT="${LEANTIME_OBSERVE_PORT:-18080}"
      APP_HOST="${LEANTIME_PROBE_HOST:-projects.thekeepstudios.com}"
      APP_PROBE_PATH="/auth/login"
      APP_PROBE_PATTERN="leantime|login|email|password|install|redirecting"
      APP_CONFIG_KIND="leantime"
      ;;
    baserow)
      APP_NAMESPACE="baserow"
      APP_SERVICE="baserow"
      APP_DEPLOYMENT="baserow"
      APP_PORT="${BASEROW_OBSERVE_PORT:-18082}"
      APP_HOST="${BASEROW_PROBE_HOST:-baserow.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="login|sign|create account"
      APP_CONFIG_KIND="baserow"
      ;;
    twenty)
      APP_NAMESPACE="twenty"
      APP_SERVICE="twenty"
      APP_DEPLOYMENT="twenty-server"
      APP_PORT="${TWENTY_OBSERVE_PORT:-18083}"
      APP_HOST="${TWENTY_PROBE_HOST:-twenty.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="twenty|login|sign|workspace"
      APP_CONFIG_KIND="twenty"
      ;;
    espocrm)
      APP_NAMESPACE="espocrm"
      APP_SERVICE="espocrm"
      APP_DEPLOYMENT="espocrm"
      APP_PORT="${ESPOCRM_OBSERVE_PORT:-18084}"
      APP_HOST="${ESPOCRM_PROBE_HOST:-espocrm.thekeepstudios.com}"
      APP_PROBE_PATH="/"
      APP_PROBE_PATTERN="espocrm|login|username|password"
      APP_CONFIG_KIND="espocrm"
      ;;
    *)
      echo "Unknown concrete dev app target: ${target}" >&2
      return 2
      ;;
  esac
}
