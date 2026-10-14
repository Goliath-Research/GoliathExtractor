#!/bin/bash
# Package MethylExtractor binary + HDF5 plugin for production release.
# Run from MethylExtractor repo root after 'make', or pass --build-dir.
#
# Vendored from Goliath-Research/GoliathOmics scripts/package_methyl_extractor.sh
# so .github/workflows/release.yml does not check out another repository.
# Arch and SemVer helpers are the subset of that repo's scripts/detect_platform.sh
# this script calls.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/package_methyl_extractor.sh [options]

Options:
  --build-dir PATH     MethylExtractor build root (default: . or METHYL_EXTRACTOR_ROOT)
  --arch KEY           arm64|x64|aarch64|amd64 (default: detect)
  --version VER        Version string for tarball name (default: git describe or manual)
  --output PATH        Output tarball path
  -h, --help           Show this help

Output layout inside tarball:
  bin/MethylExtractor
  lib/hdf5_zstd_plugin/
  VERSION.txt

Used by .github/workflows/release.yml
EOF
}

# Map uname -m to matrix key (aarch64 | amd64).
detect_uname_arch() {
  uname -m
}

platform_arch_key() {
  local uname_arch="${1:-$(detect_uname_arch)}"
  case "$uname_arch" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64) echo "amd64" ;;
    *) echo "unknown" ;;
  esac
}

# Strip optional leading "v" from git tags (v2026.6.1 -> 2026.6.1).
normalize_release_version() {
  local ver="${1:?version required}"
  ver="${ver#v}"
  echo "$ver"
}

# SemVer 2.0 without build metadata (+suffix). No leading zeros.
validate_release_version() {
  local ver="${1:?version required}"
  [[ "$ver" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-z0-9]+([-.][a-z0-9]+)*)?$ ]]
}

require_release_version() {
  local ver="$1"
  local ctx="${2:-release version}"
  if ! validate_release_version "$ver"; then
    echo "[ERROR] Invalid $ctx: '$ver'" >&2
    echo "[ERROR] Use SemVer 2.0 without leading zeros (e.g. 2026.6.1, not 2026.06.1)." >&2
    echo "[ERROR] Required for Azure Universal Packages and manifest.json." >&2
    return 1
  fi
}

BUILD_DIR="${METHYL_EXTRACTOR_ROOT:-.}"
ARCH=""
VERSION=""
OUTPUT=""
VERSION_EXPLICIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; VERSION_EXPLICIT=1; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

normalize_arch() {
  case "$1" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64|x64) echo "amd64" ;;
    *) die "Unknown arch: $1" ;;
  esac
}

normalize_me_subdir() {
  case "$1" in
    aarch64) echo "arm64" ;;
    amd64) echo "x64" ;;
    *) die "Unknown arch: $1" ;;
  esac
}

ARCH_KEY="$(normalize_arch "${ARCH:-$(platform_arch_key "$(detect_uname_arch)")}")"
ME_SUBDIR="$(normalize_me_subdir "$ARCH_KEY")"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

BIN="$BUILD_DIR/build/dynamic/$ME_SUBDIR/MethylExtractor"
PLUGIN_SRC="$BUILD_DIR/build/dynamic/$ME_SUBDIR/hdf5_zstd_plugin"
[[ -x "$BIN" ]] || die "MethylExtractor binary not found: $BIN (run make first)"

if [[ -z "$VERSION" ]]; then
  if git -C "$BUILD_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VERSION="$(git -C "$BUILD_DIR" describe --tags --always 2>/dev/null || echo manual)"
    VERSION="$(normalize_release_version "$VERSION")"
  else
    VERSION="manual"
  fi
fi

if [[ "$VERSION_EXPLICIT" -eq 1 ]]; then
  require_release_version "$VERSION" "--version" || exit 1
fi

OUTPUT="${OUTPUT:-methyl-extractor-linux-${ARCH_KEY}.tar.gz}"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/bin" "$STAGING/lib"
cp -a "$BIN" "$STAGING/bin/MethylExtractor"
# make plugin leaves the HDF5Plugin-Zstandard clone (source, .git, CMake)
# beside libH5Zzstd.so. Ship only the shared library, matching make install.
if [[ -f "$PLUGIN_SRC/libH5Zzstd.so" ]]; then
  mkdir -p "$STAGING/lib/hdf5_zstd_plugin"
  cp -a "$PLUGIN_SRC/libH5Zzstd.so" "$STAGING/lib/hdf5_zstd_plugin/"
fi
echo "$VERSION" >"$STAGING/VERSION.txt"

cat >"$STAGING/env.sh" <<'ENVEOF'
#!/bin/sh
# Source after extract: source "$(dirname "$0")/env.sh"  (from install root)
_ROOT="$(cd "$(dirname "$0")" && pwd)"
export METHYL_EXTRACTOR_BIN="$_ROOT/bin/MethylExtractor"
export HDF5_PLUGIN_PATH="$_ROOT/lib/hdf5_zstd_plugin"
export PATH="$_ROOT/bin:$PATH"
ENVEOF
chmod +x "$STAGING/env.sh"

tar -czf "$OUTPUT" -C "$STAGING" bin lib VERSION.txt env.sh
SHA="$(sha256sum "$OUTPUT" | awk '{print $1}')"
info "Wrote $OUTPUT (sha256=$SHA)"
info "Add to manifest.json artifacts.$ARCH_KEY.sha256"
