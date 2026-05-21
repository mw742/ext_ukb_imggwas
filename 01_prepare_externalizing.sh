#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
OLD="${ROOT}/work_provided_assets/gwas_output/ldsc_rg"
BASE="${ROOT}/work_provided_assets/UKBfull"

HARM="${BASE}/harmonized"
MUNGED="${BASE}/munged_py27"
LOGDIR="${BASE}/logs"
REF_BASE="${ROOT}/work_provided_assets/ldsc_ref"
HM3="${REF_BASE}/eur_w_ld_chr/w_hm3.snplist"

OLD_STD="${OLD}/harmonized/externalizing.std.tsv.gz"
OLD_MUNGED="${OLD}/munged_py27/externalizing.munged.sumstats.gz"

NEW_STD="${HARM}/externalizing.std.tsv.gz"
NEW_MUNGED="${MUNGED}/externalizing.munged.sumstats.gz"

mkdir -p "${HARM}" "${MUNGED}" "${LOGDIR}"

echo "[diag] OLD_STD=${OLD_STD}"
echo "[diag] OLD_MUNGED=${OLD_MUNGED}"
echo "[diag] NEW_STD=${NEW_STD}"
echo "[diag] NEW_MUNGED=${NEW_MUNGED}"

if [[ -s "${OLD_STD}" ]]; then
  [[ -e "${NEW_STD}" ]] || ln -s "${OLD_STD}" "${NEW_STD}"
  echo "[ok] linked standardized externalizing file"
else
  echo "[fatal] old standardized externalizing file not found: ${OLD_STD}" >&2
  exit 2
fi

if [[ -s "${OLD_MUNGED}" ]]; then
  [[ -e "${NEW_MUNGED}" ]] || ln -s "${OLD_MUNGED}" "${NEW_MUNGED}"
  echo "[ok] linked pre-munged externalizing file"
  exit 0
fi

echo "[warn] old munged externalizing not found; re-munging locally"

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

PY2RUN=(env LD_LIBRARY_PATH="${LIBFIX}:/usr/lib64:/lib64:/opt/applications/python/2.7.11/gnu/lib" "$PY2_BIN" -S)

MUNGE_BIN="$(command -v munge_sumstats.py || true)"
[[ -n "${MUNGE_BIN}" ]] || MUNGE_BIN="/opt/applications/ldsc/1.0.0/gnu/bin/munge_sumstats.py"
[[ -f "${MUNGE_BIN}" ]] || { echo "[fatal] munge_sumstats.py not found"; exit 13; }

export PYTHONNOUSERSITE=1
unset PYTHONPATH
for p in \
  /opt/applications/ldsc/1.0.0/gnu/lib/python2.7/site-packages \
  /opt/applications/ldsc/1.0.0/gnu/lib64/python2.7/site-packages
do
  [[ -d "$p" ]] && export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$p"
done

[[ -s "${NEW_STD}" ]] || { echo "[fatal] missing ${NEW_STD}" >&2; exit 3; }
[[ -s "${HM3}" ]] || { echo "[fatal] missing ${HM3}" >&2; exit 4; }

TMP="${SLURM_TMPDIR:-/tmp}/ext_premunge_${USER}_$$"
mkdir -p "${TMP}"
trap 'rm -rf "${TMP}"' EXIT

cp -f "${NEW_STD}" "${TMP}/externalizing.std.tsv.gz"

/usr/bin/time -f "[time] %E CPU:%P RSS:%MKB" \
"${PY2RUN[@]}" "${MUNGE_BIN}" \
  --sumstats "${TMP}/externalizing.std.tsv.gz" \
  --snp SNP \
  --a1 A1 \
  --a2 A2 \
  --signed-sumstats BETA,0 \
  --p P \
  --N-col N \
  --merge-alleles "${HM3}" \
  --out "${TMP}/externalizing.munged"

mv -f "${TMP}/externalizing.munged.sumstats.gz" "${NEW_MUNGED}"
echo "[ok] wrote ${NEW_MUNGED}"
