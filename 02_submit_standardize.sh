#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

[[ $# -le 1 ]] || fail "Usage: bash 02_submit_standardize.sh [max_concurrent]; configure N in config.sh"
throttle="${1:-${STD_CONCURRENT:-40}}"
positive_integer max_concurrent "$throttle"
bash "$PIPELINE_SCRIPTS_DIR/00_build_manifest.sh"
count="$(manifest_count)"
job="$(submit_job --output="$LOGS/standardize_%A_%a.log" --array="1-${count}%${throttle}" \
  "$PIPELINE_SCRIPTS_DIR/01_standardize_ukbfull.slurm")"
echo "[ok] standardization array: $job"
