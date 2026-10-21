# Command line

```text
MethylExtractor [options] <input.bam> [output_dir] [ref.fa]
```

Implemented in `src/main.c`. The program prints the raw `argv` to stderr before doing work, including for `--help` (help is handled after that banner). `--help` / `-h` then prints usage and returns 0.

## Arguments

| Argument | Required | Role |
|----------|----------|------|
| `input.bam` | yes | Coordinate-sorted BAM with an index (`sam_index_load`). A missing index aborts that chromosome |
| `output_dir` | yes, positional or `-o` | Created with `mkdir` if needed. Its final path component, with the suffix after the last `.` removed, is `sample_id` |
| `ref.fa` | one of this or `reference` in the map | Indexed FASTA (`fai_load`). A positional FASTA overrides the map |

A trailing slash on `output_dir` makes the final component empty, so the manifest is written as `/.extraction_manifest.json` under that directory. Pass the directory without a trailing slash.

## Options

| Option | Default | Accepted values |
|--------|---------|-----------------|
| `-t`, `--threads` | online CPU count, else `16` | integer ≥ 1 |
| `-q`, `--min-mapq` | `30` | integer ≥ 0. Reads with MAPQ **less than** this are dropped |
| `-p`, `--min-phred` | `20` | integer ≥ 0. Bases with Phred **less than** this are skipped |
| `-c`, `--min-cov` | `4` | integer ≥ 0. Sites with `mC + uC` below this are left out of the output file |
| `-C`, `--cap-cov` | `0` | integer ≥ 0. See below |
| `-G`, `--CHG` | off | flag |
| `-H`, `--CHH` | off | flag |
| `-m`, `--chrom-mapping` | `<directory of the BAM>/chrom_mapping.json` | path |
| `-z`, `--compression` | `6` | integer `0`–`19` |
| `-k`, `--chunk-size` | `1000000` | integer ≥ 1. HDF5 chunk length |
| `-f`, `--output-format` | `hdf5` | `hdf5`, `txt`, `both` |
| `-s`, `--split` | off | flag |
| `-o`, `--output-dir` | unset | path. Wins over the positional output directory: if `-o` is set, the next positional is the FASTA |
| `-R`, `--read-level` | off | flag |
| `--mhap` | off | flag, long option only |
| `-T`, `--tile-size` | `4` | integer `2`–`8` |
| `--chrom-parallel` | `2` | integer ≥ 1 |
| `--max-rss-gb` | `32` | integer ≥ 1 |

`-t` is the **total** region-worker budget. Each in-flight chromosome receives `max(1, threads / chrom_parallel)` workers. There is no CLI flag for BGZF threads; each region `samFile` uses 2 (`DEFAULT_BGZF_THREADS`) via `hts_set_threads`.

## Coverage cap

`--cap-cov 0` stores the counts that were tallied.

Any positive `--cap-cov` enables rescaling inside `flush_buffer`. The numeric value is copied into the QC JSON `filters.cap_cov` and is not compared with site coverage. The writer computes the mean of `mC + uC` over sites that already pass `--min-cov`. Each of those sites whose coverage is **above that mean** is rewritten so the methylated fraction is unchanged and `mC + uC` equals the mean (`mC` rounded, `uC` set to the remainder). Sites at or below the mean are unchanged. `sites_capped` in the context JSON counts how many sites were rescaled.

## Chromosome map

`load_chrom_mapping` in `src/bam_processing.c` reads a JSON object:

| Field | Role |
|-------|------|
| `reference` | FASTA path, used when no positional FASTA was given |
| `chromosomes` | array |
| `chromosomes[].extract` | JSON `true` required, otherwise the entry is skipped |
| `chromosomes[].fasta` | contig name passed to `faidx_fetch_seq` |
| `chromosomes[].bam` | contig name passed to `bam_name2id` |
| `chromosomes[].name` | string used in output file names (up to 63 bytes) |

`fasta`, `bam`, and `name` must all be non-empty. A BAM contig that is missing, or a FASTA contig that cannot be fetched, is skipped with a message on stderr. Chromosomes that do run are ordered longest-first before the worker pool starts.

`config/grch38_cpg_manifest.json` is a checked-in table of per-chromosome CpG site counts. It is not read by the binary.

## Read filters

For every alignment returned by the region iterator (`src/bam_processing.c`):

| Condition | Counter |
|-----------|---------|
| `BAM_FUNMAP` | `reads_dropped_unmapped` |
| `BAM_FSECONDARY` | `reads_dropped_secondary` |
| `BAM_FQCFAIL` | `reads_dropped_qc_fail` |
| `BAM_FDUP` | `reads_dropped_duplicate` |
| `BAM_FSUPPLEMENTARY` | `reads_dropped_supplementary` |
| MAPQ `< --min-mapq` | `reads_dropped_low_mapq` |
| `NH` tag present and `NH > 1` | `reads_dropped_multimap` |

Reads with no `NH` tag are kept. Flag masks are fixed; there is no include/exclude flag option. A read that contributes at least one counted base increments `reads_used`.

## Base calls

Only reference positions whose base is `C` or `G` are candidates. Other reference bases increment `bases_skipped_non_cytosine`. Bases below `--min-phred` increment `bases_skipped_low_phred`.

Strand comes from `getRealStrand`:

- If the `XG` tag is `C` or `G`, the strand is the Bismark OT/OB/CTOT/CTOB combination of `XG`, `BAM_FREVERSE`, and read1/read2. Stored codes are `1` (OT), `2` (OB), `3` (CTOT), `4` (CTOB).
- Otherwise a paired read uses flags only: read1 forward → `1`, read1 reverse → `2`, read2 reverse → `1`, read2 forward → `2`.
- An unpaired read is `2` when reverse and `1` when forward.

If the `XM` tag is present and has type `Z`, a base is methylated when the tag character is `Z`, `X`, `H`, or `U`, and unmethylated when it is `z`, `x`, `h`, or `u`. Otherwise the sequence is used:

- Reference `C` and strand `1` or `3`: `C` methylated, `T` unmethylated.
- Reference `G` and strand `2` or `4`: `G` methylated, `A` unmethylated.

Other bases at a candidate position are ignored (they do not increment the counted-base counters).

## Contexts

Sites are classified in `get_context` (`src/utils.c`), in this order:

| Context | Flag | Rule |
|---------|------|------|
| `CG` (`1`) | always | Reference `C` followed by `G`, or reference `G` preceded by `C` |
| `CHG` (`2`) | `-G` | Reference `C` with `G` two bases downstream, or reference `G` with `C` two bases upstream, and the site was not already `CG`. The middle base is not inspected |
| `CHH` (`3`) | `-H` | Any remaining reference `C` or `G` |

Plus-strand records are the reference `C` positions. Minus-strand records are the reference `G` positions. The two cytosines of one CpG stay in two records; this program does not merge them.

Output positions are **1-based** (`reference index + 1`).

## Overlapping mates

For a paired read whose mate is mapped on the same contig, the mate with the smaller `POS` skips reference positions at or after the mate's `POS`. If both starts are equal, read2 yields and read1 keeps the base. Skipped bases increment `bases_skipped_overlap_clip`. The decision uses only that alignment's own fields, so it stays the same when the mates fall in different region threads.

## Read-level and haplotype sidecars

`-R` builds tiles of `--tile-size` consecutive sites (default 4, range 2–8). CG tiles are always eligible. CHG and CHH tiles are built only when `-s` is set and the matching context flag is set. The writer keeps a tile when at least one read called every site in the tile (`min_tile_reads` is fixed at 1). Files are `{name}-{ctx}.patterns.h5`.

`--mhap` records up to 256 CpG calls on each alignment and writes `{name}-CG.mhap.h5` when at least one read had a CpG call. It does not require `-s`.

Layouts are in [Output](output.md).

## Parallelism flags

`--chrom-parallel` defaults to 2 and is clamped to the number of chromosomes that actually start. Before the pool starts, if the estimated RSS of the two largest chromosomes is greater than `--max-rss-gb` gibibytes, the program logs a line and forces `--chrom-parallel` to 1. The pool also waits rather than starting another chromosome when the running estimate would pass the same byte budget. The estimate is `estimate_chromosome_rss_bytes` in `src/utils.c` (sequence, site buffer, position index, dense count arrays, and read-level maps). It is an estimate, not a measurement of `VmRSS`.
