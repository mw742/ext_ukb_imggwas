# UK Biobank IDP GWAS vs ABCD Externalizing GWAS LDSC Genetic Correlation Pipeline

This repository contains scripts for running LDSC genetic correlation analysis between UK Biobank imaging-derived phenotype GWAS summary statistics and ABCD externalizing behavior GWAS summary statistics.

The pipeline prepares the GWAS summary statistics, standardizes UK Biobank IDP GWAS files, runs LDSC genetic correlation, collects the results, and checks missing or failed jobs.

---

## Pipeline Scripts

### `00_build_manifest.sh`

Builds a manifest file for all UK Biobank IDP GWAS summary statistic files.

The manifest is used by later scripts to know which GWAS files need to be processed.

---

### `01_prepare_externalizing.sh`

Prepares the ABCD externalizing GWAS summary statistics for LDSC analysis.

This script either links to an existing munged externalizing GWAS file or prepares the externalizing GWAS file into LDSC-compatible format.

---

### `01_standardize_ukbfull.slurm`

Standardizes UK Biobank IDP GWAS summary statistic files.

This step converts the original UKB IDP GWAS files into a consistent format that can be used by LDSC.

---

### `02_ldsc_rg_full.slurm`

Runs the main LDSC genetic correlation analysis.

For each UKB IDP GWAS file, this script munges the summary statistics and runs LDSC genetic correlation against the ABCD externalizing GWAS summary statistics.

---

### `02_submit_standardize.sh`

Submits the UKB IDP GWAS standardization jobs.

Use this script when you only want to run the standardization step.

---

### `03_submit_ldsc_rg_full.sh`

Submits the LDSC genetic correlation jobs.

Use this script after the UKB IDP GWAS files have already been standardized.

---

### `04_collect_rg_results.sh`

Collects all LDSC genetic correlation results into one summary table.

This final table can be used for downstream analysis, filtering, and plotting.

---

### `05_check_missing_or_failed.sh`

Checks for missing or failed LDSC results.

This script helps identify which UKB IDP GWAS files may need to be rerun.

---

### `06_run_full_pipeline.slurm`

Runs the full pipeline as a chained SLURM workflow.

This script is useful if you want to run all steps together from start to finish.

---


## Citation

If you use the ideas, scripts, or pipeline from this repository in your work, please cite or acknowledge:

Wei M, Peng Q. *Genetic Correlation Between Brain Imaging Phenotypes and Externalizing Behavior: A Large-Scale LDSC Analysis of UK Biobank IDPs*. 2026.
