#!/usr/bin/env bash
#SBATCH --job-name=UKBfull_LDSC_rg
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=24:00:00

set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

load_trait
check_references
require_file "$EXT_READY"
require_file "$STD_FILE"
trait="big40_${TRAIT_ID}"
munged="$MUNGED/${trait}.munged.sumstats.gz"
stem="$RES/${trait}__vs__externalizing"
# Recompute rather than silently reuse results from different inputs/settings.
rm -f -- "${stem}.log" "$munged"
munge "$STD_FILE" "$munged" "$trait"
temp="$(mktemp -d "${BASE}/tmp/rg_${TRAIT_ID}.XXXXXX")"
trap 'status=$?; trap - EXIT; if [[ -f "$temp/output.log" ]]; then cp -- "$temp/output.log" "${stem}.log" || status=1; fi; rm -rf -- "$temp"; exit "$status"' EXIT
run_ldsc ldsc.py --rg "$munged,$EXT_READY" --ref-ld-chr "$REF_LD_PREFIX" \
  --w-ld-chr "$WEIGHT_LD_PREFIX" --out "$temp/output"
# LDSC can catch a per-phenotype exception and exit zero. Check its result too.
io validate-log --log "$temp/output.log"
echo "[ok] valid genetic-correlation result for $trait"
