#!/bin/bash
# Fixture test for scripts/package_methyl_extractor.sh. No compiler required.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/package_methyl_extractor.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"
bash -n "$SCRIPT"

# --help
bash "$SCRIPT" --help >/dev/null

make_tree() {
  local dest="$1"
  local subdir="$2"
  mkdir -p "$dest/build/dynamic/$subdir/hdf5_zstd_plugin"
  printf 'bin-%s\n' "$subdir" >"$dest/build/dynamic/$subdir/MethylExtractor"
  chmod +x "$dest/build/dynamic/$subdir/MethylExtractor"
  printf 'plugin-%s\n' "$subdir" >"$dest/build/dynamic/$subdir/hdf5_zstd_plugin/libH5Zzstd.so"
  # Residual tree left by install_hdf5_zstd_plugin.sh after make plugin.
  mkdir -p "$dest/build/dynamic/$subdir/hdf5_zstd_plugin/HDF5Plugin-Zstandard/build"
  mkdir -p "$dest/build/dynamic/$subdir/hdf5_zstd_plugin/HDF5Plugin-Zstandard/.git"
  printf 'source\n' >"$dest/build/dynamic/$subdir/hdf5_zstd_plugin/HDF5Plugin-Zstandard/CMakeLists.txt"
  printf 'so\n' >"$dest/build/dynamic/$subdir/hdf5_zstd_plugin/HDF5Plugin-Zstandard/build/libH5Zzstd.so"
}

assert_tarball() {
  local tarball="$1"
  local version="$2"
  local bin_file="$3"
  local plugin_file="$4"
  local extract="$TMP/extract-$$"
  rm -rf "$extract"
  mkdir -p "$extract"
  [[ -f "$tarball" ]] || fail "missing tarball $tarball"
  tar -tzf "$tarball" | grep -qx 'bin/MethylExtractor' || fail "missing binary in $tarball"
  tar -tzf "$tarball" | grep -qx 'lib/hdf5_zstd_plugin/libH5Zzstd.so' || fail "missing plugin in $tarball"
  if tar -tzf "$tarball" | grep -q 'HDF5Plugin-Zstandard\|\.git\|CMake'; then
    fail "tarball includes plugin source tree"
  fi
  tar -tzf "$tarball" | grep -qx 'VERSION.txt' || fail "missing VERSION.txt in $tarball"
  tar -tzf "$tarball" | grep -qx 'env.sh' || fail "missing env.sh in $tarball"
  tar -xzf "$tarball" -C "$extract"
  [[ "$(cat "$extract/VERSION.txt")" == "$version" ]] || fail "VERSION.txt != $version"
  cmp -s "$extract/bin/MethylExtractor" "$bin_file" || fail "binary bytes mismatch"
  cmp -s "$extract/lib/hdf5_zstd_plugin/libH5Zzstd.so" "$plugin_file" || fail "plugin bytes mismatch"
  grep -q 'METHYL_EXTRACTOR_BIN=' "$extract/env.sh" || fail "env.sh missing METHYL_EXTRACTOR_BIN"
  grep -q 'HDF5_PLUGIN_PATH=' "$extract/env.sh" || fail "env.sh missing HDF5_PLUGIN_PATH"
  grep -q 'LD_LIBRARY_PATH=' "$extract/env.sh" || fail "env.sh missing LD_LIBRARY_PATH fallback"
  [[ -x "$extract/bin/MethylExtractor" ]] || fail "extracted binary is not executable"
}

make_tree "$TMP/amd" x64
OUT_AMD="$TMP/methyl-extractor-linux-amd64.tar.gz"
bash "$SCRIPT" \
  --build-dir "$TMP/amd" \
  --arch amd64 \
  --version 2026.6.1 \
  --output "$OUT_AMD" >"$TMP/amd.log"
grep -q 'sha256=' "$TMP/amd.log" || fail "script did not print sha256"
assert_tarball "$OUT_AMD" "2026.6.1" \
  "$TMP/amd/build/dynamic/x64/MethylExtractor" \
  "$TMP/amd/build/dynamic/x64/hdf5_zstd_plugin/libH5Zzstd.so"
sha256sum "$OUT_AMD" | tee "$OUT_AMD.sha256" >/dev/null
grep -q "$(sha256sum "$OUT_AMD" | awk '{print $1}')" "$OUT_AMD.sha256" || fail "sha256 sidecar mismatch"
[[ "$(basename "$OUT_AMD")" == "methyl-extractor-linux-amd64.tar.gz" ]] || fail "amd64 name"

make_tree "$TMP/arm" arm64
OUT_ARM="$TMP/methyl-extractor-linux-aarch64.tar.gz"
bash "$SCRIPT" \
  --build-dir "$TMP/arm" \
  --arch aarch64 \
  --version 2026.6.1-test \
  --output "$OUT_ARM" >/dev/null
assert_tarball "$OUT_ARM" "2026.6.1-test" \
  "$TMP/arm/build/dynamic/arm64/MethylExtractor" \
  "$TMP/arm/build/dynamic/arm64/hdf5_zstd_plugin/libH5Zzstd.so"
sha256sum "$OUT_ARM" | tee "$OUT_ARM.sha256" >/dev/null
[[ -s "$OUT_ARM.sha256" ]] || fail "empty aarch64 sha256 sidecar"

# x64 alias and arm64 alias map to the same layout keys.
bash "$SCRIPT" --build-dir "$TMP/amd" --arch x64 --version 2026.6.1 --output "$TMP/from-x64.tar.gz" >/dev/null
assert_tarball "$TMP/from-x64.tar.gz" "2026.6.1" \
  "$TMP/amd/build/dynamic/x64/MethylExtractor" \
  "$TMP/amd/build/dynamic/x64/hdf5_zstd_plugin/libH5Zzstd.so"
bash "$SCRIPT" --build-dir "$TMP/arm" --arch arm64 --version 2026.6.1 --output "$TMP/from-arm64.tar.gz" >/dev/null
assert_tarball "$TMP/from-arm64.tar.gz" "2026.6.1" \
  "$TMP/arm/build/dynamic/arm64/MethylExtractor" \
  "$TMP/arm/build/dynamic/arm64/hdf5_zstd_plugin/libH5Zzstd.so"

# Plugin directory is optional.
rm -rf "$TMP/amd/build/dynamic/x64/hdf5_zstd_plugin"
bash "$SCRIPT" --build-dir "$TMP/amd" --arch amd64 --version 2026.6.1 --output "$TMP/noplugin.tar.gz" >/dev/null
if tar -tzf "$TMP/noplugin.tar.gz" | grep -q 'hdf5_zstd_plugin'; then
  fail "plugin should be omitted"
fi
tar -tzf "$TMP/noplugin.tar.gz" | grep -qx 'bin/MethylExtractor' || fail "binary missing without plugin"

# Explicit versions must be SemVer without leading zeros.
if bash "$SCRIPT" --build-dir "$TMP/amd" --arch amd64 --version 2026.06.1 --output "$TMP/bad.tar.gz" >/dev/null 2>"$TMP/bad.err"; then
  fail "leading-zero version should fail"
fi
grep -q 'Invalid --version' "$TMP/bad.err" || fail "expected invalid version error"

if bash "$SCRIPT" --build-dir "$TMP/amd" --arch amd64 --version v2026.6.1 --output "$TMP/badv.tar.gz" >/dev/null 2>"$TMP/badv.err"; then
  fail "leading v should fail when --version is explicit"
fi

if bash "$SCRIPT" --build-dir "$TMP/amd" --arch ppc64 --output "$TMP/badarch.tar.gz" >/dev/null 2>"$TMP/badarch.err"; then
  fail "unknown arch should fail"
fi
grep -q 'Unknown arch' "$TMP/badarch.err" || fail "expected unknown arch error"

mkdir -p "$TMP/empty"
if bash "$SCRIPT" --build-dir "$TMP/empty" --arch amd64 --version 2026.6.1 --output "$TMP/missing.tar.gz" >/dev/null 2>"$TMP/missing.err"; then
  fail "missing binary should fail"
fi
grep -q 'binary not found' "$TMP/missing.err" || fail "expected missing binary error"

# Omitted version outside a git work tree becomes "manual" and is not SemVer-checked.
make_tree "$TMP/manual" x64
bash "$SCRIPT" --build-dir "$TMP/manual" --arch amd64 --output "$TMP/manual.tar.gz" >/dev/null
[[ "$(tar -xOzf "$TMP/manual.tar.gz" VERSION.txt)" == "manual" ]] || fail "default version should be manual"

echo "package_methyl_extractor.sh OK"
