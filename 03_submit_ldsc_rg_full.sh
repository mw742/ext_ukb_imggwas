#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"
MANIFEST="${BASE}/manifests/ukb_big40_manifest.tsv"
SCRIPT="${BASE}/scripts/02_ldsc_rg_full.slurm"

MAX_CONCURRENT="${1:-100}"

[[ -s "${MANIFEST}" ]] || { echo "[fatal] missing manifest: ${MANIFEST}" >&2; exit 2; }
[[ -f "${SCRIPT}" ]] || { echo "[fatal] missing script: ${SCRIPT}" >&2; exit 3; }

N=$(( $(wc -l < "${MANIFEST}") - 1 ))
(( N > 0 )) || { echo "[fatal] manifest contains no traits" >&2; exit 4; }

echo "[diag] traits=${N}"
echo "[diag] throttle=${MAX_CONCURRENT}"
echo "[submit] sbatch --array=1-${N}%${MAX_CONCURRENT} ${SCRIPT}"

sbatch --array="1-${N}%${MAX_CONCURRENT}" "${SCRIPT}"
