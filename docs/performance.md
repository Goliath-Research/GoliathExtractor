# Performance

The knobs below are the ones the binary implements. Wall-clock time depends on the BAM, the contexts you enable, whether `-R` or `--mhap` is on, and whether filter 32015 is loaded. This repository does not ship a benchmark number.

## How work is split

Chromosomes run through `process_chromosomes_parallel`, longest reference length first.

`--chrom-parallel` (default 2) is the maximum number of chromosomes in flight. It is reduced to 1 before the pool starts when the sum of `estimate_chromosome_rss_bytes` for the two longest chromosomes is greater than `--max-rss-gb` (default 32) gibibytes. The pool also refuses to start another chromosome while the sum of in-flight estimates would exceed that byte budget, and it waits for a slot.

`--threads` (default: online CPU count, or 16) is divided by the chromosome parallelism actually used. Each chromosome gets that many region threads, and at least one. Regions are contiguous slices of the enumerated site list. Each region thread opens its own `samFile`, shares the BAM index, and queries `[start, end)` with `sam_itr_queryi`. The BAM header is read once in `main` and is not read again per region.

Per region, methylated and unmethylated tallies sit in dense `uint32` arrays covering the region's reference span. Those arrays, the FASTA buffer, and the site table dominate the estimate in `estimate_chromosome_rss_bytes`. Turning on `-R` adds a `pos_to_cpg` map per active context (one context without `-s`, otherwise one per enabled context). `--mhap` stores per-read CpG lists on top of that estimate; the estimator does not add the haplotype store.

Count merges and HDF5/JSON writes for a chromosome happen after its region threads join. HDF5 creates and cJSON writes take one process-wide recursive mutex (`export_lock`), so chromosome parallelism overlaps BAM scans more than it overlaps file writes.

## What `{sample_id}.timing.json` records

| Field | Phase |
|-------|--------|
| `site_enum_ms` | Walk the reference and fill the empty site buffer |
| `bam_scan_ms` | Region threads, from create/join around the scan |
| `merge_ms` | Add region counts into the site buffer and merge haplotype stores |
| `hdf5_write_ms` | Pattern file, haplotype file, and count file |
| `qc_json_ms` | Context JSON sidecars |
| `total_ms` | That chromosome |
| `rss_est_bytes` | Estimate, not a sampled RSS |

Sample `bam_ms` and `write_ms` are sums of the chromosome BAM and HDF5-write phases. They can exceed `total_ms` when chromosomes overlap. `bam_fraction` and `write_fraction` still divide those sums by wall `total_ms`, so a fraction above 1 means the phases overlapped.

The same lines are printed to stderr: per chromosome `site_enum`, `bam_scan`, `merge`, `write`, `qc`, `total`, then a sample line with `wall`, `bam_scan_sum`, and `write_sum`.

## Compression and I/O

`-z 0` skips the compression filter and writes a chunked dataset. `-z 1` through `-z 19` calls the Zstd plugin when `HDF5_PLUGIN_PATH` can see `libH5Zzstd.so`. A missing plugin logs `using gzip` and deflates at `min(level, 9)`. Higher Zstd levels spend more CPU in the write phase, which is the phase the export lock serializes.

`--chunk-size` (default 1,000,000 records) is the HDF5 chunk length for `methylation_data`. The count file is rewritten as a whole at the end of the chromosome; the writer does not stream partial chromosomes to disk during the scan.

## What the defaults are aimed at

MAPQ 30, Phred 20, and minimum coverage 4 drop alignments and sites before the write. `-G` and `-H` enlarge the site table toward every C/G. `-R` builds a tile histogram for each active context. Those flags change both CPU and the RSS estimate that feeds `--max-rss-gb`.

If a run is killed or swapping, lower `--chrom-parallel` or `--max-rss-gb`. If `timing.json` shows wall time close to `bam_ms` while `write_fraction` stays small, extra region threads are the BAM-side lever, up to the point where index queries and the shared filesystem stop scaling. If `write_ms` dominates, lower `-z` or install the Zstd plugin so the writer is not on the gzip fallback.
