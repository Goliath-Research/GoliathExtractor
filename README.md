# MethylExtractor

MethylExtractor extracts cytosine methylation counts from a coordinate-sorted, indexed bisulfite BAM and a reference FASTA. This documentation matches the source at release **2026.10.1** (tag `v2026.10.1`).

It is a performance-focused fork of [MethylDackel](https://github.com/dpryan79/MethylDackel) (Devon P. Ryan, MIT). The fork keeps that license. See [Differences from MethylDackel](docs/upstream.md) and [`LICENSE`](LICENSE).

CpG (`CG`) context is always extracted. `CHG` and `CHH` are off unless you pass `-G` / `--CHG` or `-H` / `--CHH`. The default filters keep reads with MAPQ ≥ 30 and bases with Phred ≥ 20, and they write sites with coverage ≥ 4.

## Install

Debian or Ubuntu, from a clone of this repository:

```bash
make deps    # apt packages, including htslib, HDF5, and zstd (uses sudo)
make         # build/dynamic/<arch>/MethylExtractor
make plugin  # optional Zstd HDF5 filter (libH5Zzstd.so)
```

`<arch>` is `x64` on x86_64 and `arm64` on aarch64. `make` does not run `sudo`. `make install` copies the binary to `/usr/local/bin/MethylExtractor` and the plugin to `/usr/local/hdf5/lib/plugin`, and it appends `HDF5_PLUGIN_PATH` to `~/.bashrc` when that line is absent. It refuses to install a binary or plugin built for another machine.

GitHub Release tag `v2026.10.1` publishes `methyl-extractor-linux-amd64.tar.gz` and `methyl-extractor-linux-aarch64.tar.gz` (each with a `.sha256`). The tarballs are dynamically linked and carry their non-glibc libraries under `lib/`. Details: [Install](docs/install.md), [Release packages](docs/release_packaging.md).

## Usage

```bash
build/dynamic/x64/MethylExtractor [options] <input.bam> [output_dir] [ref.fa]
```

The BAM must be coordinate-sorted and indexed. The output directory is the second positional argument or `-o` / `--output-dir` (one of the two is required; the directory is created). The reference FASTA is the optional third positional. It overrides `reference` in the chromosome map. One of those two must name an indexed FASTA.

Chromosome names come from `chrom_mapping.json` next to the BAM, or from `-m` / `--chrom-mapping`. Only entries with `"extract": true` are processed. `fasta` is the reference contig, `bam` is the BAM contig, and `name` is the output file stem.

```json
{
  "reference": "/path/to/genome.fa",
  "chromosomes": [
    {"name": "1", "fasta": "chr1", "bam": "chr1", "extract": true}
  ]
}
```

### Options

Defaults are the constants in `include/methyl_extractor.h` and the parser in `src/main.c`.

| Option | Default | Effect |
|--------|---------|--------|
| `-h`, `--help` | | Print usage and exit 0 |
| `-t`, `--threads INT` | CPU count (`16` if that count cannot be read) | Region-worker budget. Split across in-flight chromosomes |
| `-q`, `--min-mapq INT` | `30` | Drop reads with MAPQ lower than this |
| `-p`, `--min-phred INT` | `20` | Skip bases with Phred lower than this |
| `-c`, `--min-cov INT` | `4` | Omit sites with `mC + uC` below this from output files |
| `-C`, `--cap-cov INT` | `0` | `0` keeps raw counts. Any positive value rescales sites above the mean coverage of sites that pass `--min-cov` down to that mean. The integer is recorded in the JSON and is not the ceiling |
| `-G`, `--CHG` | off | Also extract CHG |
| `-H`, `--CHH` | off | Also extract CHH |
| `-m`, `--chrom-mapping FILE` | `<bam_dir>/chrom_mapping.json` | Contig map |
| `-z`, `--compression INT` | `6` | `0` = uncompressed HDF5. `1`–`19` = Zstd level when filter `32015` is loaded, otherwise gzip capped at 9 |
| `-k`, `--chunk-size INT` | `1000000` | HDF5 chunk length for `methylation_data` |
| `-f`, `--output-format STR` | `hdf5` | `hdf5`, `txt`, or `both` |
| `-s`, `--split` | off | One file per context (`{name}-CG`, `{name}-CHG`, `{name}-CHH`) |
| `-o`, `--output-dir DIR` | required if omitted positionally | Output directory |
| `-R`, `--read-level` | off | Write `{name}-{ctx}.patterns.h5` |
| `--mhap` | off | Write `{name}-CG.mhap.h5` (long option only) |
| `-T`, `--tile-size INT` | `4` | Consecutive sites per read-level tile (`2`–`8`) |
| `--chrom-parallel INT` | `2` | Maximum chromosomes in flight. Dropped to `1` when the two largest chromosomes exceed `--max-rss-gb` |
| `--max-rss-gb INT` | `32` | RSS gate for chromosome parallelism |

```bash
MethylExtractor \
  -t 16 -q 30 -p 20 -c 4 -G -H -s -f hdf5 -z 6 \
  -m chrom_mapping.json -o results \
  sample.bam reference.fa
```

Full calling rules, overlap clipping, and file names: [Command line](docs/cli.md).

## Output

With `--split`, each kept context is `{output_dir}/{name}-{ctx}.h5` (or `.txt` when `-f txt`). Without `--split`, contexts share `{output_dir}/{name}.h5` and the sidecar context is `ALL`. `-f both` writes the HDF5 file and a sibling `.txt`.

HDF5 (default) is a one-dimensional compound dataset named `methylation_data`:

| Field | HDF5 type | Meaning |
|-------|-----------|---------|
| `pos` | uint32 | 1-based reference position |
| `mC` | uint16 | Methylated cytosine count |
| `uC` | uint16 | Unmethylated cytosine count |
| `tnc` | uint8 | Trinucleotide code, context, and strand |

When `-z` is greater than 0 and `H5Zfilter_avail(32015)` succeeds, the dataset uses the Zstd filter (id **32015**). Otherwise the writer uses gzip/deflate at `min(level, 9)`, or uncompressed data if deflate cannot be set. Startup logs whether `HDF5_PLUGIN_PATH` can see the plugin built by `make plugin`.

Every file that `flush_buffer` actually writes gets a JSON sidecar (`1-CG.h5` → `1-CG.json`) with the legacy totals plus `methylextractor.context_qc` version `1.0.0`. After the run, the output directory receives `{sample_id}.extraction_manifest.json` and `{sample_id}.timing.json`. `sample_id` is the output directory's final path component, with the suffix after the last `.` removed. Pass the directory without a trailing slash. MethylExtractor records metrics and does not assign pass or fail.

`-R` adds `{name}-{ctx}.patterns.h5` (CG always; CHG/CHH only when `--split` is also set). `--mhap` adds `{name}-CG.mhap.h5`.

Field-level layouts: [Output](docs/output.md). QC JSON: [Extraction QC](docs/extraction_qc_contract.md).

## Performance

`-t` is a region-worker budget inside each chromosome. `--chrom-parallel` runs more than one chromosome at a time, largest first, while `--max-rss-gb` keeps the estimated resident set of in-flight chromosomes under the gate. `{sample_id}.timing.json` splits wall time into BAM scan and HDF5 write. HDF5 and JSON writes take one process-wide lock. Notes: [Performance](docs/performance.md).

## Development checks

Python under `src/cap_coverage.py` and `tests/` is type-checked with Pyrefly. That module is a pandas helper; the binary does not call it.

```bash
poetry install
poetry run pyrefly check
# or: make typecheck
```

HTML docs are published at [goliath-research.github.io/MethylExtractor](https://goliath-research.github.io/MethylExtractor/). Preview locally:

```bash
pip install mkdocs-material
mkdocs serve
```

## License

MIT. Copyright (c) 2015 Devon P. Ryan and the MethylExtractor contributors. Copies must keep the copyright and permission notice in [`LICENSE`](LICENSE). Vendored cJSON remains Copyright (c) 2009-2017 Dave Gamble and cJSON contributors. HTSlib, HDF5, and Zstd keep their own licenses.
