#!/bin/bash
# Package GoliathExtractor binary + HDF5 plugin for production release.
# Run from GoliathExtractor repo root after 'make', or pass --build-dir.
#
# Vendored from Goliath-Research/GoliathOmics packaging scripts so
# .github/workflows/release.yml does not check out another repository.

set -euo pipefail

CLI_NAME="goliath-extractor"
LEGACY_CLI_NAME="MethylExtractor"

usage() {
  cat <<EOF
Usage: scripts/package_goliath_extractor.sh [options]

Options:
  --build-dir PATH     GoliathExtractor build root (default: . or GOLIATH_EXTRACTOR_ROOT)
  --arch KEY           arm64|x64|aarch64|amd64 (default: detect)
  --version VER        Version string for tarball name (default: git describe or manual)
  --output PATH        Output tarball path
  --bundle-libs        Copy all non-glibc shared libs into lib/ and set
                       RPATHs (scripts/bundle_libs.sh; needs ldd + patchelf).
                       Used by the release workflow.
  -h, --help           Show this help

Output layout inside tarball:
  bin/${CLI_NAME}
  bin/${LEGACY_CLI_NAME}  (symlink to ${CLI_NAME})
  lib/hdf5_zstd_plugin/libH5Zzstd.so
  lib/*.so*            (with --bundle-libs)
  VERSION.txt
  env.sh

Used by .github/workflows/release.yml
EOF
}

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

normalize_release_version() {
  local ver="${1:?version required}"
  ver="${ver#v}"
  echo "$ver"
}

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

BUILD_DIR="${GOLIATH_EXTRACTOR_ROOT:-${METHYL_EXTRACTOR_ROOT:-.}}"
ARCH=""
VERSION=""
OUTPUT=""
VERSION_EXPLICIT=0
BUNDLE_LIBS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; VERSION_EXPLICIT=1; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --bundle-libs) BUNDLE_LIBS=1; shift ;;
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

normalize_build_subdir() {
  case "$1" in
    aarch64) echo "arm64" ;;
    amd64) echo "x64" ;;
    *) die "Unknown arch: $1" ;;
  esac
}

ARCH_KEY="$(normalize_arch "${ARCH:-$(platform_arch_key "$(detect_uname_arch)")}")"
BUILD_SUBDIR="$(normalize_build_subdir "$ARCH_KEY")"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

BIN="$BUILD_DIR/build/dynamic/$BUILD_SUBDIR/$CLI_NAME"
PLUGIN_SRC="$BUILD_DIR/build/dynamic/$BUILD_SUBDIR/hdf5_zstd_plugin"
[[ -x "$BIN" ]] || die "GoliathExtractor binary not found: $BIN (run make first)"

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

OUTPUT="${OUTPUT:-goliath-extractor-linux-${ARCH_KEY}.tar.gz}"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/bin" "$STAGING/lib"
cp -a "$BIN" "$STAGING/bin/$CLI_NAME"
ln -sf "$CLI_NAME" "$STAGING/bin/$LEGACY_CLI_NAME"
if [[ -f "$PLUGIN_SRC/libH5Zzstd.so" ]]; then
  mkdir -p "$STAGING/lib/hdf5_zstd_plugin"
  cp -a "$PLUGIN_SRC/libH5Zzstd.so" "$STAGING/lib/hdf5_zstd_plugin/"
fi
echo "$VERSION" >"$STAGING/VERSION.txt"

if [[ "$BUNDLE_LIBS" -eq 1 ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/bundle_libs.sh" "$STAGING"
fi

cat >"$STAGING/env.sh" <<ENVEOF
#!/bin/sh
# Source after extract: . /path/to/install-root/env.sh
_src="\${BASH_SOURCE:-\$0}"
case "\$_src" in */env.sh|env.sh) ;; *) _src=./env.sh ;; esac
_ROOT="\$(cd "\$(dirname "\$_src")" && pwd)"
unset _src
export GOLIATH_EXTRACTOR_BIN="\$_ROOT/bin/${CLI_NAME}"
export METHYL_EXTRACTOR_BIN="\$_ROOT/bin/${LEGACY_CLI_NAME}"
export HDF5_PLUGIN_PATH="\$_ROOT/lib/hdf5_zstd_plugin"
export LD_LIBRARY_PATH="\$_ROOT/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PATH="\$_ROOT/bin:\$PATH"
ENVEOF
chmod +x "$STAGING/env.sh"

tar -czf "$OUTPUT" -C "$STAGING" bin lib VERSION.txt env.sh
SHA="$(sha256sum "$OUTPUT" | awk '{print $1}')"
info "Wrote $OUTPUT (sha256=$SHA)"
info "Add to manifest.json artifacts.$ARCH_KEY.sha256"
