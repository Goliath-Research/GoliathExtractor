---
name: GoliathExtractor C performance
overview: Phase timers, a shared BAM index, and memory-gated multi-chromosome parallelism in the C extractor.
todos:
  - id: instrument-timing
    content: Elapsed-ms phase timers and {sample}.timing.json
    status: completed
  - id: intra-chrom-io
    content: Share the BAM index across region threads; hts_set_threads on each samFile; log the Zstd plugin at startup
    status: completed
  - id: chrom-pool
    content: --chrom-parallel and --max-rss-gb with a largest-first pool
    status: completed
  - id: parity-test
    content: tests/integration/test_bam_to_manifest.py::test_chrom_parallel_identity compares chrom_parallel 1 and 2 on the toy BAM
    status: completed
isProject: false
---

# GoliathExtractor C performance

The behavior that landed is documented in [Performance](../performance.md). Short version of the code:

- Chromosomes used to run one after another while `-t` only split sites inside the current chromosome. `--chrom-parallel` (default 2) now runs a pool, longest chromosome first.
- `--threads` is split across the chromosomes that are in flight (`max(1, threads / chrom_parallel)` region workers each).
- `--max-rss-gb` (default 32) is compared with `estimate_chromosome_rss_bytes`. The startup check forces one chromosome at a time when the two largest estimates do not fit. The pool applies the same gate while it is running.
- `{sample_id}.timing.json` (`goliath_extractor.timing` 1.0.0) records wall time and per-chromosome phase milliseconds. Summed BAM and write times can exceed wall time when chromosomes overlap.
- HDF5 and JSON writers take one process-wide lock.
- `tests/integration/test_bam_to_manifest.py` checks that `--chrom-parallel=1` and `--chrom-parallel=2` write the same `1-CG.h5` bytes and the same manifest counts on the toy BAM.

A wall-clock target for a particular production BAM is not stored as a test in this repository. Use `timing.json` from the run you care about.
