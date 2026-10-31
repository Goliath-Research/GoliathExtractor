#!/bin/bash
# Deprecated wrapper — use scripts/package_goliath_extractor.sh
echo "[deprecated] scripts/package_methyl_extractor.sh: use scripts/package_goliath_extractor.sh" >&2
exec "$(dirname "${BASH_SOURCE[0]}")/package_goliath_extractor.sh" "$@"
