#!/usr/bin/env python3
"""Verify all remaining colleges in resumable sequential waves of ten."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from college_agents.common import (
    RUNS_ROOT,
    load_json,
    utc_now,
    write_json_atomic,
)
from prepare_college_agent_manifest import build_manifest


TOOLING_ROOT = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "--seed-run-dir",
        action="append",
        type=Path,
        default=[],
        help="Treat every result in this prior run as already attempted.",
    )
    parser.add_argument("--parallelism", type=int, default=10)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument(
        "--max-waves",
        type=int,
        default=0,
        help="Stop after this many waves; zero means all remaining colleges.",
    )
    parser.add_argument("--model")
    parser.add_argument("--codex-bin", default="codex")
    return parser.parse_args()


def completed_result_ids(run_dir: Path) -> set[str]:
    results_dir = run_dir.resolve() / "results"
    return {
        path.stem
        for path in results_dir.glob("*.json")
        if not path.name.endswith(".invalid.json")
    }


def run_command(
    command: list[str],
    log_path: Path,
) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as log_handle:
        completed = subprocess.run(
            command,
            cwd=TOOLING_ROOT.parent,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    return completed.returncode


def load_or_create_state(
    state_path: Path,
    seed_run_dirs: list[Path],
) -> dict[str, Any]:
    if state_path.exists():
        return load_json(state_path)
    attempted_ids: set[str] = set()
    for seed_run_dir in seed_run_dirs:
        attempted_ids.update(completed_result_ids(seed_run_dir))
    return {
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "attempted_ids": sorted(attempted_ids),
        "completed_waves": [],
        "current_wave": None,
    }


def main() -> int:
    args = parse_args()
    if not 1 <= args.parallelism <= 10:
        raise SystemExit("parallelism must be between 1 and 10")
    if args.timeout_seconds < 1:
        raise SystemExit("timeout-seconds must be positive")
    if args.max_waves < 0:
        raise SystemExit("max-waves cannot be negative")

    controller_dir = (RUNS_ROOT / args.run_id).resolve()
    controller_dir.mkdir(parents=True, exist_ok=True)
    state_path = controller_dir / "continuous_state.json"
    state = load_or_create_state(state_path, args.seed_run_dir)
    write_json_atomic(state_path, state)
    waves_this_invocation = 0

    while not args.max_waves or waves_this_invocation < args.max_waves:
        attempted_ids = set(state["attempted_ids"])
        current_wave = state.get("current_wave")
        if current_wave is None:
            manifest = build_manifest(
                batch_count=1,
                batch_size=10,
                excluded_ids=attempted_ids,
            )
            assignments = manifest["assignments"]
            if not assignments:
                break
            wave_number = len(state["completed_waves"]) + 1
            wave_run_id = f"{args.run_id}-wave-{wave_number:03d}"
            manifest_path = (
                controller_dir
                / "manifests"
                / f"wave_{wave_number:03d}.json"
            )
            write_json_atomic(manifest_path, manifest)
            current_wave = {
                "wave": wave_number,
                "run_id": wave_run_id,
                "manifest": str(manifest_path),
                "institution_ids": [
                    assignment["institution_id"]
                    for assignment in assignments
                ],
                "started_at": utc_now(),
            }
            state["current_wave"] = current_wave
            state["updated_at"] = utc_now()
            write_json_atomic(state_path, state)

        wave_number = current_wave["wave"]
        wave_run_id = current_wave["run_id"]
        manifest_path = Path(current_wave["manifest"])
        wave_run_dir = RUNS_ROOT / wave_run_id
        log_path = controller_dir / "controller_logs" / (
            f"wave_{wave_number:03d}.log"
        )
        batch_command = [
            sys.executable,
            str(TOOLING_ROOT / "run_college_batch.py"),
            "--batch",
            "1",
            "--manifest",
            str(manifest_path),
            "--run-id",
            wave_run_id,
            "--parallelism",
            str(args.parallelism),
            "--timeout-seconds",
            str(args.timeout_seconds),
            "--codex-bin",
            args.codex_bin,
        ]
        if args.model:
            batch_command.extend(["--model", args.model])
        batch_return_code = run_command(batch_command, log_path)

        recovery_return_code = run_command(
            [
                sys.executable,
                str(TOOLING_ROOT / "recover_college_agent_results.py"),
                "--run-dir",
                str(wave_run_dir),
            ],
            log_path,
        )
        valid_results = list((wave_run_dir / "results").glob("*.json"))
        valid_results = [
            path
            for path in valid_results
            if not path.name.endswith(".invalid.json")
        ]
        collection_return_code: int | None = None
        if valid_results:
            collection_return_code = run_command(
                [
                    sys.executable,
                    str(TOOLING_ROOT / "collect_college_agent_results.py"),
                    "--run-dir",
                    str(wave_run_dir),
                    "--apply",
                    "--include-removal-candidates",
                ],
                log_path,
            )

        expected_result_count = len(current_wave["institution_ids"])
        if (
            len(valid_results) != expected_result_count
            or collection_return_code != 0
        ):
            current_wave["last_attempt_finished_at"] = utc_now()
            current_wave["batch_return_code"] = batch_return_code
            current_wave["recovery_return_code"] = recovery_return_code
            current_wave["collection_return_code"] = collection_return_code
            current_wave["valid_result_count"] = len(valid_results)
            state["current_wave"] = current_wave
            state["updated_at"] = utc_now()
            write_json_atomic(state_path, state)
            print(
                json.dumps(
                    {
                        "status": "wave_incomplete",
                        "wave": wave_number,
                        "expected_result_count": expected_result_count,
                        "valid_result_count": len(valid_results),
                        "collection_return_code": collection_return_code,
                        "log_path": str(log_path),
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
            return 1

        completed_wave = {
            **current_wave,
            "finished_at": utc_now(),
            "batch_return_code": batch_return_code,
            "recovery_return_code": recovery_return_code,
            "collection_return_code": collection_return_code,
            "valid_result_count": len(valid_results),
        }
        state["completed_waves"].append(completed_wave)
        state["attempted_ids"] = sorted(
            attempted_ids | set(current_wave["institution_ids"])
        )
        state["current_wave"] = None
        state["updated_at"] = utc_now()
        write_json_atomic(state_path, state)
        waves_this_invocation += 1
        print(json.dumps(completed_wave, ensure_ascii=False), flush=True)

    summary = {
        "run_id": args.run_id,
        "finished_at": utc_now(),
        "waves_completed": len(state["completed_waves"]),
        "attempted_count": len(state["attempted_ids"]),
        "state_path": str(state_path),
    }
    write_json_atomic(controller_dir / "continuous_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
