#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

if [[ -n "${EXT_STANDARDIZED:-}" && -n "${EXT_MUNGED:-}" ]] ||
   [[ -z "${EXT_STANDARDIZED:-}" && -z "${EXT_MUNGED:-}" ]]; then
  fail "Set exactly one of EXT_STANDARDIZED or EXT_MUNGED"
fi
input="${EXT_MUNGED:-${EXT_STANDARDIZED:-}}"
require_file "$input"
[[ "$input" != "$EXT_READY" ]] || fail "Externalizing input must be separate from the output"
if [[ -e "$EXT_READY" && "$input" -ef "$EXT_READY" ]]; then
  fail "Externalizing input resolves to the output file"
fi
rm -f -- "$EXT_READY"
if [[ -n "${EXT_MUNGED:-}" ]]; then
  temp="$(mktemp "${BASE}/tmp/externalizing.XXXXXX")"
  trap 'rm -f -- "$temp"' EXIT
  cp -- "$EXT_MUNGED" "$temp"
  io validate-sumstats --path "$temp" --kind munged
  mv -f -- "$temp" "$EXT_READY"
  printf 'Input: %s\nAlready munged; no munging performed.\n' "$EXT_MUNGED" > "$LOGS/externalizing.input.txt"
else
  require_setting HM3
  io validate-sumstats --path "$EXT_STANDARDIZED" --kind standardized
  munge "$EXT_STANDARDIZED" "$EXT_READY" externalizing
fi
echo "[ok] externalizing input ready"
