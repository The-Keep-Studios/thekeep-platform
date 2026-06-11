#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
SEED_DIR="${SCRIPT_DIR%/*}/demo/seed"

for name in organizations people projects opportunities meetings; do
  file="${SEED_DIR}/${name}.csv"
  [ -s "${file}" ] || {
    echo "Missing demo seed: ${file}" >&2
    exit 1
  }
  awk -F, 'NR > 1 && $1 !~ /^demo_/ { exit 1 }' "${file}" || {
    echo "Demo IDs must start with demo_: ${file}" >&2
    exit 1
  }
done

if grep -Eiq \
  'thekeepstudios|iantsmall|full[[:space:]_-]*hearts|@gmail\.com|@yahoo\.com|@outlook\.com' \
  "${SEED_DIR}"/*.csv; then
  echo "Demo seed contains a forbidden real-data marker." >&2
  exit 1
fi

if grep -Eiho '[[:alnum:]._%+-]+@[[:alnum:].-]+' "${SEED_DIR}"/*.csv |
   grep -Ev '@[[:alnum:].-]+\.example\.test$' >/dev/null; then
  echo "Demo email addresses must use example.test." >&2
  exit 1
fi

echo "Demo seed checks passed."
