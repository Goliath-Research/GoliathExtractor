# Release tarball packaging

`.github/workflows/release.yml` publishes `methyl-extractor-linux-amd64.tar.gz`
and `methyl-extractor-linux-aarch64.tar.gz` (plus `<name>.tar.gz.sha256`) to the
GitHub Release for tag `v<version>`. GoliathOmics
(`scripts/download_methyl_extractor_artifacts.sh`) downloads them by those names.

## Layout

```
bin/MethylExtractor                  RPATH $ORIGIN/../lib
lib/*.so*                            bundled shared libs (real file + soname symlink), RPATH $ORIGIN
lib/hdf5_zstd_plugin/libH5Zzstd.so   RPATH $ORIGIN/..
VERSION.txt
env.sh                               METHYL_EXTRACTOR_BIN, HDF5_PLUGIN_PATH, PATH, LD_LIBRARY_PATH (fallback)
```

## Self-contained, dynamically linked

The binary stays dynamically linked (static builds broke on newer platforms).
Instead:

1. Build on Ubuntu 22.04 (`ubuntu-22.04` / `ubuntu-22.04-arm` runners), so the
   glibc baseline is 2.35 and the tarball runs on 22.04 and anything newer.
2. `scripts/package_methyl_extractor.sh --bundle-libs` calls
   `scripts/bundle_libs.sh`, which walks `ldd` for the binary and the HDF5
   plugin and copies every library except the glibc family and the loader
   (libc, libm, libdl, libpthread, librt, libresolv, ld-linux, ...) into `lib/`,
   then sets RPATHs with `patchelf --force-rpath` (DT_RPATH, so it also covers
   transitive deps). It fails if anything is unresolved or still resolves from
   the host.
3. The `smoke` job extracts each tarball in bare `ubuntu:22.04`,
   `ubuntu:24.04`, `ubuntu:latest` and `debian:stable-slim` (no extra packages)
   and runs `scripts/smoke_test_tarball.sh`: `ldd` must report no
   `not found`, and `MethylExtractor --help` must succeed with and without
   `env.sh`. Publishing waits for it.

Run locally (Docker):

```bash
docker run --rm -v "$PWD:/src" -w /src ubuntu:22.04 bash -c '
  apt-get update && apt-get install -y build-essential cmake git patchelf libhdf5-dev libhts-dev \
    zlib1g-dev libbz2-dev liblzma-dev libcurl4-gnutls-dev libssl-dev libzstd-dev &&
  make && make plugin &&
  bash scripts/package_methyl_extractor.sh --version 0.0.0-local --bundle-libs \
    --output methyl-extractor-linux-amd64.tar.gz'
docker run --rm -v "$PWD:/src" ubuntu:24.04 sh /src/scripts/smoke_test_tarball.sh /src/methyl-extractor-linux-amd64.tar.gz
```

Fixture tests: `tests/test_bundle_libs.sh` (needs gcc + patchelf) and
`tests/test_package_methyl_extractor.sh`.

GoliathOmics `scripts/bundle_methyl_extractor_libs.sh` detects an
already-bundled tarball (`lib/libhts.so.3`, `lib/libdeflate.so.0`,
`lib/libhtscodecs.so.2` present and `LD_LIBRARY_PATH` in `env.sh`) and leaves
it untouched.
