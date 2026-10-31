"""Deprecated import path for GoliathExtractor helpers."""

import warnings

from goliath_extractor.cap_coverage import cap_coverage

warnings.warn(
    "methyl_extractor is deprecated; import goliath_extractor instead",
    DeprecationWarning,
    stacklevel=2,
)

__all__ = ["cap_coverage"]
