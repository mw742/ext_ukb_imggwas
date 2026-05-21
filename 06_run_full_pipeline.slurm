#!/usr/bin/env bash
#SBATCH --job-name=ukb_full_pipe
#SBATCH --output=/gpfs/group/ehlers/mwei/ABCD/work_provided_assets/UKBfull/logs/ukb_full_pipe_%j.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=02:00:00
#SBATCH --partition=shared

set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"
SCRIPTS="${BASE}/scripts"
MANIFEST="${BASE}/manifests/ukb_big40_manifest.tsv"
LOGS="${BASE}/logs"

STD_SCRIPT="${SCRIPTS}/01_standardize_ukbfull.slurm"
LDSC_SCRIPT="${SCRIPTS}/02_ldsc_rg_full.slurm"

STD_CONCURRENT="${STD_CONCURRENT:-40}"
UKB_N_VALUE="${UKB_N_VALUE:-40000}"
LDSC_CONCURRENT="${LDSC_CONCURRENT:-80}"

mkdir -p "${LOGS}"

[[ -s "${MANIFEST}" ]] || { echo "[fatal] missing manifest: ${MANIFEST}" >&2; exit 2; }
[[ -f "${STD_SCRIPT}" ]] || { echo "[fatal] missing standardize script: ${STD_SCRIPT}" >&2; exit 3; }
[[ -f "${LDSC_SCRIPT}" ]] || { echo "[fatal] missing LDSC script: ${LDSC_SCRIPT}" >&2; exit 4; }

N=$(( $(wc -l < "${MANIFEST}") - 1 ))
(( N > 0 )) || { echo "[fatal] manifest contains no traits" >&2; exit 5; }

echo "[diag] traits=${N}"
echo "[diag] std_concurrent=${STD_CONCURRENT}"
echo "[diag] ukb_n=${UKB_N_VALUE}"
echo "[diag] ldsc_concurrent=${LDSC_CONCURRENT}"
echo "[diag] submit_host=$(hostname)"
echo "[diag] submit_time=$(date)"

prep_jobid=$(sbatch --parsable \
  --job-name=ukb_prep_ext \
  --output="${LOGS}/ukb_prep_ext_%j.log" \
  --wrap="cd ${SCRIPTS} && bash 01_prepare_externalizing.sh")

echo "[ok] submitted prep job: ${prep_jobid}"

std_jobid=$(sbatch --parsable \
  --dependency=afterok:${prep_jobid} \
  --export=ALL,UKB_N=${UKB_N_VALUE} \
  --array="1-${N}%${STD_CONCURRENT}" \
  "${STD_SCRIPT}")

echo "[ok] submitted standardize array: ${std_jobid}"

ldsc_jobid=$(sbatch --parsable \
  --dependency=afterok:${std_jobid} \
  --array="1-${N}%${LDSC_CONCURRENT}" \
  "${LDSC_SCRIPT}")

echo "[ok] submitted LDSC array: ${ldsc_jobid}"

collect_jobid=$(sbatch --parsable \
  --dependency=afterok:${ldsc_jobid} \
  --job-name=ukb_collect_rg \
  --output="${LOGS}/ukb_collect_rg_%j.log" \
  --wrap="cd ${SCRIPTS} && bash 04_collect_rg_results.sh")

echo "[ok] submitted collect job: ${collect_jobid}"

check_jobid=$(sbatch --parsable \
  --dependency=afterok:${collect_jobid} \
  --job-name=ukb_check_rg \
  --output="${LOGS}/ukb_check_rg_%j.log" \
  --wrap="cd ${SCRIPTS} && bash 05_check_missing_or_failed.sh")

echo "[ok] submitted check job: ${check_jobid}"

echo
echo "Pipeline submitted successfully."
echo "prep_jobid=${prep_jobid}"
echo "std_jobid=${std_jobid}"
echo "ldsc_jobid=${ldsc_jobid}"
echo "collect_jobid=${collect_jobid}"
echo "check_jobid=${check_jobid}"
