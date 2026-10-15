#!/usr/bin/env bash
#SBATCH --job-name=UKBfull_std
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=08:00:00

set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

load_trait
io standardize --manifest "$MANIFEST" --task "$SLURM_ARRAY_TASK_ID" \
  --qc "$QC/standardize_${TRAIT_ID}.json"
