#!/usr/bin/env bash
#SBATCH --job-name=ukb_full_pipe
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=02:00:00

set -euo pipefail
PIPELINE_SCRIPTS_DIR="${PIPELINE_SCRIPTS_DIR:-${SLURM_SUBMIT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"
source "${PIPELINE_SCRIPTS_DIR}/lib/common.sh"

positive_integer STD_CONCURRENT "${STD_CONCURRENT:-40}"
positive_integer LDSC_CONCURRENT "${LDSC_CONCURRENT:-80}"
check_references
input="${EXT_MUNGED:-${EXT_STANDARDIZED:-}}"
[[ -n "$input" ]] || fail "Configure an externalizing input"
[[ -z "${EXT_MUNGED:-}" || -z "${EXT_STANDARDIZED:-}" ]] || fail "Set only one externalizing input"
require_file "$input"
require_setting LDSC_DIR
require_setting LDSC_PYTHON
require_file "$LDSC_DIR/ldsc.py"
require_file "$LDSC_DIR/munge_sumstats.py"
[[ ! -e "$BASE/pipeline_jobs.tsv" ]] || fail "This BASE already has submitted jobs; use a new run directory"
mkdir "$BASE/.launch_lock" || fail "Another launcher is using this BASE"
trap 'rmdir "$BASE/.launch_lock"' EXIT
bash "$PIPELINE_SCRIPTS_DIR/00_build_manifest.sh"
count="$(manifest_count)"
printf 'stage\tjob_id\n' > "$BASE/pipeline_jobs.tsv"
{
  printf 'Submitted at: %s\n' "$(date -u +%FT%TZ)"
  printf 'Code commit: '
  git -C "$PIPELINE_SCRIPTS_DIR" rev-parse HEAD 2>/dev/null || printf 'unavailable\n'
  printf 'Python helpers: '
  "$PYTHON_BIN" --version
  printf 'LDSC directory: %s\nTraits: %s\n' "$LDSC_DIR" "$count"
} > "$BASE/run_metadata.txt"
prep="$(submit_job --job-name=ukb_prep_ext --mem=8G --time=02:00:00 \
  --output="$LOGS/prep_%j.log" "$PIPELINE_SCRIPTS_DIR/01_prepare_externalizing.sh")"
printf 'prepare\t%s\n' "$prep" >> "$BASE/pipeline_jobs.tsv"
std="$(submit_job --output="$LOGS/standardize_%A_%a.log" \
  --array="1-${count}%${STD_CONCURRENT:-40}" "$PIPELINE_SCRIPTS_DIR/01_standardize_ukbfull.slurm")"
printf 'standardize\t%s\n' "$std" >> "$BASE/pipeline_jobs.tsv"
ldsc="$(submit_job --dependency="afterok:${prep}:${std}" --kill-on-invalid-dep=yes \
  --output="$LOGS/ldsc_%A_%a.log" --array="1-${count}%${LDSC_CONCURRENT:-80}" \
  "$PIPELINE_SCRIPTS_DIR/02_ldsc_rg_full.slurm")"
printf 'ldsc\t%s\n' "$ldsc" >> "$BASE/pipeline_jobs.tsv"
# Failed/cancelled analyses still lead to a partial results table and QC reports.
collect="$(submit_job --dependency="afterany:${prep}:${std}:${ldsc}" \
  --job-name=ukb_collect --mem=1G --time=00:30:00 --output="$LOGS/collect_%j.log" \
  "$PIPELINE_SCRIPTS_DIR/04_collect_rg_results.sh")"
printf 'collect\t%s\n' "$collect" >> "$BASE/pipeline_jobs.tsv"
qc="$(submit_job --dependency="afterany:${collect}" --job-name=ukb_qc \
  --mem=1G --time=00:30:00 --output="$LOGS/qc_%j.log" \
  "$PIPELINE_SCRIPTS_DIR/05_check_missing_or_failed.sh")"
printf 'qc\t%s\n' "$qc" >> "$BASE/pipeline_jobs.tsv"
echo "[ok] jobs submitted; this does not mean the analysis has completed successfully"
cat "$BASE/pipeline_jobs.tsv"
