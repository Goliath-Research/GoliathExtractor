# Output

Paths below use `name` from the chromosome map and `ctx` of `CG`, `CHG`, or `CHH`. The sample id is the output directory's final path component with the last `.suffix` removed.

## Files

| Mode | Data file | Sidecar |
|------|-----------|---------|
| `-f hdf5` (default), no `-s` | `{name}.h5` | `{name}.json` |
| `-f txt`, no `-s` | `{name}.txt` | `{name}.json` |
| `-f both`, no `-s` | `{name}.h5` and `{name}.txt` | `{name}.json` (from the `.h5` path) |
| `-s` | `{name}-{ctx}.h5` or `.txt` as above | `{name}-{ctx}.json` |
| `-R` | `{name}-{ctx}.patterns.h5` | none beyond the marginal count file |
| `--mhap` | `{name}-CG.mhap.h5` | none |
| end of run | | `{sample_id}.extraction_manifest.json`, `{sample_id}.timing.json` |

Without `-s`, every kept context is in the single chromosome file and the JSON `metadata.context` is `ALL`. With `-s`, a context that has no reference sites is omitted. A context whose sites all fall below `--min-cov` does not get an H5, TXT, or JSON file; `flush_buffer` returns before creating them. The manifest can still list that context with `num_positions` 0 and the path that was not written.

## HDF5 `methylation_data`

Default and `-f both` create one dataset, `methylation_data`, in the file root. It is a one-dimensional compound type the size of `MethylRecord`, chunked, with an unlimited max dimension. Named members, inserted in `src/output_formats.c`:

| Member | Type | Meaning |
|--------|------|---------|
| `pos` | `H5T_NATIVE_UINT32` | 1-based reference position |
| `mC` | `H5T_NATIVE_UINT16` | Methylated count stored for the site |
| `uC` | `H5T_NATIVE_UINT16` | Unmethylated count stored for the site |
| `tnc` | `H5T_NATIVE_UINT8` | Packed trinucleotide, context, and strand |

Counts are 16-bit. The in-memory site buffer is also `uint16`, so a site cannot record more than 65535 methylated or unmethylated calls.

On the GCC System V builds this repository produces, the `tnc` byte is little-endian bitfields with the first field in the low bits:

| Bits | Field | Values |
|------|-------|--------|
| 0–4 | trinucleotide code | See below |
| 5–6 | context | `1` CG, `2` CHG, `3` CHH |
| 7 | strand | `0` plus (reference C), `1` minus (reference G) |

The trinucleotide code is produced by `encode_trinucleotide_context`. The text writer always prints a 3-mer that starts with `C` (the cytosine on the called strand). The other two characters are the following bases in that strand's 5'→3' direction, reverse-complemented when the reference base is G. Base codes are A=0, C=1, G=2, T=3, N=4. The third base contributes its code; the second base contributes `5 * code`.

Chunk length is `--chunk-size` (default 1,000,000).

### Compression

| `-z` | Filter |
|------|--------|
| `0` | Chunked, no compression filter |
| `1`–`19` and `H5Zfilter_avail(32015) > 0` | Zstd filter id **32015**, one client data value = the level. The filter is mandatory on that dataset |
| `1`–`19` and Zstd is unavailable or `H5Pset_filter` fails | gzip/deflate at `min(level, 9)`. If deflate setup fails, the dataset is left uncompressed |

The same Zstd-then-gzip choice is used for the pattern and haplotype files. Level 6 is the default (`DEFAULT_HDF5_COMPRESSION`).

`make plugin` builds `libH5Zzstd.so`. Point `HDF5_PLUGIN_PATH` at its directory before the run. The startup log line `HDF5 Zstd filter available` or `NOT available` reports what this process actually loaded.

## Text

`-f txt` and `-f both` write one row per site that passed `--min-cov`, with no header:

```text
position	strand	methylated_count	unmethylated_count	context	trinucleotide
```

Example of the shape (numbers depend on the BAM):

```text
161	+	11	9	CG	CGT
310	-	8	12	CG	CGA
```

`strand` is `+` or `-`. `context` is `CG`, `CHG`, or `CHH`. `trinucleotide` is the 3-mer from the low 5 bits of `tnc`.

## Read-level patterns

`write_read_level_patterns_h5` creates group `read_level_patterns` (`READ_LEVEL_GROUP`). Attributes:

| Attribute | Value |
|-----------|-------|
| `context` | `CG`, `CHG`, or `CHH` |
| `tile_size` | `--tile-size` |
| `min_tile_reads` | `1` |
| `pattern_encoding` | `bitmask_msb_first` |
| `schema_version` | `1.0.0` |

Datasets (little-endian, chunked and compressed the same way as the count file when `-z` > 0):

| Dataset | Type | Shape | Meaning |
|---------|------|-------|---------|
| `tile_start_pos` | uint32 | `(n_tiles,)` | 1-based position of the tile's first site |
| `tile_n_reads` | uint32 | `(n_tiles,)` | Reads that called every site in the tile |
| `tile_cpg_positions` | uint32 | `(n_tiles, k)` | 1-based site positions, `k = tile_size` |
| `pattern_tile_id` | uint32 | `(nnz,)` | Tile row for this pattern |
| `pattern_id` | uint16 | `(nnz,)` | Pattern bits |
| `pattern_count` | uint32 | `(nnz,)` | Reads with that pattern |

`pattern_encoding` `bitmask_msb_first` means bit `(k - 1 - j)` is set when site `j` in the tile (left to right) is methylated. Zero-count patterns are omitted. Tiles with no complete read are omitted. A file is skipped entirely when no tile qualifies. The marginal `{name}-{ctx}.h5` count file is unchanged by `-R`.

## CpG haplotypes (`--mhap`)

`write_mhap_h5` creates group `mhap`. Attributes: `schema_version` `1.0.0`, `context` `CG`, `chrom` (the map `name`).

| Dataset | Type | Length | Meaning |
|---------|------|--------|---------|
| `read_start` | int32 | n_reads | BAM `POS` (0-based) of the alignment |
| `read_strand` | int8 | n_reads | `getRealStrand` code: 1 OT, 2 OB, 3 CTOT, 4 CTOB |
| `n_cpg` | int32 | n_reads | CpG calls stored for that read |
| `cpg_pos` | int32 | n_obs | 0-based position of the cytosine C in the CpG |
| `meth` | uint8 | n_obs | `1` methylated, `0` unmethylated |

`cpg_pos` and `meth` are concatenated in read order. At most 256 CpGs are stored per alignment (`MHAP_MAX_CPG_PER_READ`). Positions here are 0-based; `methylation_data.pos` and the pattern positions are 1-based. The file is written only when `n_reads > 0`.

## JSON sidecars

Context, manifest, and timing schemas are specified in [Extraction QC](extraction_qc_contract.md).
