#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"

MANIFEST="${BASE}/manifests/ukb_big40_manifest.tsv"
RES="${BASE}/results_py27"
OUT_MISSING="${BASE}/qc/missing_rg_traits.tsv"
OUT_FAILED="${BASE}/qc/failed_rg_traits.tsv"

mkdir -p "${BASE}/qc"

[[ -s "${MANIFEST}" ]] || { echo "[fatal] missing manifest: ${MANIFEST}" >&2; exit 2; }

echo -e "order\tid4\ttrait\tresults_exists\tlog_exists" > "${OUT_MISSING}"
echo -e "order\tid4\ttrait\tproblem" > "${OUT_FAILED}"

awk 'NR>1' "${MANIFEST}" | while IFS=$'\t' read -r order id4 src harm; do
  trait="big40_${id4}"
  res="${RES}/${trait}__vs__externalizing.results"
  log="${RES}/${trait}__vs__externalizing.log"

  res_ok=0; log_ok=0
  [[ -s "${res}" ]] && res_ok=1
  [[ -s "${log}" ]] && log_ok=1

  if [[ "${res_ok}" -eq 0 || "${log_ok}" -eq 0 ]]; then
    echo -e "${order}\t${id4}\t${trait}\t${res_ok}\t${log_ok}" >> "${OUT_MISSING}"
    continue
  fi

  if grep -qiE 'error|traceback|failed|exception' "${log}"; then
    echo -e "${order}\t${id4}\t${trait}\tlog_contains_error_string" >> "${OUT_FAILED}"
  fi
done

echo "[ok] wrote ${OUT_MISSING}"
echo "[ok] wrote ${OUT_FAILED}"
