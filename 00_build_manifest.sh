#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

require_setting UKB_SOURCE_DIR
io manifest --source "$UKB_SOURCE_DIR" --harmonized "$HARM" --manifest "$MANIFEST" \
  --pattern "${UKB_FILE_GLOB:-[0-9][0-9][0-9][0-9].txt.gz}" \
  --n "${UKB_N:-}" --n-column "${UKB_N_COLUMN:-}" --n-table "${UKB_N_TABLE:-}" \
  --excluded "$QC/excluded_input_files.tsv"
