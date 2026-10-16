#!/bin/sh
# shellcheck disable=SC1091  # sourced files exist only at runtime
# Smoke-test a release tarball on a bare distro image (no extra packages).
# Usage: scripts/smoke_test_tarball.sh methyl-extractor-linux-<arch>.tar.gz
# Fails if any library is "not found" or MethylExtractor --help fails.
# POSIX sh so it runs in minimal images; needs only tar, gzip and ldd.
set -eu
TARBALL="${1:?usage: $0 TARBALL}"
DEST="$(mktemp -d)"
tar -xzf "$TARBALL" -C "$DEST"
. /etc/os-release 2>/dev/null || true
echo "== ${PRETTY_NAME:-unknown distro} ($(uname -m)) =="
rc=0
for f in "$DEST/bin/MethylExtractor" "$DEST"/lib/*.so* "$DEST"/lib/hdf5_zstd_plugin/*.so; do
  [ -f "$f" ] || continue
  out="$(env -u LD_LIBRARY_PATH ldd "$f" 2>&1)" || { echo "ldd failed: $f"; echo "$out"; rc=1; continue; }
  if echo "$out" | grep -q 'not found'; then
    echo "UNRESOLVED in $f:"; echo "$out" | grep 'not found'; rc=1
  fi
done
env -u LD_LIBRARY_PATH ldd "$DEST/bin/MethylExtractor"
[ "$rc" -eq 0 ] || exit 1
# Without env.sh: RPATH alone must be enough.
env -u LD_LIBRARY_PATH "$DEST/bin/MethylExtractor" --help >/dev/null
# With env.sh (documented usage).
( cd "$DEST" && . ./env.sh && MethylExtractor --help >/dev/null )
if command -v bash >/dev/null 2>&1; then
  bash -c '. "$1/env.sh" && MethylExtractor --help >/dev/null' _ "$DEST"
fi
echo "OK: MethylExtractor --help"
rm -rf "$DEST"
