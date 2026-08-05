#!/usr/bin/env python3
"""Run ten batch scripts in parallel (up to 100 isolated agents)."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from college_agents.common import (
    DEFAULT_MANIFEST_PATH,
    INVENTORY_PATH,
    RUNS_ROOT,
    load_json,
    sha256_file,
    utc_now,
    write_json_atomic,
)


BATCH_SCRIPTS_DIR = Path(__file__).with_name("college_batches")


def default_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def run_batch_script(
    batch: int,
    run_dir: Path,
    common_arguments: list[str],
) -> dict[str, Any]:
    script = BATCH_SCRIPTS_DIR / f"batch_{batch:02d}.sh"
    log_path = run_dir / "batch_logs" / f"batch_{batch:02d}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log_handle:
        completed = subprocess.run(
            ["/bin/bash", str(script), *common_arguments],
            cwd=script.parent.parent.parent,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    return {
        "batch": batch,
        "return_code": completed.returncode,
        "status": "completed" if completed.returncode == 0 else "failed",
        "log_path": str(log_path),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH)
    parser.add_argument("--run-id", default=default_run_id())
    parser.add_argument("--batch-parallelism", type=int, default=10)
    parser.add_argument("--agent-parallelism", type=int, default=10)
    parser.add_argument("--model")
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--allow-stale-manifest", action="store_true")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print the 10-by-10 execution plan without agents.",
    )
    parser.add_argument(
        "--codex-bin",
        default=os.environ.get("CODEX_BIN", "codex"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 1 <= args.batch_parallelism <= 10:
        raise SystemExit("batch-parallelism must be between 1 and 10")
    if not 1 <= args.agent_parallelism <= 10:
        raise SystemExit("agent-parallelism must be between 1 and 10")

    manifest_path = args.manifest.resolve()
    manifest = load_json(manifest_path)
    metadata = manifest["metadata"]
    if metadata["batch_count"] != 10 or metadata["batch_size"] != 10:
        raise SystemExit(
            "The master runner requires a 10-batch x 10-agent manifest"
        )
    assignments = manifest["assignments"]
    if len(assignments) != 100:
        raise SystemExit(
            f"The master runner requires exactly 100 assignments; "
            f"found {len(assignments)}"
        )
    current_inventory_hash = sha256_file(INVENTORY_PATH)
    if (
        metadata["inventory_sha256"] != current_inventory_hash
        and not args.allow_stale_manifest
    ):
        raise SystemExit(
            "The assignment manifest is stale because the master inventory "
            "changed. Regenerate it or pass --allow-stale-manifest."
        )
    batch_plan = []
    for batch in range(1, 11):
        script = BATCH_SCRIPTS_DIR / f"batch_{batch:02d}.sh"
        batch_assignments = [
            assignment
            for assignment in assignments
            if assignment["batch"] == batch
        ]
        if not script.is_file():
            raise SystemExit(f"Missing batch script: {script}")
        if len(batch_assignments) != 10:
            raise SystemExit(
                f"Batch {batch} requires 10 assignments; "
                f"found {len(batch_assignments)}"
            )
        batch_plan.append(
            {
                "batch": batch,
                "script": str(script),
                "institution_ids": [
                    assignment["institution_id"]
                    for assignment in batch_assignments
                ],
            }
        )
    if args.dry_run:
        print(
            json.dumps(
                {
                    "status": "dry_run_valid",
                    "batch_count": len(batch_plan),
                    "agents_per_batch": 10,
                    "assignment_count": len(assignments),
                    "configured_max_parallel_agents": (
                        args.batch_parallelism * args.agent_parallelism
                    ),
                    "batches": batch_plan,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    run_dir = (RUNS_ROOT / args.run_id).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    common_arguments = [
        "--manifest",
        str(manifest_path),
        "--run-id",
        args.run_id,
        "--parallelism",
        str(args.agent_parallelism),
        "--timeout-seconds",
        str(args.timeout_seconds),
        "--codex-bin",
        args.codex_bin,
    ]
    if args.model:
        common_arguments.extend(["--model", args.model])
    if args.force:
        common_arguments.append("--force")

    started_at = utc_now()
    batch_results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=args.batch_parallelism) as executor:
        futures = {
            executor.submit(
                run_batch_script,
                batch,
                run_dir,
                common_arguments,
            ): batch
            for batch in range(1, 11)
        }
        for future in as_completed(futures):
            batch = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = {
                    "batch": batch,
                    "return_code": None,
                    "status": "orchestrator_error",
                    "error": f"{type(exc).__name__}: {exc}",
                }
            batch_results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)

    batch_results.sort(key=lambda item: item["batch"])
    summary = {
        "run_id": args.run_id,
        "started_at": started_at,
        "finished_at": utc_now(),
        "manifest": str(manifest_path),
        "assignment_count": len(assignments),
        "configured_max_parallel_agents": (
            args.batch_parallelism * args.agent_parallelism
        ),
        "successful_batch_count": sum(
            result["status"] == "completed" for result in batch_results
        ),
        "failed_batch_count": sum(
            result["status"] != "completed" for result in batch_results
        ),
        "batches": batch_results,
    }
    write_json_atomic(run_dir / "master_summary.json", summary)
    return 0 if summary["failed_batch_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
