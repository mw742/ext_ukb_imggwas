"""Synthetic regression checks. No research data, real LDSC runs, or SLURM jobs."""
import csv
import gzip
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pipeline_io", ROOT / "pipeline_io.py")
io = importlib.util.module_from_spec(spec)
spec.loader.exec_module(io)

# All numerical values and file names below are invented test fixtures.
LOG = """Heritability of phenotype 1
Intercept: 1.01 (0.01)
Heritability of phenotype 2/2
Intercept: 0.98 (0.02)
Genetic Covariance
Intercept: 0.02 (0.01)
123456 SNPs with valid alleles.
Genetic Correlation: 0.2 (0.1)
Z-score: 2.0
P: 0.0455
Summary of Genetic Correlation Results
p1 p2 rg se z p h2_obs h2_obs_se h2_int h2_int_se gcov_int gcov_int_se
synthetic1 synthetic2 0.2 0.1 2.0 0.0455 0.1 0.01 0.98 0.02 0.02 0.01
Analysis finished at synthetic-time
"""


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic pipeline ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "run"
        self.source = self.root / "source"
        self.source.mkdir()
        self.config = self.root / "config.sh"
        self.manifest = self.base / "manifests/ukb_manifest.tsv"
        self.write_source("0001", "rs_synthetic A G 0.1 2 1200\n")
        self.settings = dict(BASE=str(self.base), UKB_SOURCE_DIR=str(self.source), UKB_N="1000",
                             PYTHON_BIN=sys.executable, STD_CONCURRENT="2", LDSC_CONCURRENT="3")
        self.write_config()

    def write_source(self, trait, rows):
        with gzip.open(self.source / f"{trait}.txt.gz", "wt") as stream:
            stream.write("rsid a1 a2 beta pval(-log10) n\n" + rows)

    def write_config(self):
        self.config.write_text("\n".join(f"{k}={shlex.quote(v)}" for k, v in self.settings.items()) + "\n")

    def run_script(self, name, *args, ok=True, extra_env=None):
        env = os.environ.copy()
        env.pop("PIPELINE_SCRIPTS_DIR", None)
        env.pop("SLURM_SUBMIT_DIR", None)
        env.update(PIPELINE_CONFIG=str(self.config))
        env.update(extra_env or {})
        p = subprocess.run(["bash", str(ROOT / name), *args], env=env, capture_output=True, text=True)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        else:
            self.assertNotEqual(p.returncode, 0, p.stdout)
        return p

    def test_requires_sample_size_and_reports_excluded_inputs(self):
        self.settings["UKB_N"] = ""
        self.write_config()
        self.run_script("00_build_manifest.sh", ok=False)
        self.settings["UKB_N"] = "1000"
        self.write_source("summary", "rs_test A G 0.2 1 1200\n")
        self.write_config()
        self.run_script("00_build_manifest.sh")
        self.assertEqual(len(io.read_manifest(self.manifest)), 1)
        self.assertIn("summary.txt.gz", (self.base / "qc/excluded_input_files.tsv").read_text())

    def test_standardizer_explicit_n_and_invalid_values(self):
        self.write_source("0001", "rs_good A G 0.1 2 1200\nrs_bad A G 0.1 -1 1200\nrs_inf A G 0.1 inf 1200\nrs_tiny A G 0.1 500 1200\n")
        self.run_script("00_build_manifest.sh")
        self.run_script("01_standardize_ukbfull.slurm", extra_env={"SLURM_ARRAY_TASK_ID": "1"})
        with gzip.open(self.base / "harmonized/big40_0001.std.tsv.gz", "rt") as stream:
            rows = list(csv.DictReader(stream, delimiter="\t"))
        self.assertEqual(len(rows), 2)
        self.assertEqual(float(rows[0]["N"]), 1000)
        self.assertAlmostEqual(float(rows[0]["P"]), .01)
        self.assertGreater(float(rows[1]["P"]), 0)
        qc = json.loads((self.base / "qc/standardize_0001.json").read_text())
        self.assertEqual((qc["invalid"], qc["p_clamped"]), (2, 1))

    def test_per_variant_and_per_trait_sample_sizes(self):
        self.settings.update(UKB_N="", UKB_N_COLUMN="n")
        self.write_config()
        self.run_script("00_build_manifest.sh")
        self.run_script("01_standardize_ukbfull.slurm", extra_env={"SLURM_ARRAY_TASK_ID": "1"})
        with gzip.open(self.base / "harmonized/big40_0001.std.tsv.gz", "rt") as stream:
            self.assertEqual(float(next(csv.DictReader(stream, delimiter="\t"))["N"]), 1200)
        table = self.root / "sizes.tsv"
        table.write_text("trait_id\tN\n0001\t1500\n")
        self.settings.update(UKB_N_COLUMN="", UKB_N_TABLE=str(table))
        self.write_config()
        self.run_script("00_build_manifest.sh")
        self.assertEqual(float(io.read_manifest(self.manifest)[0]["N"]), 1500)
        table.write_text("trait_id\tN\n0002\t1500\n")
        self.run_script("00_build_manifest.sh", ok=False)

    def test_log_parser_fields_and_paths_with_spaces(self):
        log = self.root / "result.log"
        log.write_text(LOG.replace("synthetic1 synthetic2", "/a path/one.gz /another path/two.gz"))
        row = io.parse_log(log)
        self.assertEqual(row["Status"], "ok")
        self.assertEqual((row["Z"], row["P"]), ("2.0", "0.0455"))
        self.assertEqual((row["H2_intercept_trait1"], row["H2_intercept_trait2"], row["Gcov_intercept"]), ("1.01", "0.98", "0.02"))
        self.assertEqual(row["N_valid_allele_SNPs"], "123456")

    def test_log_rejects_na_incomplete_and_error_even_with_footer(self):
        log = self.root / "result.log"
        for text in (LOG.replace("0.2 0.1 2.0 0.0455", "NA NA NA NA"),
                     LOG.replace("Analysis finished at synthetic-time\n", ""),
                     "Traceback (most recent call last):\n" + LOG,
                     LOG.replace("0.2 0.1 2.0 0.0455", "0.2 0.1 2.0 1.5")):
            with self.subTest(text=text):
                log.write_text(text)
                self.assertEqual(io.parse_log(log)["Status"], "failed")

    def test_collector_needs_no_results_file_and_qc_detects_missing(self):
        self.write_source("0002", "rs_other A G 0.1 2 1200\n")
        self.run_script("00_build_manifest.sh")
        (self.base / "results/big40_0001__vs__externalizing.log").write_text(LOG)
        self.run_script("04_collect_rg_results.sh")
        with (self.base / "rg_results_full.tsv").open() as stream:
            rows = list(csv.DictReader(stream, delimiter="\t"))
        self.assertEqual([r["Status"] for r in rows], ["ok", "missing"])
        self.run_script("05_check_missing_or_failed.sh", ok=False)
        second = self.base / "results/big40_0002__vs__externalizing.log"
        second.write_text(LOG.replace("0.2 0.1 2.0 0.0455", "NA NA NA NA"))
        self.run_script("05_check_missing_or_failed.sh", ok=False)
        self.assertIn("invalid_or_unavailable", (self.base / "qc/failed_rg_traits.tsv").read_text())
        second.write_text(LOG)
        self.run_script("05_check_missing_or_failed.sh")

    def fake_environment(self):
        refs = self.root / "refs"
        refs.mkdir()
        for number in range(1, 23):
            (refs / f"{number}.l2.ldscore.gz").write_text("synthetic placeholder\n")
            (refs / f"{number}.l2.M_5_50").write_text("1\n")
        hm3 = self.root / "hm3.snplist"
        hm3.write_text("SNP A1 A2\nrs_test A G\n")
        ext = self.root / "external.sumstats.gz"
        with gzip.open(ext, "wt") as stream:
            stream.write("SNP A1 A2 Z N\nrs_test A G 2 1000\n")
        ldsc = self.root / "fake ldsc"
        ldsc.mkdir()
        (ldsc / "ldsc.py").write_text("# fake LDSC\n")
        (ldsc / "munge_sumstats.py").write_text("# fake munge\n")
        self.settings.update(REF_LD_PREFIX=str(refs) + "/", WEIGHT_LD_PREFIX=str(refs) + "/",
                             HM3=str(hm3), EXT_MUNGED=str(ext), LDSC_DIR=str(ldsc), LDSC_PYTHON=sys.executable)
        self.write_config()
        return ldsc

    def test_reference_prefix_and_launch_failure_dependencies(self):
        self.fake_environment()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        records = self.root / "submissions.jsonl"
        sbatch = bin_dir / "sbatch"
        sbatch.write_text("#!" + sys.executable + "\nimport json,sys,pathlib\np=pathlib.Path(" + repr(str(records)) + ")\nold=p.read_text().splitlines() if p.exists() else []\nwith p.open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nprint(str(101+len(old))+';synthetic-cluster')\n")
        sbatch.chmod(0o755)
        env = {"PATH": str(bin_dir) + os.pathsep + os.environ["PATH"]}
        self.run_script("06_run_full_pipeline.slurm", extra_env=env)
        jobs = [json.loads(line) for line in records.read_text().splitlines()]
        self.assertEqual(len(jobs), 5)
        self.assertIn("--dependency=afterok:101:102", jobs[2])
        self.assertIn("--kill-on-invalid-dep=yes", jobs[2])
        self.assertIn("--dependency=afterany:101:102:103", jobs[3])
        self.assertIn("--dependency=afterany:104", jobs[4])
        self.assertIn("ldsc\t103", (self.base / "pipeline_jobs.tsv").read_text())
        self.run_script("06_run_full_pipeline.slurm", extra_env=env, ok=False)
        self.settings["REF_LD_PREFIX"] = self.settings["REF_LD_PREFIX"].rstrip("/")
        self.write_config()
        self.run_script("03_submit_ldsc_rg_full.sh", extra_env=env, ok=False)
        self.assertEqual(len(records.read_text().splitlines()), 5)

    def test_worker_preserves_logs_and_rejects_zero_exit_na(self):
        ldsc = self.fake_environment()
        self.run_script("00_build_manifest.sh")
        self.run_script("01_prepare_externalizing.sh")
        self.run_script("01_standardize_ukbfull.slurm", extra_env={"SLURM_ARRAY_TASK_ID": "1"})
        (ldsc / "munge_sumstats.py").write_text("import sys,pathlib,gzip\np=sys.argv[sys.argv.index('--out')+1]\npathlib.Path(p+'.log').write_text('synthetic munging log\\n')\nwith gzip.open(p+'.sumstats.gz','wt') as f: f.write('SNP A1 A2 Z N\\nrs_test A G 2 1000\\n')\n")
        fake = "import sys,pathlib\np=sys.argv[sys.argv.index('--out')+1]\npathlib.Path(p+'.log').write_text({log!r})\n"
        (ldsc / "ldsc.py").write_text(fake.format(log=LOG))
        env = {"SLURM_ARRAY_TASK_ID": "1"}
        self.run_script("02_ldsc_rg_full.slurm", extra_env=env)
        self.assertTrue((self.base / "logs/big40_0001.munge.log").is_file())
        result = self.base / "results/big40_0001__vs__externalizing.log"
        self.assertEqual(io.parse_log(result)["Status"], "ok")
        (ldsc / "ldsc.py").write_text(fake.format(log=LOG.replace("0.2 0.1 2.0 0.0455", "NA NA NA NA")))
        self.run_script("02_ldsc_rg_full.slurm", extra_env=env, ok=False)
        self.assertEqual(io.parse_log(result)["Status"], "failed")
        # Even failed munging must preserve the log and cannot leave a stale valid rg log.
        (ldsc / "munge_sumstats.py").write_text("import sys,pathlib\np=sys.argv[sys.argv.index('--out')+1]\npathlib.Path(p+'.log').write_text('synthetic failure\\n')\nsys.exit(1)\n")
        self.run_script("02_ldsc_rg_full.slurm", extra_env=env, ok=False)
        self.assertIn("failure", (self.base / "logs/big40_0001.munge.log").read_text())
        self.assertFalse(result.exists())

    def test_standardized_externalizing_preparation_and_bad_throttle(self):
        ldsc = self.fake_environment()
        standard = self.root / "external.std.tsv.gz"
        with gzip.open(standard, "wt") as stream:
            stream.write("SNP A1 A2 BETA P N\nrs_test A G .1 .04 1000\n")
        self.settings.update(EXT_MUNGED="", EXT_STANDARDIZED=str(standard))
        self.write_config()
        (ldsc / "munge_sumstats.py").write_text("import sys,pathlib,gzip\np=sys.argv[sys.argv.index('--out')+1]\npathlib.Path(p+'.log').write_text('synthetic externalizing munging\\n')\nwith gzip.open(p+'.sumstats.gz','wt') as f: f.write('SNP A1 A2 Z N\\nrs_test A G 2 1000\\n')\n")
        self.run_script("01_prepare_externalizing.sh")
        self.assertTrue((self.base / "munged/externalizing.munged.sumstats.gz").is_file())
        self.assertIn("externalizing", (self.base / "logs/externalizing.munge.log").read_text())
        self.run_script("02_submit_standardize.sh", "0", ok=False)


if __name__ == "__main__":
    unittest.main()
