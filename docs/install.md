# Install

MethylExtractor is a C program. The supported build is the dynamic binary produced by `make` on Linux x86_64 or aarch64. Release **2026.10.1** is tag `v2026.10.1`.

## Build from source

The Makefile targets Debian and Ubuntu package names.

```bash
git clone https://github.com/Goliath-Research/MethylExtractor.git
cd MethylExtractor
make deps
make
```

`make deps` runs `sudo apt-get install` for:

- `build-essential`, `cmake`, `git`
- `libhdf5-dev`, `libhts-dev`, `hdf5-tools`
- `zlib1g-dev`, `libbz2-dev`, `liblzma-dev`
- `libcurl4-gnutls-dev`, `libssl-dev`
- `libzstd-dev`, `zstd`

`make` (the same as `make dynamic`) compiles with `gcc -O2` and links `libhts`, `libhdf5_serial`, `libhdf5_serial_hl`, `libpthread`, and `libm`. It does not pass `-fopenmp`; threads are pthreads. The binary is `build/dynamic/x64/MethylExtractor` or `build/dynamic/arm64/MethylExtractor`.

`make debug` builds `build/debug/<arch>/MethylExtractor` with `-g -O0 -DDEBUG`. `make static` attempts a fully static link. The Makefile notes that a static link needs static HTSlib and HDF5 archives that a normal distro install does not ship, so the dynamic binary is the one CI builds and packages.

`make clean` deletes `build/`.

## Zstd HDF5 plugin

Filter id **32015** is the HDF5 Zstandard filter. It is a plugin, not part of the stock HDF5 library this program links. Without it, HDF5 output still succeeds and uses gzip.

```bash
make plugin
```

That runs `scripts/install_hdf5_zstd_plugin.sh` and writes `build/dynamic/<arch>/hdf5_zstd_plugin/libH5Zzstd.so`. The target prints an `HDF5_PLUGIN_PATH` export for in-tree use. MethylExtractor logs at startup whether `H5Zfilter_avail(32015)` succeeds.

## System install

```bash
make install
```

`make install` builds the dynamic binary and the plugin, then checks `file` output against the host (`x86-64` or `aarch64`). On a mismatch it exits before copying. On a match it:

- copies the binary to `/usr/local/bin/MethylExtractor`
- copies `libH5Zzstd.so` to `/usr/local/hdf5/lib/plugin/`
- appends `export HDF5_PLUGIN_PATH=/usr/local/hdf5/lib/plugin` to `~/.bashrc` when that file does not already mention `HDF5_PLUGIN_PATH`

Open a new shell, or export `HDF5_PLUGIN_PATH` yourself, before expecting Zstd-compressed files.

## Release tarball

Tags `v*` build `methyl-extractor-linux-amd64.tar.gz` and `methyl-extractor-linux-aarch64.tar.gz` on Ubuntu 22.04. See [Release packages](release_packaging.md).

```bash
mkdir -p "$HOME/methyl-extractor"
tar -xzf methyl-extractor-linux-amd64.tar.gz -C "$HOME/methyl-extractor"
. "$HOME/methyl-extractor/env.sh"
MethylExtractor --help
```

`env.sh` puts `bin` on `PATH`, points `HDF5_PLUGIN_PATH` at the bundled plugin, and sets `LD_LIBRARY_PATH` as a fallback. The binary's RPATH already looks in `lib/`.

## Python checks

`pyproject.toml` is a Poetry project with `package-mode = false`. It exists so Pyrefly can type-check `src/cap_coverage.py` and `tests/`. The C binary does not import those modules. `src/cap_coverage.py` rescales a pandas DataFrame; `--cap-cov` in the binary is the C path in `src/output_formats.c`.

```bash
poetry install
poetry run pyrefly check
```

`make typecheck` runs the same command.

## Documentation site

The Markdown in `docs/` is a [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) site, published at [goliath-research.github.io/MethylExtractor](https://goliath-research.github.io/MethylExtractor/). Pull requests run `mkdocs build --strict` and do not deploy. Pushes to `main` publish the site.

```bash
pip install mkdocs-material
mkdocs build --strict
mkdocs serve
```

The HTML file `MethylExtractor_Documentation.html` at the repository root is an older snapshot. Use `README.md` and `docs/` for release 2026.10.1.
