#!/usr/bin/env python3
"""Streaming input preparation and LDSC log validation; Python standard library only."""
import argparse
import csv
import fnmatch
import gzip
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


def finite(value, label, positive=False):
    number = float(value)
    if not math.isfinite(number) or (positive and number <= 0):
        raise ValueError(f"{label} must be finite" + (" and positive" if positive else ""))
    return number


def atomic_tsv(path, columns, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_manifest(path):
    with open(path, newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required = {"order", "trait_id", "src_path", "std_path", "N", "N_column"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("Manifest has wrong columns; rebuild with 00_build_manifest.sh")
        rows = list(reader)
    if not rows:
        raise ValueError("Manifest contains no traits")
    seen = set()
    for index, row in enumerate(rows, 1):
        if row["order"] != str(index) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", row["trait_id"]):
            raise ValueError("Invalid manifest order or trait ID")
        if row["trait_id"] in seen:
            raise ValueError("Duplicate trait ID in manifest")
        seen.add(row["trait_id"])
    return rows


def trait_row(args):
    rows = read_manifest(args.manifest)
    if not 1 <= args.task <= len(rows):
        raise ValueError("Task index outside manifest")
    return rows[args.task - 1]


def build_manifest(args):
    source = Path(args.source).resolve()
    if not source.is_dir():
        raise ValueError("UKB source directory does not exist")
    if sum(bool(v) for v in (args.n, args.n_column, args.n_table)) != 1:
        raise ValueError("Set exactly one of UKB_N, UKB_N_COLUMN, UKB_N_TABLE")
    sizes = {}
    if args.n_table:
        with open(args.n_table, newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            if not {"trait_id", "N"}.issubset(reader.fieldnames or []):
                raise ValueError("Sample-size TSV requires trait_id and N columns")
            for row in reader:
                key = row["trait_id"]
                if key in sizes:
                    raise ValueError(f"Duplicate sample-size entry: {key}")
                sizes[key] = str(finite(row["N"], "N", positive=True))
    if args.n:
        finite(args.n, "UKB_N", positive=True)
    paths = sorted((p for p in source.iterdir() if p.is_file() and fnmatch.fnmatchcase(p.name, args.pattern)), key=lambda p: p.name)
    if not paths:
        raise ValueError("No input files match UKB_FILE_GLOB")
    rows = []
    for index, path in enumerate(paths, 1):
        if not path.name.endswith(".txt.gz"):
            raise ValueError("Selected UKB files must end in .txt.gz")
        trait = path.name[:-7]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", trait):
            raise ValueError(f"Unsafe trait filename: {path.name}")
        if any(c in str(path) for c in "\t\n\r"):
            raise ValueError("Input paths cannot contain tabs or newlines")
        if args.n_table and trait not in sizes:
            raise ValueError(f"Missing sample size for trait {trait}")
        rows.append(dict(order=index, trait_id=trait, src_path=str(path),
                         std_path=str(Path(args.harmonized).resolve() / f"big40_{trait}.std.tsv.gz"),
                         N=sizes.get(trait, args.n), N_column=args.n_column))
    atomic_tsv(args.manifest, list(rows[0]), rows)
    selected = {p.name for p in paths}
    excluded = [{"filename": p.name} for p in sorted(source.glob("*.txt.gz")) if p.name not in selected]
    atomic_tsv(args.excluded, ["filename"], excluded)
    print(f"[ok] manifest: {len(rows)} traits; {len(excluded)} other .txt.gz files excluded by pattern")


def standardize(args):
    row = trait_row(args)
    if bool(row["N"]) == bool(row["N_column"]):
        raise ValueError("Manifest must specify either N or N_column")
    constant_n = finite(row["N"], "N", True) if row["N"] else None
    destination = Path(row["std_path"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=destination.name + ".", dir=destination.parent)
    os.close(fd)
    counts = dict(read=0, written=0, invalid=0, p_clamped=0)
    try:
        with gzip.open(row["src_path"], "rt") as source, gzip.open(temp, "wt") as output:
            columns = source.readline().split()
            required = ["rsid", "a1", "a2", "beta", "pval(-log10)"]
            if row["N_column"]:
                required.append(row["N_column"])
            if len(columns) != len(set(columns)) or not set(required).issubset(columns):
                raise ValueError("Missing or duplicate UKB header columns")
            positions = {key: columns.index(key) for key in required}
            output.write("SNP\tA1\tA2\tBETA\tP\tN\n")
            for line in source:
                if not line.strip():
                    continue
                counts["read"] += 1
                values = line.split()
                if len(values) != len(columns):
                    raise ValueError(f"Wrong column count on input line {counts['read'] + 1}")
                v = {key: values[index] for key, index in positions.items()}
                try:
                    beta = finite(v["beta"], "beta")
                    logp = finite(v["pval(-log10)"], "-log10(P)")
                    n = constant_n if constant_n is not None else finite(v[row["N_column"]], "N", True)
                    if logp < 0 or any(v[k].lower() in {"na", "nan", "."} for k in ("rsid", "a1", "a2")):
                        raise ValueError("Invalid p-value or missing SNP/allele")
                except ValueError:
                    counts["invalid"] += 1
                    continue
                p = 10.0 ** (-logp)
                if p < sys.float_info.min:
                    p = sys.float_info.min
                    counts["p_clamped"] += 1
                output.write(f"{v['rsid']}\t{v['a1']}\t{v['a2']}\t{beta:.17g}\t{p:.17g}\t{n:.17g}\n")
                counts["written"] += 1
        if not counts["written"]:
            raise ValueError("No usable variants after standardization")
        os.replace(temp, destination)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    Path(args.qc).write_text(json.dumps({"trait_id": row["trait_id"], "input": row["src_path"],
                                       "N": row["N"], "N_column": row["N_column"], **counts}, indent=2) + "\n")
    print(f"[ok] standardized {row['trait_id']}: {counts}")


def validate_sumstats(args):
    required = {"SNP", "A1", "A2", "N", "Z" if args.kind == "munged" else "BETA"}
    if args.kind == "standardized":
        required.add("P")
    usable = 0
    with gzip.open(args.path, "rt") as source:
        columns = source.readline().split()
        if len(columns) != len(set(columns)) or not required.issubset(columns):
            raise ValueError(f"Invalid {args.kind} sumstats header")
        for line in source:
            if not line.strip():
                continue
            values = line.split()
            if len(values) != len(columns):
                raise ValueError("Wrong column count in sumstats")
            row = dict(zip(columns, values))
            # Munged HM3-aligned files legitimately contain rows with missing Z/N.
            try:
                finite(row["N"], "N", True)
                finite(row["Z" if args.kind == "munged" else "BETA"], "effect")
                if args.kind == "standardized" and not 0 < finite(row["P"], "P") <= 1:
                    raise ValueError("P outside (0, 1]")
                if any(row[k].lower() in {"na", "nan", "."} for k in ("SNP", "A1", "A2")):
                    raise ValueError("Missing allele")
            except ValueError:
                continue
            usable += 1
    if not usable:
        raise ValueError("No usable sumstats rows")
    print(f"[ok] {args.kind} sumstats: {usable} usable rows")


def chromosome(prefix, number):
    return prefix.replace("@", str(number)) if "@" in prefix else prefix + str(number)


def references(args):
    missing = []
    for label, prefix in (("reference", args.ref), ("weights", args.weights)):
        for number in range(1, 23):
            stem = chromosome(prefix, number)
            if not any(Path(stem + ".l2.ldscore" + suffix).is_file() for suffix in ("", ".gz", ".bz2")):
                missing.append(f"{label}: {stem}.l2.ldscore[.gz/.bz2]")
            if label == "reference" and not Path(stem + ".l2.M_5_50").is_file():
                missing.append(f"reference: {stem}.l2.M_5_50")
    if missing:
        raise ValueError("Missing LD reference files; check trailing slash/dot in prefixes:\n" + "\n".join(missing))
    print("[ok] reference and weight files found for chromosomes 1-22")


RESULT_COLUMNS = ["Trait", "Rg", "SE", "Z", "P", "H2_intercept_trait1", "H2_intercept_trait2",
                  "Gcov_intercept", "N_valid_allele_SNPs", "Status", "Problem", "Warnings", "LogFile"]


def parse_log(path, trait=""):
    path = Path(path)
    result = dict.fromkeys(RESULT_COLUMNS, "NA")
    result.update(Trait=trait, Status="failed", Problem="", Warnings="", LogFile=str(path))
    if not path.is_file() or path.stat().st_size == 0:
        result.update(Status="missing", Problem="missing_or_empty_log")
        return result
    text = path.read_text(errors="replace")
    lines = text.splitlines()
    result["Warnings"] = "; ".join(line.strip() for line in lines if "WARNING" in line.upper())
    if re.search(r"(?im)^\s*(?:Traceback\b|ERROR\b|[A-Za-z_][A-Za-z_0-9]*(?:Error|Exception):)", text):
        result["Problem"] = "error_in_log"
        return result
    if not re.search(r"(?m)^Analysis finished at ", text):
        result["Problem"] = "incomplete_log"
        return result
    markers = [i for i, line in enumerate(lines) if line.strip() == "Summary of Genetic Correlation Results"]
    if not markers:
        result["Problem"] = "missing_rg_summary"
        return result
    section = [line.split() for line in lines[markers[-1] + 1:] if line.strip()]
    try:
        header, values = section[0], section[1]
        if len(values) < len(header) or header[:2] != ["p1", "p2"] or not {"rg", "se", "z", "p", "h2_int", "gcov_int"}.issubset(header):
            raise ValueError("Unexpected summary layout")
        # The two input paths may contain spaces; numerical columns form a fixed suffix.
        summary = dict(zip(header[2:], values[-(len(header) - 2):]))
        for output, key in (("Rg", "rg"), ("SE", "se"), ("Z", "z"), ("P", "p"),
                            ("H2_intercept_trait2", "h2_int"), ("Gcov_intercept", "gcov_int")):
            result[output] = str(finite(summary[key], key, key == "se"))
        if not 0 <= float(result["P"]) <= 1:
            raise ValueError("P outside [0, 1]")
    except (IndexError, KeyError, ValueError):
        result["Problem"] = "invalid_or_unavailable_rg_summary"
        return result
    in_first_trait = False
    for line in lines:
        if line.strip() == "Heritability of phenotype 1":
            in_first_trait = True
        elif line.startswith("Heritability of phenotype") or line.strip() == "Genetic Covariance":
            in_first_trait = False
        elif in_first_trait and line.startswith("Intercept:"):
            value = line.split(":", 1)[1].strip()
            value = value.replace("constrained to ", "").split()[0]
            try:
                result["H2_intercept_trait1"] = str(finite(value, "intercept"))
            except ValueError:
                result["Problem"] = "invalid_trait1_intercept"
                return result
    counts = re.findall(r"(?m)^([0-9]+) SNPs with valid alleles\.", text)
    if counts:
        result["N_valid_allele_SNPs"] = counts[-1]
    if result["H2_intercept_trait1"] == "NA" or not counts or int(counts[-1]) <= 0:
        result["Problem"] = "missing_intercept_or_snp_count"
        return result
    if abs(float(result["Rg"])) > 1:
        result["Warnings"] += "; finite_rg_outside_minus1_plus1"
    result["Status"] = "ok"
    return result


def collect(args):
    rows = [parse_log(Path(args.results) / f"big40_{r['trait_id']}__vs__externalizing.log", f"big40_{r['trait_id']}")
            for r in read_manifest(args.manifest)]
    atomic_tsv(args.output, RESULT_COLUMNS, rows)
    print(f"[ok] collected {len(rows)} traits, {sum(r['Status'] == 'ok' for r in rows)} valid")


def check(args):
    rows = [parse_log(Path(args.results) / f"big40_{r['trait_id']}__vs__externalizing.log", f"big40_{r['trait_id']}")
            for r in read_manifest(args.manifest)]
    for status, filename in (("missing", "missing_rg_traits.tsv"), ("failed", "failed_rg_traits.tsv")):
        atomic_tsv(Path(args.qc) / filename, RESULT_COLUMNS, [r for r in rows if r["Status"] == status])
    atomic_tsv(Path(args.qc) / "warnings_rg_traits.tsv", RESULT_COLUMNS, [r for r in rows if r["Warnings"]])
    failures = sum(r["Status"] != "ok" for r in rows)
    print(f"[qc] {len(rows) - failures}/{len(rows)} valid; {failures} missing/failed")
    return int(failures > 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("manifest")
    for flag in ("source", "harmonized", "manifest", "excluded"):
        p.add_argument("--" + flag, required=True)
    p.add_argument("--pattern", default="[0-9][0-9][0-9][0-9].txt.gz")
    for flag in ("n", "n-column", "n-table"):
        p.add_argument("--" + flag, default="")
    p.set_defaults(func=build_manifest)
    for command in ("count", "field", "standardize"):
        p = commands.add_parser(command)
        p.add_argument("--manifest", required=True)
        if command != "count":
            p.add_argument("--task", required=True, type=int)
        if command == "field":
            p.add_argument("--field", required=True, choices=["trait_id", "src_path", "std_path"])
            p.set_defaults(func=lambda a: print(trait_row(a)[a.field]))
        elif command == "count":
            p.set_defaults(func=lambda a: print(len(read_manifest(a.manifest))))
        else:
            p.add_argument("--qc", required=True)
            p.set_defaults(func=standardize)
    p = commands.add_parser("validate-sumstats")
    p.add_argument("--path", required=True)
    p.add_argument("--kind", choices=["standardized", "munged"], required=True)
    p.set_defaults(func=validate_sumstats)
    p = commands.add_parser("references")
    p.add_argument("--ref", required=True)
    p.add_argument("--weights", required=True)
    p.set_defaults(func=references)
    p = commands.add_parser("validate-log")
    p.add_argument("--log", required=True)
    def validate_log(a):
        result = parse_log(a.log)
        print(json.dumps({k: result[k] for k in ("Status", "Problem", "Warnings")}))
        return int(result["Status"] != "ok")
    p.set_defaults(func=validate_log)
    for command in ("collect", "check"):
        p = commands.add_parser(command)
        p.add_argument("--manifest", required=True)
        p.add_argument("--results", required=True)
        p.add_argument("--output" if command == "collect" else "--qc", required=True)
        p.set_defaults(func=collect if command == "collect" else check)
    args = parser.parse_args()
    try:
        return args.func(args) or 0
    except (ValueError, OSError, EOFError, csv.Error) as error:
        print(f"[fatal] {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
