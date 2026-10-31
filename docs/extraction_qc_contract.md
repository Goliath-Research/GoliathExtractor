# Extraction QC files

GoliathExtractor writes three JSON documents. Schema names and versions are the string constants in `include/goliath_extractor.h`. Nothing in this program turns those numbers into a pass or fail.

Large integers are emitted with cJSON as doubles, so integers above 2^53 are not exact.

## `{name}.json` or `{name}-{ctx}.json`

Written by `write_context_qc_json` next to a count file that was actually produced. `schema_name` is `goliath_extractor.context_qc`, `schema_version` is `1.0.0`.

Legacy top-level fields, computed on sites that passed `--min-cov` after any cap rescaling:

| Field | Meaning |
|-------|---------|
| `num_positions` | Sites written |
| `total_methylated` | Sum of `mC` |
| `total_unmethylated` | Sum of `uC` |
| `avg_methylation_level` | `total_methylated / (total_methylated + total_unmethylated)`, or 0 |
| `avg_coverage` | Mean of `mC + uC` on the written sites |

`metadata`:

| Field | Meaning |
|-------|---------|
| `schema_name`, `schema_version` | Constants above |
| `exported_at_utc` | UTC timestamp `%Y-%m-%dT%H:%M:%SZ` |
| `chromosome` | Map `name` |
| `context` | `CG`, `CHG`, `CHH`, or `ALL` when `-s` is off |
| `companion_output` | Path of the H5 or TXT passed to the writer |
| `filters.min_mapq`, `min_phred`, `min_cov`, `cap_cov` | CLI values |

`sites` (from the pre-filter buffer, except `sites_passing_min_cov`):

| Field | Meaning |
|-------|---------|
| `sites_in_reference` | Sites enumerated for this file |
| `sites_passing_min_cov` | Same number as `num_positions` |
| `sites_with_any_coverage` | Sites with coverage > 0 |
| `sites_below_min_cov` | Sites with coverage > 0 and coverage `< --min-cov` |
| `sites_capped` | Sites rescaled because `--cap-cov` was non-zero |
| `fraction_sites_covered` | `sites_passing_min_cov / sites_in_reference`, present when the denominator is > 0 |

`coverage` percentiles use a 256-bin histogram over **all** enumerated sites in the file, including coverage 0. Coverage ≥ 256 shares one bin and is reported as 256.

| Field | Meaning |
|-------|---------|
| `mean_on_passing_sites` | Same as top-level `avg_coverage` |
| `mean_all_sites` | Mean coverage including sites that failed `--min-cov` |
| `median_all_sites`, `p10_all_sites`, `p90_all_sites` | Histogram percentiles |

`methylation.level` matches `avg_methylation_level` on the written sites. `methylation.by_strand.plus` and `.minus` are fractions computed on the **pre-filter** buffer (all enumerated sites), and they are 0 when that strand has no counts. `total_methylated` and `total_unmethylated` under `methylation` match the legacy totals (post-filter, post-cap).

`read_filtering` is present when filter stats were passed in. Counters:

`reads_seen`, `reads_used`, `reads_dropped_unmapped`, `reads_dropped_secondary`, `reads_dropped_qc_fail`, `reads_dropped_duplicate`, `reads_dropped_supplementary`, `reads_dropped_low_mapq`, `reads_dropped_multimap`, `reads_dropped_no_strand`, `bases_skipped_overlap_clip`, `bases_skipped_low_phred`, `bases_skipped_non_cytosine`, `bases_counted_methylated`, `bases_counted_unmethylated`.

`read_retention_rate` (`reads_used / reads_seen`) is added when `reads_seen > 0`. The same per-chromosome filter block is attached to every context file of that chromosome. `reads_dropped_no_strand` is in the struct; `getRealStrand` returns 1–4 on every path, so the counter stays 0 for those paths.

## `{sample_id}.extraction_manifest.json`

`write_extraction_manifest`. `metadata.schema_name` is `goliath_extractor.extraction_manifest`, `schema_version` `1.0.0`.

`metadata` also has `exported_at_utc`, `sample_id`, `sample_dir` (the output directory), `bam_file`, `reference`, `contexts_extracted` (`CG`, plus `CHG` and/or `CHH` when those flags were set), and `filters` (`min_mapq`, `min_phred`, `min_cov`, `cap_cov`, `split_context_files` as 0 or 1).

`summary.chromosomes_processed` is the number of chromosomes that entered the worker list.

Summary methylation totals are summed only from context names `CG`, `CHG`, and `CHH`. Those names are written when `-s` is set. Without `-s`, each chromosome has a single context `ALL`, `context_index` ignores it, and the `cpg_*` / `chg_*` / `chh_*` fields below are omitted.

When the summed CG `num_positions` is greater than 0, `summary` also includes:

| Field | Meaning |
|-------|---------|
| `cpg_sites_passing_min_cov` | Sum of written CG positions |
| `cpg_sites_in_reference` | Sum of enumerated sites on those CG records |
| `cpg_weighted_mean_coverage` | `(methylated + unmethylated) / cpg_sites_passing_min_cov` |
| `cpg_methylation_level` | Present when the CG methylated + unmethylated total is > 0 |
| `cpg_fraction_sites_covered` | Present when `cpg_sites_in_reference > 0` |

`chg_methylation_level` is present when `-G` was set and the CHG methylated + unmethylated total is > 0. `chh_methylation_level` is the same for `-H`.

`read_filtering` on the manifest is the sum of per-chromosome filter stats.

`per_chromosome` is an object keyed by map name. Each value has one object per written context plus `read_filtering`. A context object has `num_positions`, `methylation_level`, `mean_coverage`, `total_methylated`, `total_unmethylated`, and `companion_output`. Those names differ from the legacy sidecar keys (`avg_methylation_level`, `avg_coverage`).

## `{sample_id}.timing.json`

`write_extraction_timing`. Top-level `schema_name` is `goliath_extractor.timing`, `schema_version` `1.0.0`.

| Field | Meaning |
|-------|---------|
| `total_ms` | Wall time from just before `process_chromosomes_parallel` until it returns |
| `bam_ms` | Sum of per-chromosome `bam_scan_ms` |
| `write_ms` | Sum of per-chromosome `hdf5_write_ms` |
| `bam_fraction`, `write_fraction` | Those sums divided by `total_ms` (the divisor is 1 when wall time is 0) |
| `chrom_parallel`, `region_threads`, `max_rss_gb`, `n_chromosomes` | Values used for the run |
| `chromosomes` | Array, one object per chromosome that entered the worker list |

Each chromosome object: `name`, `site_enum_ms`, `bam_scan_ms`, `merge_ms`, `hdf5_write_ms`, `qc_json_ms`, `total_ms`, `rss_est_bytes`. `hdf5_write_ms` includes pattern and haplotype writes, which happen in that same window. `qc_json_ms` is accumulated under the export lock while each sidecar is written. `rss_est_bytes` is the estimate from `estimate_chromosome_rss_bytes`, not a sampled RSS.
