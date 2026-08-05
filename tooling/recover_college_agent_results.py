#!/usr/bin/env python3
"""Recover mechanically normalizable agent results without rerunning research."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from college_agents.common import (
    load_json,
    normalize_agent_result,
    utc_now,
    validate_agent_result,
    write_json_atomic,
)


INVALID_SUFFIX = ".invalid.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    results_dir = run_dir / "results"
    recovered: list[str] = []
    still_invalid: dict[str, list[str]] = {}

    for invalid_path in sorted(results_dir.glob(f"*{INVALID_SUFFIX}")):
        institution_id = invalid_path.name[: -len(INVALID_SUFFIX)]
        result = normalize_agent_result(
            load_json(invalid_path),
            institution_id,
        )
        errors = validate_agent_result(result, institution_id)
        if errors:
            still_invalid[institution_id] = errors
            continue

        result_path = results_dir / f"{institution_id}.json"
        write_json_atomic(result_path, result)
        invalid_path.unlink()
        recovered.append(institution_id)

        metrics_path = run_dir / "metrics" / f"{institution_id}.json"
        metrics = load_json(metrics_path) if metrics_path.exists() else {}
        metrics.update(
            {
                "institution_id": institution_id,
                "status": "completed_after_normalization",
                "errors": [],
                "result_path": str(result_path),
                "recovered_at": utc_now(),
            }
        )
        write_json_atomic(metrics_path, metrics)

    summary = {
        "recovered_count": len(recovered),
        "recovered_institution_ids": recovered,
        "still_invalid_count": len(still_invalid),
        "still_invalid": still_invalid,
    }
    write_json_atomic(run_dir / "recovery_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if not still_invalid else 1


if __name__ == "__main__":
    raise SystemExit(main())
