#!/usr/bin/env bash
set -euo pipefail

LEANTIME_URL="${LEANTIME_URL:-https://projects.thekeepstudios.com}"
LEANTIME_URL="${LEANTIME_URL%/}"
LEANTIME_BROWSER_COOKIE="${LEANTIME_BROWSER_COOKIE:-}"
LEANTIME_MCP_TOKEN="${LEANTIME_MCP_TOKEN:-}"
LEANTIME_MCP_AUTH_SCHEME="${LEANTIME_MCP_AUTH_SCHEME:-Bearer}"
LEANTIME_MCP_PATH="${LEANTIME_MCP_PATH:-/mcp}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/leantime-routing.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

request_root() {
  local accept="$1"
  local suffix="$2"
  local -a args=(
    -sS
    --max-time 20
    -D "${tmp_dir}/root-${suffix}.headers"
    -o "${tmp_dir}/root-${suffix}.body"
    -w "%{http_code}"
    -H "Accept: ${accept}"
  )

  if [ -n "${LEANTIME_BROWSER_COOKIE}" ]; then
    args+=(-H "Cookie: ${LEANTIME_BROWSER_COOKIE}")
  fi

  curl "${args[@]}" "${LEANTIME_URL}/"
}

check_root_redirect() {
  local accept="$1"
  local suffix="$2"
  local status
  local location

  status="$(request_root "${accept}" "${suffix}")"
  case "${status}" in
    301|302|303|307|308) ;;
    *) fail "root with Accept ${accept} returned ${status}, expected a redirect" ;;
  esac

  location="$(
    awk 'tolower($1) == "location:" {sub(/\r$/, "", $2); print $2}' \
      "${tmp_dir}/root-${suffix}.headers" |
      tail -n 1
  )"
  [ "${location}" = "${LEANTIME_URL}/dashboard/home" ] ||
    fail "root redirected to ${location:-nowhere}, expected ${LEANTIME_URL}/dashboard/home"
  ! grep -Eiq '"jsonrpc"' "${tmp_dir}/root-${suffix}.body" ||
    fail "root returned an MCP JSON-RPC body"

  pass "root Accept ${accept} is isolated to the Leantime UI"
}

check_root_redirect "text/html" "html"
check_root_redirect "text/event-stream" "event-stream"

dashboard_args=(
  -fsSL
  --max-time 20
  -D "${tmp_dir}/dashboard.headers"
  -o "${tmp_dir}/dashboard.body"
  -H "Accept: text/html"
)
if [ -n "${LEANTIME_BROWSER_COOKIE}" ]; then
  dashboard_args+=(-H "Cookie: ${LEANTIME_BROWSER_COOKIE}")
fi
curl "${dashboard_args[@]}" "${LEANTIME_URL}/dashboard/home"
grep -Eiq '<!doctype html|<html' "${tmp_dir}/dashboard.body" ||
  fail "/dashboard/home did not return HTML"
! grep -Eiq '"jsonrpc"' "${tmp_dir}/dashboard.body" ||
  fail "/dashboard/home returned an MCP JSON-RPC body"
pass "/dashboard/home returns the Leantime UI"

mcp_status="$(
  curl -sS \
    --max-time 20 \
    -o "${tmp_dir}/mcp-unauth.body" \
    -w "%{http_code}" \
    -H "Accept: text/event-stream" \
    "${LEANTIME_URL}${LEANTIME_MCP_PATH}"
)"
case "${mcp_status}" in
  401|403)
    pass "${LEANTIME_MCP_PATH} rejects unauthenticated access"
    ;;
  *)
    fail "${LEANTIME_MCP_PATH} returned ${mcp_status} without authentication; expected 401 or 403"
    ;;
esac

if [ -n "${LEANTIME_MCP_TOKEN}" ]; then
  set +e
  mcp_authenticated_status="$(
    curl -sS \
      --max-time 5 \
      -D "${tmp_dir}/mcp-auth.headers" \
      -o "${tmp_dir}/mcp-auth.body" \
      -w "%{http_code}" \
      -H "Accept: text/event-stream" \
      -H "Authorization: ${LEANTIME_MCP_AUTH_SCHEME} ${LEANTIME_MCP_TOKEN}" \
      "${LEANTIME_URL}${LEANTIME_MCP_PATH}"
  )"
  mcp_curl_status=$?
  set -e

  if [ "${mcp_curl_status}" -ne 0 ] && [ "${mcp_curl_status}" -ne 28 ]; then
    fail "authenticated MCP probe failed with curl status ${mcp_curl_status}"
  fi
  [ "${mcp_authenticated_status}" = "200" ] ||
    fail "authenticated MCP probe returned HTTP ${mcp_authenticated_status}"
  grep -Eiq '^content-type: text/event-stream' "${tmp_dir}/mcp-auth.headers" ||
    fail "authenticated MCP endpoint did not return text/event-stream"
  pass "${LEANTIME_MCP_PATH} accepts authenticated MCP streaming requests"
else
  echo "INFO: set LEANTIME_MCP_TOKEN to verify authenticated MCP streaming."
fi

if [ -z "${LEANTIME_BROWSER_COOKIE}" ]; then
  echo "INFO: set LEANTIME_BROWSER_COOKIE to repeat UI checks with an authenticated Leantime session."
fi
