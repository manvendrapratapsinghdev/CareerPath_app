#!/usr/bin/env python3
"""Run one isolated Codex agent for one institution."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Any

from college_agents.common import (
    DATABASE_PATH,
    RUNS_ROOT,
    SCHEMA_PATH,
    build_prompt,
    load_inventory_institution,
    normalize_agent_result,
    utc_now,
    validate_agent_result,
    write_json_atomic,
)


def run_agent(
    institution_id: str,
    run_dir: Path,
    *,
    model: str | None = None,
    timeout_seconds: int = 1800,
    force: bool = False,
    codex_bin: str = "codex",
) -> dict[str, Any]:
    institution = load_inventory_institution(institution_id)
    results_dir = run_dir / "results"
    logs_dir = run_dir / "logs"
    metrics_dir = run_dir / "metrics"
    workspace_dir = run_dir / "workspaces" / institution_id
    for directory in (results_dir, logs_dir, metrics_dir, workspace_dir):
        directory.mkdir(parents=True, exist_ok=True)
    isolated_database = workspace_dir / "assets/data/career_path.db"
    isolated_tmp_dir = workspace_dir / "tmp"
    isolated_database.parent.mkdir(parents=True, exist_ok=True)
    isolated_tmp_dir.mkdir(parents=True, exist_ok=True)
    if force or not isolated_database.exists():
        shutil.copy2(DATABASE_PATH, isolated_database)

    result_path = results_dir / f"{institution_id}.json"
    log_path = logs_dir / f"{institution_id}.jsonl"
    metrics_path = metrics_dir / f"{institution_id}.json"
    temporary_result_path = results_dir / f".{institution_id}.result.tmp"

    if result_path.exists() and not force:
        existing = json.loads(result_path.read_text(encoding="utf-8"))
        errors = validate_agent_result(existing, institution_id)
        if not errors:
            metrics = {
                "institution_id": institution_id,
                "status": "skipped_valid_existing_result",
                "result_path": str(result_path),
                "finished_at": utc_now(),
            }
            write_json_atomic(metrics_path, metrics)
            return metrics

    resolved_codex = shutil.which(codex_bin)
    if resolved_codex is None:
        raise FileNotFoundError(f"Codex executable not found: {codex_bin}")

    temporary_result_path.unlink(missing_ok=True)
    prompt = build_prompt(institution)
    command = [
        resolved_codex,
        "exec",
        "--ephemeral",
        "--sandbox",
        "workspace-write",
        "--config",
        "sandbox_workspace_write.network_access=true",
        "--config",
        "sandbox_workspace_write.exclude_slash_tmp=true",
        "--config",
        "sandbox_workspace_write.exclude_tmpdir_env_var=true",
        "--skip-git-repo-check",
        "--cd",
        str(workspace_dir),
        "--output-schema",
        str(SCHEMA_PATH),
        "--output-last-message",
        str(temporary_result_path),
        "--json",
        "-",
    ]
    if model:
        command[2:2] = ["--model", model]

    started_at = utc_now()
    started = time.monotonic()
    timed_out = False
    return_code: int | None = None
    def terminate_process(process: subprocess.Popen[str]) -> None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()

    with log_path.open("w", encoding="utf-8") as log_handle:
        worker_environment = os.environ.copy()
        worker_environment["TMPDIR"] = str(isolated_tmp_dir)
        process = subprocess.Popen(
            command,
            cwd=workspace_dir,
            stdin=subprocess.PIPE,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            env=worker_environment,
        )
        try:
            process.communicate(input=prompt, timeout=timeout_seconds)
            return_code = process.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            terminate_process(process)
            return_code = process.returncode
        except BaseException:
            terminate_process(process)
            raise

    duration_seconds = round(time.monotonic() - started, 3)
    errors: list[str] = []
    result: dict[str, Any] | None = None
    if timed_out:
        errors.append(f"agent timed out after {timeout_seconds} seconds")
    if return_code != 0:
        errors.append(f"codex exec exited with code {return_code}")
    if not temporary_result_path.exists():
        errors.append("codex exec did not create a final result")
    else:
        try:
            loaded = json.loads(
                temporary_result_path.read_text(encoding="utf-8")
            )
            if not isinstance(loaded, dict):
                errors.append("agent result must be a JSON object")
            else:
                result = normalize_agent_result(loaded, institution_id)
                errors.extend(validate_agent_result(result, institution_id))
        except json.JSONDecodeError as exc:
            errors.append(f"agent result is not valid JSON: {exc}")

    status = "failed"
    if not errors and result is not None:
        write_json_atomic(result_path, result)
        temporary_result_path.unlink(missing_ok=True)
        status = "completed"
    elif temporary_result_path.exists():
        invalid_path = results_dir / f"{institution_id}.invalid.json"
        temporary_result_path.replace(invalid_path)

    metrics = {
        "institution_id": institution_id,
        "nirf_name": institution["nirf_name"],
        "status": status,
        "started_at": started_at,
        "finished_at": utc_now(),
        "duration_seconds": duration_seconds,
        "return_code": return_code,
        "timed_out": timed_out,
        "errors": errors,
        "result_path": str(result_path) if status == "completed" else None,
        "log_path": str(log_path),
    }
    write_json_atomic(metrics_path, metrics)
    return metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--institution-id", required=True)
    parser.add_argument(
        "--run-dir",
        type=Path,
        default=RUNS_ROOT / "single",
    )
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
    if args.timeout_seconds < 1:
        raise SystemExit("timeout-seconds must be positive")
    metrics = run_agent(
        args.institution_id,
        args.run_dir.resolve(),
        model=args.model,
        timeout_seconds=args.timeout_seconds,
        force=args.force,
        codex_bin=args.codex_bin,
    )
    print(json.dumps(metrics, ensure_ascii=False))
    return 0 if metrics["status"].startswith(("completed", "skipped")) else 1


if __name__ == "__main__":
    raise SystemExit(main())
