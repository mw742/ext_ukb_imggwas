#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

# Include every expected trait, including explicit missing/failed rows.
io collect --manifest "$MANIFEST" --results "$RES" --output "$BASE/rg_results_full.tsv"
