#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="/gpfs/group/ehlers/mwei/ABCD"
BASE="${ROOT}/work_provided_assets/UKBfull"
SRC="/gpfs/group/ehlers/mwei/UKB_big40"

MANIFEST_DIR="${BASE}/manifests"
HARM="${BASE}/harmonized"
QC="${BASE}/qc"
LOGS="${BASE}/logs"

mkdir -p "${MANIFEST_DIR}" "${HARM}" "${QC}" "${LOGS}"

MANIFEST="${MANIFEST_DIR}/ukb_big40_manifest.tsv"
TMP="${MANIFEST}.tmp"

[[ -d "${SRC}" ]] || { echo "[fatal] source dir not found: ${SRC}" >&2; exit 2; }

printf "order\tid4\tsrc_path\tstd_path\n" > "${TMP}"

i=0
for f in $(find "${SRC}" -maxdepth 1 -name '*.txt.gz' | sort -V); do
  base=$(basename "$f")
  id4="${base%.txt.gz}"
  [[ "${id4}" =~ ^[0-9]{4}$ ]] || continue
  i=$((i+1))
  printf "%d\t%s\t%s\t%s\n" \
    "$i" \
    "$id4" \
    "$f" \
    "${HARM}/big40_${id4}.std.tsv.gz" >> "${TMP}"
done

mv -f "${TMP}" "${MANIFEST}"
echo "[ok] wrote ${MANIFEST}"
echo "[ok] traits: $(( $(wc -l < "${MANIFEST}") - 1 ))"
