# Differences from MethylDackel

MethylExtractor is a fork of [MethylDackel](https://github.com/dpryan79/MethylDackel) (earlier name PileOMeth) by Devon P. Ryan. Upstream extracts per-cytosine methylation from coordinate-sorted, indexed BS-seq alignments. If you use this fork in work that also depends on MethylDackel behavior, cite that repository: <https://github.com/dpryan79/MethylDackel>.

## License

Both programs are MIT. [`LICENSE`](https://github.com/Goliath-Research/MethylExtractor/blob/main/LICENSE) in this repository keeps:

- Copyright (c) 2015 Devon P. Ryan
- Copyright (c) contributors to MethylExtractor

The MIT permission notice must stay on copies and substantial portions of the software. Local changes are under the same MIT terms. Vendored `src/cjson/cJSON.c` keeps Copyright (c) 2009-2017 Dave Gamble and cJSON contributors. HTSlib, HDF5, and Zstd are linked under their own licenses and are not relicensed by this file.

## What this program is for

One executable reads a BAM plus a reference and writes per-chromosome counts. There are no subcommands.

Upstream `MethylDackel` is a multi-command tool. The behaviors below are from [its README](https://github.com/dpryan79/MethylDackel/blob/master/README.md) as published upstream, set next to what `src/` in this repository does.

| Topic | MethylDackel | MethylExtractor 2026.10.1 |
|-------|----------------|---------------------------|
| Commands | `extract`, `mbias`, `mergeContext`, `perRead` | A single `main`. No mbias plots and no merge step |
| Default output | bedGraph (`chromosome`, 0-based half-open interval, percent, methylated, unmethylated), optional methylKit / fraction / logit / counts | HDF5 dataset `methylation_data` (`pos` 1-based, `mC`, `uC`, `tnc`), optional TSV, JSON sidecar |
| Contexts | CpG by default; `--CHG`, `--CHH`, `--noCpG` | `CG` always. `-G` / `-H` add CHG / CHH. CpG cannot be turned off |
| Merging a CpG | `--mergeContext` sums the two strands into one interval | Each strand stays its own record |
| Minimum depth | Sites with coverage ≥ 1 are written unless `--minDepth` is set | `--min-cov` defaults to **4** |
| MAPQ / Phred | Defaults MAPQ ≥ 10 and Phred ≥ 5 (`-q`, `-p`) | Defaults MAPQ ≥ **30** and Phred ≥ **20** (`-q`, `-p`) |
| Flag filter | Skips secondary, QC-fail, duplicate, and supplementary; `-F` / `--keepDupes` can change that | Same four flags, plus unmapped, are always dropped. No flag override |
| Multimappers | Optional mappability bigWig or BBM (`libBigWig`) | Drops reads whose `NH` tag is greater than 1. No bigWig |
| Overlap | Default: mates that overlap are not both counted; qualities are combined the way `samtools mpileup` combines them, then `-p` is applied | Coordinate clip: the left mate (smaller `POS`) skips bases at or after the mate start; equal starts yield read2. Qualities are not combined |
| Methylation bias | `mbias` SVG plots and `--OT` / `--OB` / `--CTOT` / `--CTOB` include bounds | No mbias command and no end-trimming bounds |
| Conversion and variants | `--minConversionEfficiency`, `--maxVariantFrac`, `--minOppositeDepth` | Not implemented |
| Per-read output | `perRead`: read name, chromosome, position, CpG percent, informative bases | `-R` writes a sparse per-tile pattern histogram. `--mhap` writes per-read CpG positions and calls. Neither is the `perRead` table |
| Reference and contigs | `MethylDackel extract reference.fa alignments.bam` | FASTA plus `chrom_mapping.json` so FASTA contig, BAM contig, and output stem can differ |
| Threads | Not the model this fork uses | pthread region workers and a memory-gated chromosome pool |
| Compression | Text bedGraph | In-file Zstd filter 32015, gzip if the plugin is absent |

Calling conventions that are still in the same family: Bismark `XG` / `XM` tags when they are present, otherwise C/T on OT/CTOT and G/A on OB/CTOB, and both CpG and (optionally) CHG/CHH contexts.

## Dependencies this fork uses instead of libBigWig

The dynamic link line is HTSlib, HDF5 (serial), pthread, and libm. Zstd is used through the HDF5 plugin at runtime, not through a direct `-lzstd` on the MethylExtractor link line (`make dynamic`). cJSON is compiled in.
