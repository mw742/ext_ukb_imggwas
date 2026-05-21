#!/usr/bin/env bash
#SBATCH --job-name=UKBfull_LDSC_rg
#SBATCH --output=/gpfs/group/ehlers/mwei/ABCD/work_provided_assets/UKBfull/logs/UKBfull_LDSC_rg_%A_%a.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --partition=shared

set -euo pipefail
IFS=$'\n\t'
trap 'echo "[fatal] line $LINENO failed" >&2' ERR

echo "[$(date)] Starting UKBfull LDSC rg on host: $(hostname)"

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"

HARM="${BASE}/harmonized"
MUNGED="${BASE}/munged_py27"
RES="${BASE}/results_py27"
MANIFEST="${BASE}/manifests/ukb_big40_manifest.tsv"
REF_BASE="${ROOT}/work_provided_assets/ldsc_ref"
REF_LD_CHR="${REF_BASE}/eur_w_ld_chr"
HM3="${REF_LD_CHR}/w_hm3.snplist"
EXT_MUNGED="${MUNGED}/externalizing.munged.sumstats.gz"

if ls -1 "${REF_BASE}/weights_hm3_no_hla"/weights.*.l2.ldscore.gz >/dev/null 2>&1; then
  W_LD_CHR="${REF_BASE}/weights_hm3_no_hla/weights"
else
  W_LD_CHR="${REF_LD_CHR}/weights"
fi

mkdir -p "${MUNGED}" "${RES}"

[[ -s "${MANIFEST}" ]]   || { echo "[fatal] missing manifest: ${MANIFEST}" >&2; exit 2; }
[[ -s "${HM3}" ]]        || { echo "[fatal] missing HM3 list: ${HM3}" >&2; exit 3; }
[[ -s "${EXT_MUNGED}" ]] || { echo "[fatal] missing externalizing munged: ${EXT_MUNGED}" >&2; exit 4; }

module purge
module load python/2.7.11
module load ldsc/1.0.0

# ---------- Stable Python2/OpenSSL runtime ----------
LIBFIX="/gpfs/home/mwei/libfix"
PY2_BIN="/opt/applications/python/2.7.11/gnu/bin/python2.7"
HASHLIB_SO="/opt/applications/python/2.7.11/gnu/lib/python2.7/lib-dynload/_hashlib.so"

export LD_LIBRARY_PATH="${LIBFIX}:/usr/lib64:/lib64:/opt/applications/python/2.7.11/gnu/lib"
export PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME

[[ -x "$PY2_BIN" ]] || { echo "[fatal] python2 binary not found: $PY2_BIN"; exit 10; }
[[ -r "${LIBFIX}/libssl.so.10" ]] || { echo "[fatal] missing ${LIBFIX}/libssl.so.10"; exit 11; }
[[ -r "${LIBFIX}/libcrypto.so.10" ]] || { echo "[fatal] missing ${LIBFIX}/libcrypto.so.10"; exit 12; }

# Wrap every Python2 call with the fixed runtime
PY2RUN=(env LD_LIBRARY_PATH="${LIBFIX}:/usr/lib64:/lib64:/opt/applications/python/2.7.11/gnu/lib" "$PY2_BIN" -S)

echo "[diag] hostname=$(hostname)"
echo "[diag] LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "[diag] PATH=$PATH"
echo "[diag] which python2=$(command -v python2 || true)"
echo "[diag] PY2_BIN=$PY2_BIN"
echo "[diag] HASHLIB_SO=$HASHLIB_SO"

echo "[diag] checking private OpenSSL compat files"
ls -l "${LIBFIX}/libssl.so.10" \
      "${LIBFIX}/libcrypto.so.10" \
      "${LIBFIX}/libssl.so.1.0.2k" \
      "${LIBFIX}/libcrypto.so.1.0.2k"

echo "[diag] ldd on python2"
ldd "$PY2_BIN" || true

echo "[diag] ldd on _hashlib.so with fixed env"
env LD_LIBRARY_PATH="${LIBFIX}:/usr/lib64:/lib64:/opt/applications/python/2.7.11/gnu/lib" \
    ldd "$HASHLIB_SO" || true

echo "[diag] testing hashlib"
"${PY2RUN[@]}" - <<'PY'
import _hashlib, hashlib
print("OK")
print(hashlib.md5("abc").hexdigest())
PY

# Prefer module-provided binaries
LDSC_BIN="$(command -v ldsc.py || true)"
MUNGE_BIN="$(command -v munge_sumstats.py || true)"
[[ -n "${LDSC_BIN}" ]]  || LDSC_BIN="/opt/applications/ldsc/1.0.0/gnu/bin/ldsc.py"
[[ -n "${MUNGE_BIN}" ]] || MUNGE_BIN="/opt/applications/ldsc/1.0.0/gnu/bin/munge_sumstats.py"

[[ -f "${LDSC_BIN}" ]]  || { echo "[fatal] ldsc.py not found"; exit 13; }
[[ -f "${MUNGE_BIN}" ]] || { echo "[fatal] munge_sumstats.py not found"; exit 14; }

# ---------- Clean Python2 env for LDSC ----------
export PYTHONNOUSERSITE=1
unset PYTHONPATH
for p in \
  /opt/applications/ldsc/1.0.0/gnu/lib/python2.7/site-packages \
  /opt/applications/ldsc/1.0.0/gnu/lib64/python2.7/site-packages
do
  [[ -d "$p" ]] && export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$p"
done

echo "[diag] PYTHONPATH=${PYTHONPATH:-<empty>}"

echo "[diag] sanity check Python2 deps"
"${PY2RUN[@]}" - <<'PY'
import sys, hashlib
hp = getattr(hashlib, '__file__', '')
if hp and ('site-packages' in hp or 'egg' in hp):
    sys.stderr.write("[fatal] Bad hashlib on sys.path: %s\n" % hp)
    sys.stderr.write("\n".join(sys.path) + "\n")
    raise SystemExit(1)
import numpy, scipy, pandas, ldscore
print("py2 deps OK")
PY

TOTAL=$(( $(wc -l < "${MANIFEST}") - 1 ))
TASK_ID="${SLURM_ARRAY_TASK_ID}"

(( TASK_ID >= 1 && TASK_ID <= TOTAL )) || {
  echo "[skip] task ${TASK_ID} outside valid range 1..${TOTAL}"
  exit 0
}

LINE=$(awk -F'\t' -v k="${TASK_ID}" 'NR==k+1 {print; exit}' "${MANIFEST}")
[[ -n "${LINE}" ]] || { echo "[fatal] could not read manifest line for task ${TASK_ID}" >&2; exit 15; }

order=$(echo "${LINE}" | awk -F'\t' '{print $1}')
id4=$(echo "${LINE}"   | awk -F'\t' '{print $2}')
src=$(echo "${LINE}"   | awk -F'\t' '{print $3}')
harm=$(echo "${LINE}"  | awk -F'\t' '{print $4}')

trait="big40_${id4}"
munged_final="${MUNGED}/${trait}.munged.sumstats.gz"
rg_stem="${RES}/${trait}__vs__externalizing"

echo "[diag] order=${order}"
echo "[diag] task=${TASK_ID}/${TOTAL}"
echo "[diag] id4=${id4}"
echo "[diag] src=${src}"
echo "[diag] harm=${harm}"
echo "[diag] trait=${trait}"

[[ -s "${harm}" ]] || { echo "[fatal] harmonized input missing: ${harm}" >&2; exit 16; }

TMPROOT="${SLURM_TMPDIR:-/tmp}"
JOBTMP="${TMPROOT}/ukbfull_ldsc_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
mkdir -p "${JOBTMP}"
trap 'rm -rf "${JOBTMP}"' EXIT
export TMPDIR="${JOBTMP}"

# 1) munge if needed
if [[ ! -s "${munged_final}" ]]; then
  echo "[munge] ${trait}"
  cp -f "${harm}" "${JOBTMP}/in.std.tsv.gz"
  /usr/bin/time -f "[time] munge %E CPU:%P RSS:%MKB" \
  "${PY2RUN[@]}" "${MUNGE_BIN}" \
    --sumstats "${JOBTMP}/in.std.tsv.gz" \
    --snp SNP \
    --a1 A1 \
    --a2 A2 \
    --signed-sumstats BETA,0 \
    --p P \
    --N-col N \
    --merge-alleles "${HM3}" \
    --out "${JOBTMP}/${trait}.munged"
  mv -f "${JOBTMP}/${trait}.munged.sumstats.gz" "${munged_final}"
else
  echo "[skip] munged already exists: ${munged_final}"
fi

[[ -s "${munged_final}" ]] || { echo "[fatal] munged output missing: ${munged_final}" >&2; exit 17; }

# 2) run rg if needed
if [[ -s "${rg_stem}.results" && -s "${rg_stem}.log" ]]; then
  echo "[skip] rg already exists: ${rg_stem}"
else
  echo "[rg] ${trait} vs externalizing"
  /usr/bin/time -f "[time] ldsc %E CPU:%P RSS:%MKB" \
  "${PY2RUN[@]}" "${LDSC_BIN}" \
    --rg "${munged_final},${EXT_MUNGED}" \
    --ref-ld-chr "${REF_LD_CHR}" \
    --w-ld-chr "${W_LD_CHR}" \
    --out "${rg_stem}"
fi

echo "[ok] done ${trait}"
