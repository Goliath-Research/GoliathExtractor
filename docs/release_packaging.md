# Release packages

`.github/workflows/release.yml` builds and publishes Linux tarballs for tag `v*` (for example `v2026.10.1`). A manual run can set `releaseVersion` (SemVer, no leading zeros: `2026.10.1`, not `2026.010.1`) when the ref is not a tag.

Asset names:

- `goliath-extractor-linux-amd64.tar.gz` and `.tar.gz.sha256`
- `goliath-extractor-linux-aarch64.tar.gz` and `.tar.gz.sha256`

## Layout

```text
bin/goliath-extractor                  RPATH $ORIGIN/../lib
lib/*.so*                            bundled shared libraries (real file and soname symlink), RPATH $ORIGIN
lib/hdf5_zstd_plugin/libH5Zzstd.so   RPATH $ORIGIN/..
VERSION.txt
env.sh                               METHYL_EXTRACTOR_BIN, HDF5_PLUGIN_PATH, PATH, LD_LIBRARY_PATH
```

## Why the binary stays dynamic

The package job builds on `ubuntu-22.04` (amd64) and `ubuntu-22.04-arm` (aarch64), so the glibc baseline is 2.35. `scripts/package_goliath_extractor.sh --bundle-libs` calls `scripts/bundle_libs.sh`, which walks `ldd` for the binary and the HDF5 plugin, copies every library outside the glibc family and the dynamic loader into `lib/`, and sets DT_RPATH with `patchelf --force-rpath`. The script fails if a dependency is still unresolved or still resolves from the host.

The `smoke` job unpacks each tarball in `ubuntu:22.04`, `ubuntu:24.04`, `ubuntu:latest`, and `debian:stable-slim` with no extra packages, and runs `scripts/smoke_test_tarball.sh`. `ldd` must not report `not found`. `goliath-extractor --help` must succeed with and without sourcing `env.sh`. Publish waits for smoke.

## Rebuild locally

```bash
docker run --rm -v "$PWD:/src" -w /src ubuntu:22.04 bash -c '
  apt-get update && apt-get install -y build-essential cmake git patchelf libhdf5-dev libhts-dev \
    zlib1g-dev libbz2-dev liblzma-dev libcurl4-gnutls-dev libssl-dev libzstd-dev &&
  make && make plugin &&
  bash scripts/package_goliath_extractor.sh --version 2026.10.1 --bundle-libs \
    --output goliath-extractor-linux-amd64.tar.gz'
docker run --rm -v "$PWD:/src" ubuntu:24.04 sh /src/scripts/smoke_test_tarball.sh /src/goliath-extractor-linux-amd64.tar.gz
```

Fixture tests, without a full release build: `tests/test_package_goliath_extractor.sh` and `tests/test_bundle_libs.sh` (the bundle fixture needs `gcc` and `patchelf`). The pull-request workflow runs both.

## Version file

`VERSION.txt` inside the tarball is the `--version` string passed by the workflow (`2026.10.1` for tag `v2026.10.1`). The C binary does not print that version from a `--version` flag; `--help` is the smoke check.
