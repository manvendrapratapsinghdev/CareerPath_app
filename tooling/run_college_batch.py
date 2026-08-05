#!/usr/bin/env python3
"""Run one manifest batch with up to ten concurrent college agents."""

from __future__ import annotations

import argparse
import json
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from college_agents.common import (
    DEFAULT_MANIFEST_PATH,
    RUNS_ROOT,
    load_json,
    utc_now,
    write_json_atomic,
)
from run_college_agent import run_agent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", type=int, required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--parallelism", type=int, default=10)
    parser.add_argument("--model")
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--codex-bin",
        default=os.environ.get("CODEX_BIN", "codex"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.batch < 1:
        raise SystemExit("batch must be positive")
    if not 1 <= args.parallelism <= 10:
        raise SystemExit("parallelism must be between 1 and 10")
    manifest = load_json(args.manifest.resolve())
    assignments = [
        assignment
        for assignment in manifest["assignments"]
        if assignment["batch"] == args.batch
    ]
    if not assignments:
        raise SystemExit(f"No assignments found for batch {args.batch}")
    if len(assignments) > 10:
        raise SystemExit(
            f"Batch {args.batch} contains {len(assignments)} assignments; "
            "the maximum is 10"
        )

    run_dir = (RUNS_ROOT / args.run_id).resolve()
    batch_started_at = utc_now()
    results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=args.parallelism) as executor:
        futures = {
            executor.submit(
                run_agent,
                assignment["institution_id"],
                run_dir,
                model=args.model,
                timeout_seconds=args.timeout_seconds,
                force=args.force,
                codex_bin=args.codex_bin,
            ): assignment
            for assignment in assignments
        }
        for future in as_completed(futures):
            assignment = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = {
                    "institution_id": assignment["institution_id"],
                    "status": "orchestrator_error",
                    "errors": [f"{type(exc).__name__}: {exc}"],
                }
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)

    results.sort(key=lambda item: item["institution_id"])
    summary = {
        "batch": args.batch,
        "started_at": batch_started_at,
        "finished_at": utc_now(),
        "assignment_count": len(assignments),
        "completed_count": sum(
            item["status"] == "completed" for item in results
        ),
        "skipped_count": sum(
            item["status"].startswith("skipped") for item in results
        ),
        "failed_count": sum(
            not item["status"].startswith(("completed", "skipped"))
            for item in results
        ),
        "results": results,
    }
    summary_path = run_dir / "batches" / f"batch_{args.batch:02d}.json"
    write_json_atomic(summary_path, summary)
    return 0 if summary["failed_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
