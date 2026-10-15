#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

[[ $# -le 1 ]] || fail "Usage: bash 03_submit_ldsc_rg_full.sh [max_concurrent]"
throttle="${1:-${LDSC_CONCURRENT:-80}}"
positive_integer max_concurrent "$throttle"
check_references
require_file "$EXT_READY"
count="$(manifest_count)"
for ((task=1; task<=count; task++)); do
  require_file "$(io field --manifest "$MANIFEST" --task "$task" --field std_path)"
done
job="$(submit_job --output="$LOGS/ldsc_%A_%a.log" --array="1-${count}%${throttle}" \
  "$PIPELINE_SCRIPTS_DIR/02_ldsc_rg_full.slurm")"
echo "[ok] LDSC array: $job"
