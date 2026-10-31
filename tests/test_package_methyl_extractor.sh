#!/bin/bash
# Deprecated wrapper — use tests/test_package_goliath_extractor.sh
echo "[deprecated] tests/test_package_methyl_extractor.sh: use tests/test_package_goliath_extractor.sh" >&2
exec "$(dirname "${BASH_SOURCE[0]}")/test_package_goliath_extractor.sh" "$@"
