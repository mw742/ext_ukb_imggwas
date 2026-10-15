# Copy to config.sh (gitignored), then replace paths with your authorized locations.
# Use a NEW BASE for each analysis run. Keep research inputs outside this repository.
BASE="/path/to/analysis-run"
UKB_SOURCE_DIR="/path/to/ukb-idp-summary-statistics"
# Preserves the original four-digit phenotype selection; broaden only intentionally.
UKB_FILE_GLOB='[0-9][0-9][0-9][0-9].txt.gz'

# Set EXACTLY ONE sample-size source. No sample size is assumed automatically.
UKB_N_TABLE="/path/to/trait_sample_sizes.tsv"  # TSV columns: trait_id and N
UKB_N_COLUMN=""  # Alternative: exact per-variant N column in each source file
UKB_N=""         # Alternative: verified constant N for all selected variants/traits

# Set EXACTLY ONE externalizing input. Its preparation/provenance is your responsibility.
EXT_STANDARDIZED="/path/to/externalizing.std.tsv.gz"  # SNP A1 A2 BETA P N
EXT_MUNGED=""  # Alternative: an already munged SNP A1 A2 Z N .sumstats.gz file

HM3="/path/to/w_hm3.snplist"
# Prefix includes the slash or dot BEFORE the chromosome number. @ is also supported.
REF_LD_PREFIX="/path/to/eur_w_ld_chr/"  # e.g. /path/to/eur_w_ld_chr/1.l2.ldscore.gz
WEIGHT_LD_PREFIX="$REF_LD_PREFIX"
# For weights.1.l2.ldscore.gz, use /path/to/weights_hm3_no_hla/weights.

# Python 3 helpers use only the standard library; LDSC has its own environment.
PYTHON_BIN="python3"  # Python >=3.9, preferably an absolute executable path
LDSC_DIR="/path/to/ldsc"  # A verified checkout containing ldsc.py and munge_sumstats.py
LDSC_PYTHON="/path/to/ldsc-environment/bin/python"  # Compatible with YOUR LDSC version
LDSC_ENV_SETUP=""  # Optional trusted shell file for module/conda activation
SBATCH_PARTITION=""  # Empty uses the cluster default
STD_CONCURRENT=40
LDSC_CONCURRENT=80
