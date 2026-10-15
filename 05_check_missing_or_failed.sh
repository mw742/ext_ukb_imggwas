#!/usr/bin/env bash
set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

# Exit nonzero if any expected result is missing, incomplete, or invalid.
io check --manifest "$MANIFEST" --results "$RES" --qc "$QC"
