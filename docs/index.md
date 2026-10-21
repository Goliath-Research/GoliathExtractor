# MethylExtractor

MethylExtractor extracts cytosine methylation counts from a coordinate-sorted, indexed bisulfite BAM and a reference FASTA. These pages describe the C program built from this repository at release **2026.10.1** (`v2026.10.1`).

The program is a fork of [MethylDackel](https://github.com/dpryan79/MethylDackel), written by Devon P. Ryan and distributed under the MIT license. MethylExtractor keeps that license and the upstream copyright. What this tree adds, and what it does not carry over, is listed in [MethylDackel](upstream.md).

## What a run does

1. Load `chrom_mapping.json` (beside the BAM, or `-m`) and an indexed reference FASTA.
2. For each mapped chromosome with `"extract": true`, enumerate reference cytosine sites. `CG` is always included. `CHG` and `CHH` are included only with `-G` and `-H`.
3. Scan the BAM index in region threads. Drop reads that fail the flag, MAPQ, or `NH` filters. Skip low-Phred bases. Clip overlapping mates by coordinate so a reference position is counted once.
4. Keep sites with coverage at least `--min-cov` (default 4) and write them as HDF5 and/or text, plus a JSON sidecar.
5. Write `{sample_id}.extraction_manifest.json` and `{sample_id}.timing.json` in the output directory.

Pass/fail decisions are not computed here. The JSON files report counts, coverage, methylation fractions, and filter tallies.

## Pages

- [Install](install.md) — `make`, the Zstd plugin, and release tarballs
- [Command line](cli.md) — flags, filters, strand calls, chromosome map
- [Output](output.md) — `methylation_data`, text columns, pattern and haplotype sidecars
- [Extraction QC](extraction_qc_contract.md) — context JSON, manifest, and timing schemas
- [Performance](performance.md) — threads, chromosome parallelism, compression
- [Release packages](release_packaging.md) — self-contained Linux tarballs
- [MethylDackel](upstream.md) — upstream credit and behavioral differences

The repository README is the short form of the same contract.
