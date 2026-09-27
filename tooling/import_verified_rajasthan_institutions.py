#!/usr/bin/env python3
"""Backward-compatible Rajasthan entrypoint for the generic importer."""

from import_verified_institutions import *  # noqa: F401,F403
from import_verified_institutions import main


if __name__ == "__main__":
    raise SystemExit(main())
