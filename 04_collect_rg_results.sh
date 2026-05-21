#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"
RES="${BASE}/results_py27"
OUT="${BASE}/rg_results_full.tsv"

[[ -d "${RES}" ]] || { echo "[fatal] missing results dir: ${RES}" >&2; exit 2; }

echo -e "Trait\tRg\tSE\tZ\tP\tInt1\tInt2\tNhm3\tResultFile\tLogFile" > "${OUT}"

shopt -s nullglob
for r in "${RES}"/big40_*__vs__externalizing.results; do
  stem="${r%.results}"
  trait=$(basename "${stem}" | sed 's/__vs__externalizing$//')
  log="${stem}.log"

  rg=$(awk '/Genetic Correlation:/ {print $3; exit}' "${log}" 2>/dev/null || echo NA)
  se=$(awk '/Genetic Correlation:/ {gsub("[()]", "", $4); print $4; exit}' "${log}" 2>/dev/null || echo NA)
  z=$(awk '/ p = / {print $(NF-2); exit}' "${log}" 2>/dev/null || echo NA)
  p=$(awk '/ p = / {print $NF; exit}' "${log}" 2>/dev/null || echo NA)
  int1=$(awk '/Intercept:/ {print $2; exit}' "${log}" 2>/dev/null || echo NA)
  int2=$(awk '/Intercept:/ {val=$2} END{print val}' "${log}" 2>/dev/null || echo NA)
  nhm3=$(awk '/Sum of M.*hm3/ {getline; print $1; exit}' "${log}" 2>/dev/null || echo NA)

  echo -e "${trait}\t${rg}\t${se}\t${z}\t${p}\t${int1}\t${int2}\t${nhm3}\t${r}\t${log}" >> "${OUT}"
done

echo "[ok] wrote ${OUT}"
echo "[ok] rows: $(( $(wc -l < "${OUT}") - 1 ))"
