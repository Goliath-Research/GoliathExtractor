#!/bin/bash
# Bundle every non-glibc shared library needed by a MethylExtractor install
# tree into <root>/lib and point RPATHs at it, so the tarball runs on hosts
# without htslib/HDF5/curl/etc. installed. Dynamic linking is kept on purpose
# (static builds broke on newer platforms); only the glibc family and the
# dynamic loader are taken from the host, so build on an old distro
# (ubuntu:22.04) to keep the glibc baseline low.
#
# Usage: scripts/bundle_libs.sh [--no-patchelf] ROOT
#   ROOT/bin/MethylExtractor                    -> RPATH $ORIGIN/../lib
#   ROOT/lib/*.so*  (bundled)                   -> RPATH $ORIGIN
#   ROOT/lib/hdf5_zstd_plugin/*.so (if present) -> RPATH $ORIGIN/..
#
# Must run on the build host (same arch) because it uses ldd.
# Idempotent: re-running on a bundled tree changes nothing material.
# Env: BUNDLE_EXCLUDE_REGEX overrides the host-provided soname regex.

set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }

PATCHELF=1
if [[ "${1:-}" == "--no-patchelf" ]]; then PATCHELF=0; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,17p' "$0"; exit 0; fi
ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT" ]] || die "usage: $0 [--no-patchelf] ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
BIN="$ROOT/bin/MethylExtractor"
LIB="$ROOT/lib"
PLUGIN_DIR="$LIB/hdf5_zstd_plugin"
[[ -f "$BIN" ]] || die "missing $BIN"
command -v ldd >/dev/null || die "ldd is required"
if [[ "$PATCHELF" -eq 1 ]]; then
  command -v patchelf >/dev/null || die "patchelf is required (apt-get install patchelf)"
fi
mkdir -p "$LIB"

# glibc family + loader: always provided by the host and must match it.
EXCLUDE_REGEX="${BUNDLE_EXCLUDE_REGEX:-^(linux-vdso|linux-gate|ld-linux[^ ]*|ld64|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libnsl|libBrokenLocale|libmvec|libnss_[a-z]+|libcrypt|libthread_db)\.so(\.|$)}"

ELFS=("$BIN")
if [[ -d "$PLUGIN_DIR" ]]; then
  while IFS= read -r f; do ELFS+=("$f"); done < <(find "$PLUGIN_DIR" -maxdepth 1 -type f -name '*.so*' | sort)
fi

# ldd prints the full transitive closure. LD_LIBRARY_PATH=lib makes re-runs
# resolve already-bundled copies (so they keep being recognised as needed).
ldd_deps() {
  local out
  out="$(LD_LIBRARY_PATH="$LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$1" 2>&1)" || die "ldd failed on $1: $out"
  if grep -q 'not found' <<<"$out"; then
    echo "$out" >&2
    die "unresolved libraries for $1 on the build host"
  fi
  awk '$2 == "=>" && $3 ~ /^\// { print $1 " " $3 }' <<<"$out"
}

declare -A SEEN=()
for elf in "${ELFS[@]}"; do
  # Not a process substitution: die must abort the whole script.
  deps="$(ldd_deps "$elf")"
  while read -r soname path; do
    [[ -z "$soname" ]] && continue
    [[ -n "${SEEN[$soname]:-}" ]] && continue
    SEEN[$soname]=1
    if [[ "$soname" =~ $EXCLUDE_REGEX ]]; then continue; fi
    real="$(readlink -f "$path")"
    base="$(basename "$real")"
    if [[ "$real" != "$LIB/$base" ]]; then
      install -m 0644 "$real" "$LIB/$base"
    fi
    if [[ "$base" != "$soname" ]]; then
      ln -sfn "$base" "$LIB/$soname"
    fi
    info "bundled $soname -> $base"
  done <<<"$deps"
done

if [[ "$PATCHELF" -eq 1 ]]; then
  # DT_RPATH (not RUNPATH) so the search path also applies to transitive
  # dependencies and wins over a host LD_LIBRARY_PATH.
  # shellcheck disable=SC2016
  patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$BIN"
  while IFS= read -r f; do
    # shellcheck disable=SC2016
    patchelf --force-rpath --set-rpath '$ORIGIN' "$f"
  done < <(find "$LIB" -maxdepth 1 -type f -name '*.so*')
  for f in "${ELFS[@]:1}"; do
    # shellcheck disable=SC2016
    patchelf --force-rpath --set-rpath '$ORIGIN/..' "$f"
  done
fi

# Verify with a clean environment: everything must resolve from lib/ or the
# excluded host set.
for elf in "${ELFS[@]}"; do
  out="$(env -u LD_LIBRARY_PATH ldd "$elf" 2>&1)"
  if grep -q 'not found' <<<"$out"; then echo "$out" >&2; die "$elf still has unresolved libraries"; fi
  if [[ "$PATCHELF" -eq 1 ]]; then
    while read -r soname path; do
      [[ "$soname" =~ $EXCLUDE_REGEX ]] && continue
      [[ "$(cd "$(dirname "$path")" && pwd -P)" == "$LIB" ]] || die "$elf resolves $soname from host ($path), expected $LIB"
    done < <(awk '$2 == "=>" && $3 ~ /^\// { print $1 " " $3 }' <<<"$out")
  fi
done
info "bundled $(find "$LIB" -maxdepth 1 -name '*.so*' -type f | wc -l) libraries into $LIB"
