#!/usr/bin/env bash
# Shared configuration. Source from a pipeline entry point with strict mode enabled.
fail() { echo "[fatal] $*" >&2; exit 2; }
positive_integer() { [[ "$2" =~ ^[1-9][0-9]*$ ]] || fail "$1 must be a positive integer"; }
require_setting() { [[ -n "${!1:-}" ]] || fail "Set $1 in PIPELINE_CONFIG"; }
require_file() { [[ -s "$1" && -r "$1" ]] || fail "Missing, empty or unreadable file: $1"; }

PIPELINE_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE_CONFIG="${PIPELINE_CONFIG:-${PIPELINE_SCRIPTS_DIR}/config.sh}"
require_file "$PIPELINE_CONFIG"
PIPELINE_CONFIG="$(cd -- "$(dirname -- "$PIPELINE_CONFIG")" && pwd)/$(basename -- "$PIPELINE_CONFIG")"
# Configuration is trusted local shell code; never source an untrusted file.
source "$PIPELINE_CONFIG"
export PIPELINE_CONFIG PIPELINE_SCRIPTS_DIR
require_setting BASE
[[ "$BASE" = /* && "$BASE" != / ]] || fail "BASE must be an absolute run-directory path other than /"
PYTHON_BIN="${PYTHON_BIN:-python3}"
"$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3, 9), "Python >=3.9 required"'
MANIFEST="${BASE}/manifests/ukb_manifest.tsv"
HARM="${BASE}/harmonized"
MUNGED="${BASE}/munged"
RES="${BASE}/results"
QC="${BASE}/qc"
LOGS="${BASE}/logs"
EXT_READY="${MUNGED}/externalizing.munged.sumstats.gz"
mkdir -p -- "${BASE}/manifests" "$HARM" "$MUNGED" "$RES" "$QC" "$LOGS" "${BASE}/tmp"

io() { "$PYTHON_BIN" "${PIPELINE_SCRIPTS_DIR}/pipeline_io.py" "$@"; }
manifest_count() { io count --manifest "$MANIFEST"; }
load_trait() {
  local task="${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}"
  positive_integer SLURM_ARRAY_TASK_ID "$task"
  # Each field is fetched separately so empty TSV fields cannot shift columns.
  TRAIT_ID="$(io field --manifest "$MANIFEST" --task "$task" --field trait_id)"
  STD_FILE="$(io field --manifest "$MANIFEST" --task "$task" --field std_path)"
}

run_ldsc() (
  # Isolate optional module/conda activation from the Python 3 helper runtime.
  if [[ -n "${LDSC_ENV_SETUP:-}" ]]; then
    require_file "$LDSC_ENV_SETUP"
    source "$LDSC_ENV_SETUP"
  fi
  require_setting LDSC_DIR
  require_setting LDSC_PYTHON
  local program="$1"; shift
  require_file "${LDSC_DIR}/${program}"
  "$LDSC_PYTHON" "${LDSC_DIR}/${program}" "$@"
)

check_references() {
  require_setting HM3
  require_setting REF_LD_PREFIX
  require_setting WEIGHT_LD_PREFIX
  require_file "$HM3"
  io references --ref "$REF_LD_PREFIX" --weights "$WEIGHT_LD_PREFIX"
}

munge() (
  local input="$1" destination="$2" label="$3" temp status
  require_file "$input"
  require_file "$HM3"
  temp="$(mktemp -d "${BASE}/tmp/${label}.XXXXXX")"
  trap 'status=$?; trap - EXIT; if [[ -f "$temp/output.log" ]]; then cp -- "$temp/output.log" "$LOGS/${label}.munge.log" || status=1; fi; rm -rf -- "$temp"; exit "$status"' EXIT
  run_ldsc munge_sumstats.py --sumstats "$input" --snp SNP --a1 A1 --a2 A2 \
    --signed-sumstats BETA,0 --p P --N-col N --merge-alleles "$HM3" --out "$temp/output"
  io validate-sumstats --path "$temp/output.sumstats.gz" --kind munged
  mv -f -- "$temp/output.sumstats.gz" "$destination"
)

submit_job() {
  local raw id
  local options=(--parsable --export=ALL --chdir="$PIPELINE_SCRIPTS_DIR")
  [[ -z "${SBATCH_PARTITION:-}" ]] || options+=(--partition="$SBATCH_PARTITION")
  raw="$(sbatch "${options[@]}" "$@")"
  id="${raw%%;*}"
  positive_integer 'sbatch job ID' "$id"
  printf '%s\n' "$id"
}
