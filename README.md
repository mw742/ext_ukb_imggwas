# UK Biobank IDP GWAS vs externalizing GWAS: LDSC pipeline

Scripts to standardize UK Biobank imaging-derived phenotype (IDP) GWAS summary
statistics, prepare an externalizing summary-statistics input, run cross-trait
LDSC, and collect results with explicit technical QC.

## Status and scope

This revision corrects configuration, LD-score prefixes, result parsing, and job
orchestration in the original repository snapshot
[`99f0cc4`](https://github.com/mw742/ext_ukb_imggwas/commit/99f0cc44b95cfbe7072d75fb2508f65edbfa0281).
It has synthetic regression checks. It has **not** been rerun against the original
study inputs or validated on the original HPC system. Treat it as an updated
implementation, not a verified reproduction of the published numerical results.
The earlier commits remain available; this update does not rewrite history.

The pipeline starts from GWAS summary statistics. It does not perform the
originating GWAS or recreate the externally prepared externalizing input. Its QC
checks whether LDSC outputs are complete and numerically usable; it does not
implement the manuscript's biological phenotype selection, heritability/signal
thresholds, multiple-testing correction, aggregate association tests, or figures.

The externalizing input's cohort cannot be inferred from its filename. Record the
exact GWAS source, release, ancestry, phenotype, and preparation steps used for
your run; the former README's ABCD label is not a substitute for this provenance.

### Validation and future updates

This research implementation may contain errors or limitations that have not yet
been identified, despite the checks described above. Further validation may lead
to revisions. Any corrections made following additional checks will be documented
in the commit history or release notes, including their effect on outputs when known.

Users should independently validate the code for their intended analysis and
record the exact commit used. The current validation status and known limitations
are described in this README.

## Requirements

- Bash, standard Unix utilities, and Python **3.9 or newer** for `pipeline_io.py`.
  The helper uses the Python standard library only; pandas, NumPy, and a named
  micromamba environment are not required for it.
- SLURM for job submission, including `--parsable`, job arrays, and
  `--kill-on-invalid-dep=yes`.
- A separately installed, verified LDSC checkout and its compatible Python
  environment. The original scripts used LDSC 1.0.0/Python 2.7; an environment
  module with the same name is not proof of identical source code. Follow
  [upstream installation instructions](https://github.com/bulik/ldsc), pin the
  checkout, and retain its version/commit with your analysis records.
- Authorized access to the input statistics, HapMap3 SNP/allele list, and
  ancestry-appropriate chromosome-split LD-score references.

Do not change the LDSC version or scientific inputs silently when comparing with
the original analysis. Validate any replacement environment on suitable inputs.

## Configure

Copy `config.example.sh` to `config.sh` and edit it. Alternatively set an
absolute path in `PIPELINE_CONFIG`:

```bash
cp config.example.sh config.sh
# Edit config.sh before running anything.
export PIPELINE_CONFIG="/absolute/path/to/config.sh"
```

Configuration files are trusted shell code. Use an absolute `BASE` **outside the
repository and separate from input data**, with a new directory for each analysis
run. Do not edit the configuration, source checkout, or manifest while jobs are
active. All compute nodes must see the same configured paths and executables.
Local configuration and common data/output formats are gitignored; this does not
remove any file already tracked by Git.

Configure these inputs:

| Setting | Required meaning |
| --- | --- |
| `UKB_SOURCE_DIR` | Directory containing original whitespace-delimited `.txt.gz` GWAS files |
| `UKB_FILE_GLOB` | Explicit phenotype-file selection; the default preserves four-digit names |
| `EXT_STANDARDIZED` or `EXT_MUNGED` | Exactly one externalizing input, as described below |
| `HM3` | HapMap3 SNP/allele list for `--merge-alleles` |
| `REF_LD_PREFIX` | Chromosome-file prefix, including the required trailing slash/dot |
| `WEIGHT_LD_PREFIX` | Regression-weight prefix; may equal the reference prefix for the standard unpartitioned setup |
| `LDSC_DIR`, `LDSC_PYTHON` | LDSC checkout and compatible Python executable |
| `PYTHON_BIN` | Python 3 executable for this repository's helper |
| `LDSC_ENV_SETUP` | Optional trusted module/activation script, used in a subshell |
| `SBATCH_PARTITION` | Optional partition; blank uses the cluster default |

For files `eur_w_ld_chr/1.l2.ldscore.gz` through chromosome 22, use
`REF_LD_PREFIX="/path/to/eur_w_ld_chr/"`. For `weights.1.l2.ldscore.gz`,
use `WEIGHT_LD_PREFIX="/path/to/weights."`. An `@` chromosome placeholder is
also supported. Preflight checks all 22 chromosomes and the reference
`.l2.M_5_50` files. No automatic guessing of a weight prefix occurs.

### Sample sizes: an explicit source is required

Choose **exactly one**:

1. `UKB_N_TABLE`: a tab-delimited table with `trait_id` and `N`, plus optional
   provenance columns. IDs match source filenames without `.txt.gz`, including
   leading zeros. Every selected trait must have a unique, positive finite N.
   `trait_sample_sizes.example.tsv` is a placeholder template, not real data.
2. `UKB_N_COLUMN`: the exact column holding per-variant sample size in each input.
3. `UKB_N`: one verified positive finite sample size applied to all selected
   variants/traits. Use only if justified for the source release.

There is **no default N=40,000**. Do not infer sample size from the name BIG40.
Retain the provider/source documentation supporting your choice.

### Input schemas and preparation

UKB files require `rsid a1 a2 beta pval(-log10)`, and the configured sample-size
column if applicable. Confirm that `beta` is signed relative to `a1` and that the
P-value column is negative base-10 logarithm, not a raw P value.

The standardizer streams rows to a temporary gzip file, converts P values, and
atomically replaces the completed output. Invalid numerical/missing rows are
counted and excluded; malformed row widths fail the job. Extremely small P values
are floored at the smallest positive normal Python float, as in the earlier
implementation. Per-trait QC records row counts and the sample-size source.
LDSC's own munging then performs its usual SNP and allele filtering.

For externalizing, provide one of:

- `EXT_STANDARDIZED`: gzip text with `SNP A1 A2 BETA P N`. This script validates
  the file and munges it; it does not construct these columns from an original GWAS.
- `EXT_MUNGED`: gzip text with `SNP A1 A2 Z N`, already prepared with compatible
  LDSC/allele conventions. It is validated and copied atomically into the run.

Preserve the original GWAS release, source URL/accession, checksums, ancestry,
genome build, effect-allele convention, externalizing preprocessing commands, and
LDSC/reference versions in your own run records. No credentials or participant
data should be committed here.

## Run

After configuring a new run directory, submit the complete pipeline:

```bash
bash 06_run_full_pipeline.slurm
```

The launcher builds the manifest, submits externalizing preparation and
standardization, then submits LDSC after both succeed. Collection waits for those
jobs to terminate even after failure/cancellation. QC runs after collection
regardless of its exit status. `--kill-on-invalid-dep=yes` prevents the LDSC job
remaining indefinitely pending after a failed prerequisite.

The launcher records job IDs in `BASE/pipeline_jobs.tsv`; submission success is
not analysis success. It refuses a second full submission to that run directory.
If submission fails partway, inspect the recorded jobs before starting a new run.
A launcher killed without cleanup can leave `BASE/.launch_lock`; remove that
empty lock only after confirming no launcher is active.

Individual steps are also available:

```bash
bash 00_build_manifest.sh
bash 01_prepare_externalizing.sh
bash 02_submit_standardize.sh 40
# Wait for the standardization array to finish successfully before the next step.
bash 03_submit_ldsc_rg_full.sh 80
# Wait for the LDSC array to terminate before collecting and checking.
bash 04_collect_rg_results.sh
bash 05_check_missing_or_failed.sh
```

The two submission wrappers accept only an optional concurrency limit. Sample
sizes belong in configuration. The standardization wrapper rebuilds the manifest;
never invoke it while an earlier array using that manifest is active.

When invoking array workers directly with `sbatch`, export
`PIPELINE_SCRIPTS_DIR` as the absolute checkout directory and provide
`SLURM_ARRAY_TASK_ID` via a job array. The wrappers handle this automatically.

Each worker recomputes its outputs; it does not silently reuse nonempty files.
Use a new `BASE` to preserve previous analyses. A direct rerun of a worker replaces
its prior output/log. Munging logs are retained on both success and ordinary
command failure; hard scheduler termination may prevent trap cleanup, in which
case consult the scheduler log as well.

## Outputs and QC

- `manifests/ukb_manifest.tsv`: selected inputs, output paths, and N sources.
- `qc/excluded_input_files.tsv`: other `.txt.gz` files excluded by the selection
  pattern. Review this to catch unintended omissions.
- `harmonized/` and `munged/`: standardized and LDSC-ready statistics.
- `logs/*.munge.log`: retained munging logs, alongside scheduler logs.
- `results/*__vs__externalizing.log`: LDSC logs, including failed attempts where
  available. Standard LDSC `--rg` does not require a `.results` sidecar.
- `rg_results_full.tsv`: one row per expected phenotype, with `Status` and
  `Problem`; missing/failed traits cannot disappear silently.
- `qc/missing_rg_traits.tsv`, `qc/failed_rg_traits.tsv`, and
  `qc/warnings_rg_traits.tsv`: diagnostics. The QC command exits nonzero for any
  missing/failed result.
- `run_metadata.txt` and `pipeline_jobs.tsv`: launch information.

The parser uses the final standard LDSC summary table, validates finite rg/Z,
positive SE, and P in [0,1], and checks for exceptions and a completion footer.
An `NA` estimate is a failed numerical result even if LDSC exits zero. Finite rg
outside [-1,1] is reported as a warning rather than automatically discarded.
Warnings and a technical `ok` status do not replace scientific quality control.

`H2_intercept_trait1` is the UKB IDP heritability intercept;
`H2_intercept_trait2` is the externalizing heritability intercept;
`Gcov_intercept` is the cross-trait covariance intercept.
`N_valid_allele_SNPs` is the count reported at LDSC's allele-validation stage,
not necessarily the final post-filter regression SNP count. Do not use it as a
substitute for a manuscript-specific regression-SNP QC threshold.

## Validation

```bash
python3 -m unittest discover -s tests -v
for f in *.sh *.slurm lib/*.sh; do bash -n "$f" || exit; done
```

Tests generate synthetic inputs/logs in temporary directories. They cover explicit
sample sizes, invalid values, correct intercept/Z/P parsing, paths containing
spaces, missing/incomplete/NA/error results, log retention, and mocked SLURM
dependencies. They do not submit real jobs, run the real LDSC estimator, or
validate the study's findings. A real-cluster pilot with authorized inputs remains
necessary before a production analysis.

## Code and data availability

This repository distributes code, documentation, and synthetic test definitions.
It does not distribute participant-level data, input GWAS summary-statistic files,
or other restricted research datasets. Obtain required inputs from their original
providers and follow applicable access, use, and redistribution terms. The software
license does not grant rights to external datasets or third-party software.

The existing software terms and copyright notice are in [LICENSE](LICENSE).
Third-party software, including LDSC, retains its own license.

## Citation

Wei M, Peng Q. *Genetic Correlation Between Brain Imaging Phenotypes and
Externalizing Behavior: A Large-Scale LDSC Analysis of UK Biobank IDPs*.
medRxiv [Preprint]. 2026.
[doi:10.64898/2026.07.12.26357891](https://doi.org/10.64898/2026.07.12.26357891).
[PubMed record](https://pubmed.ncbi.nlm.nih.gov/42528560/).

Please cite the associated preprint when using this work, and cite LDSC and each
input data resource as appropriate. A citation request is separate from the
software license's conditions. Record the exact code commit used in your analysis.

## Technical references

- [LDSC genetic-correlation tutorial and output format](https://github.com/bulik/ldsc/wiki/Heritability-and-Genetic-Correlation)
- [LDSC source and installation](https://github.com/bulik/ldsc)
- [SLURM sbatch dependencies](https://slurm.schedmd.com/sbatch.html)
