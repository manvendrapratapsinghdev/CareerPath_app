#!/usr/bin/env python3
"""Backward-compatible Rajasthan entrypoint for generic validation."""

from validate_verifications import *  # noqa: F401,F403
from validate_verifications import main


if __name__ == "__main__":
    raise SystemExit(main())
