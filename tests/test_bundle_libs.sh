#!/bin/bash
# Fixture test for scripts/bundle_libs.sh: builds a fake MethylExtractor
# that links a private shared library (libfoo.so.1 -> libfoo.so.1.2.3) plus a
# fake HDF5 plugin, bundles it, then runs it with the build dir gone.
# Needs gcc + patchelf + ldd; skips (exit 0) when they are missing.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/bundle_libs.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
bash -n "$SCRIPT"
for t in gcc patchelf ldd; do
  command -v "$t" >/dev/null || { echo "SKIP: $t not installed"; exit 0; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/build" "$TMP/tree/bin" "$TMP/tree/lib/hdf5_zstd_plugin"

cat >"$TMP/build/foo.c" <<'C'
int foo(void) { return 42; }
C
cat >"$TMP/build/main.c" <<'C'
#include <stdio.h>
#include <math.h>
int foo(void);
int main(void) { printf("foo=%d %.0f\n", foo(), sqrt(16.0)); return 0; }
C
cat >"$TMP/build/plugin.c" <<'C'
int foo(void);
int plugin(void) { return foo(); }
C
gcc -shared -fPIC -Wl,-soname,libfoo.so.1 -o "$TMP/build/libfoo.so.1.2.3" "$TMP/build/foo.c"
ln -s libfoo.so.1.2.3 "$TMP/build/libfoo.so.1"
ln -s libfoo.so.1 "$TMP/build/libfoo.so"
gcc -o "$TMP/tree/bin/MethylExtractor" "$TMP/build/main.c" -L"$TMP/build" -lfoo -lm
gcc -shared -fPIC -o "$TMP/tree/lib/hdf5_zstd_plugin/libH5Zzstd.so" "$TMP/build/plugin.c" -L"$TMP/build" -lfoo

# Unbundled: the binary cannot run without the build dir on the path.
if "$TMP/tree/bin/MethylExtractor" >/dev/null 2>&1; then fail "fixture should not run unbundled"; fi

LD_LIBRARY_PATH="$TMP/build" bash "$SCRIPT" "$TMP/tree" 2>"$TMP/log" || { cat "$TMP/log"; fail "bundle failed"; }
rm -rf "$TMP/build"

[[ -f "$TMP/tree/lib/libfoo.so.1.2.3" && ! -L "$TMP/tree/lib/libfoo.so.1.2.3" ]] || fail "real file not copied"
[[ "$(readlink "$TMP/tree/lib/libfoo.so.1")" == "libfoo.so.1.2.3" ]] || fail "soname symlink missing"
for x in libc.so libm.so ld-linux; do
  for f in "$TMP/tree/lib/$x"*; do [[ -e "$f" ]] && fail "$x must not be bundled"; done
done
# shellcheck disable=SC2016
[[ "$(patchelf --print-rpath "$TMP/tree/bin/MethylExtractor")" == '$ORIGIN/../lib' ]] || fail "binary rpath"
# shellcheck disable=SC2016
[[ "$(patchelf --print-rpath "$TMP/tree/lib/libfoo.so.1.2.3")" == '$ORIGIN' ]] || fail "lib rpath"
# shellcheck disable=SC2016
[[ "$(patchelf --print-rpath "$TMP/tree/lib/hdf5_zstd_plugin/libH5Zzstd.so")" == '$ORIGIN/..' ]] || fail "plugin rpath"
if env -u LD_LIBRARY_PATH ldd "$TMP/tree/lib/hdf5_zstd_plugin/libH5Zzstd.so" | grep -q 'not found'; then fail "plugin unresolved"; fi

# Relocate the tree: RPATH is $ORIGIN-relative.
mv "$TMP/tree" "$TMP/moved"
[[ "$(env -u LD_LIBRARY_PATH "$TMP/moved/bin/MethylExtractor")" == "foo=42 4" ]] || fail "bundled binary did not run"

# Idempotent.
before="$(cd "$TMP/moved" && find . | sort)"
bash "$SCRIPT" "$TMP/moved" 2>/dev/null || fail "second run failed"
[[ "$(cd "$TMP/moved" && find . | sort)" == "$before" ]] || fail "second run changed the tree"

echo "bundle_libs.sh OK"
