#!/usr/bin/env bash
#SBATCH --job-name=UKBfull_std
#SBATCH --output=/gpfs/group/ehlers/mwei/ABCD/work_provided_assets/UKBfull/logs/UKBfull_std_%A_%a.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=08:00:00
#SBATCH --partition=shared

set -euo pipefail
IFS=$'\n\t'
trap 'echo "[fatal] line $LINENO failed" >&2; exit 2' ERR

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"
MANIFEST="${BASE}/manifests/ukb_big40_manifest.tsv"
QC="${BASE}/qc"

UKB_N="${UKB_N:-40000}"

mkdir -p "${QC}"

[[ -s "${MANIFEST}" ]] || { echo "[fatal] missing manifest: ${MANIFEST}" >&2; exit 3; }

TOTAL=$(( $(wc -l < "${MANIFEST}") - 1 ))
TASK_ID="${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is not set}"

(( TASK_ID >= 1 && TASK_ID <= TOTAL )) || {
  echo "[skip] task ${TASK_ID} outside 1..${TOTAL}"
  exit 0
}

LINE=$(awk -F'\t' -v k="${TASK_ID}" 'NR==k+1 {print; exit}' "${MANIFEST}")
[[ -n "${LINE}" ]] || { echo "[fatal] could not read manifest line ${TASK_ID}" >&2; exit 4; }

order=$(echo "${LINE}" | awk -F'\t' '{print $1}')
id4=$(echo "${LINE}"   | awk -F'\t' '{print $2}')
src=$(echo "${LINE}"   | awk -F'\t' '{print $3}')
dst=$(echo "${LINE}"   | awk -F'\t' '{print $4}')

echo "[diag] order=${order}"
echo "[diag] id4=${id4}"
echo "[diag] src=${src}"
echo "[diag] dst=${dst}"
echo "[diag] UKB_N=${UKB_N}"

[[ -s "${src}" ]] || { echo "[fatal] missing raw input: ${src}" >&2; exit 5; }

if [[ -s "${dst}" ]]; then
  echo "[skip] standardized file already exists: ${dst}"
  exit 0
fi

export SRC_FILE="${src}"
export DST_FILE="${dst}"
export UKB_N_VAL="${UKB_N}"
export QC_FILE="${QC}/std_columns_${id4}.txt"

unset PYTHONHOME PYTHONPATH PYTHONNOUSERSITE
micromamba run -n my_env python - <<'PY'
import os
import numpy as np
import pandas as pd

src = os.environ["SRC_FILE"]
dst = os.environ["DST_FILE"]
ukb_n = float(os.environ["UKB_N_VAL"])
qc_file = os.environ["QC_FILE"]

hdr = pd.read_csv(src, sep=r"\s+", compression="gzip", nrows=0)
cols = list(hdr.columns)

with open(qc_file, "w") as f:
    f.write("\t".join(cols) + "\n")

required = ["rsid", "a1", "a2", "beta", "pval(-log10)"]
missing = [c for c in required if c not in cols]
if missing:
    raise ValueError("Missing required columns: %s ; observed=%s" % (missing, cols))

df = pd.read_csv(
    src,
    sep=r"\s+",
    compression="gzip",
    usecols=["rsid", "a1", "a2", "beta", "pval(-log10)"]
)

df = df.rename(columns={
    "rsid": "SNP",
    "a1": "A1",
    "a2": "A2",
    "beta": "BETA",
    "pval(-log10)": "LOG10P"
})

df["P"] = np.power(10.0, -df["LOG10P"].astype(float))
tiny = np.finfo(float).tiny
df.loc[df["P"] < tiny, "P"] = tiny
df["N"] = ukb_n

df = df[["SNP", "A1", "A2", "BETA", "P", "N"]]
df = df.replace([np.inf, -np.inf], np.nan)
df = df.dropna(subset=["SNP", "A1", "A2", "BETA", "P", "N"])

for c in ["SNP", "A1", "A2"]:
    df[c] = df[c].astype(str).str.strip()

df["BETA"] = pd.to_numeric(df["BETA"], errors="coerce")
df["P"] = pd.to_numeric(df["P"], errors="coerce")
df["N"] = pd.to_numeric(df["N"], errors="coerce")

df = df.dropna(subset=["BETA", "P", "N"])
df = df[(df["P"] > 0) & (df["P"] <= 1)]

df.to_csv(dst, sep="\t", index=False, compression="gzip")
print("[ok] standardized:", src, "->", dst, "rows=", len(df))
PY
