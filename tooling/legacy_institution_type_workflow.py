#!/usr/bin/env python3
"""Research and classify legacy institute types in resumable batches of ten."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from jsonschema import Draft202012Validator, FormatChecker


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATABASE = REPO_ROOT / "assets/data/career_path.db"
DEFAULT_INVENTORY = REPO_ROOT / "research/legacy_institution_type_inventory.json"
DEFAULT_RUNS_ROOT = REPO_ROOT / "research/legacy_type_runs"
DEFAULT_SCHEMA = REPO_ROOT / "tooling/legacy_type_result.schema.json"
DEFAULT_PROMPT = REPO_ROOT / "tooling/legacy_type_worker_prompt.md"


class WorkflowError(RuntimeError):
    """A recoverable workflow validation error."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def normalized_hostname(value: str) -> str:
    return (urlparse(value).hostname or "").casefold().removeprefix("www.")


def is_http_url(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def belongs_to_website(source_url: str, website: str) -> bool:
    source_host = normalized_hostname(source_url)
    website_host = normalized_hostname(website)
    if not source_host or not website_host:
        return False
    return (
        source_host == website_host
        or source_host.endswith(f".{website_host}")
        or website_host.endswith(f".{source_host}")
    )


def normalize_type(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.casefold()).strip("_")


def load_inventory(path: Path) -> dict[str, Any]:
    payload = load_json(path)
    if not isinstance(payload, dict) or not isinstance(
        payload.get("institutions"), list
    ):
        raise WorkflowError(f"{path}: expected an institutions list")
    return payload


def build_inventory(database_path: Path, output_path: Path) -> int:
    connection = sqlite3.connect(
        f"file:{database_path.resolve()}?mode=ro", uri=True
    )
    connection.row_factory = sqlite3.Row
    try:
        known_types = [
            row["institution_type"]
            for row in connection.execute(
                """
                SELECT DISTINCT institution_type
                FROM institutes
                WHERE institution_type IS NOT NULL
                  AND TRIM(institution_type) <> ''
                ORDER BY institution_type
                """
            )
        ]
        rows = connection.execute(
            """
            SELECT id, name, city, state, website, description
            FROM institutes
            WHERE institution_type IS NULL
              AND website IS NOT NULL
              AND TRIM(website) <> ''
            ORDER BY id
            """
        ).fetchall()
    finally:
        connection.close()

    institutions = [
        {
            "institution_id": f"legacy-{row['id']}",
            "database_id": row["id"],
            "name": row["name"],
            "city": row["city"],
            "state": row["state"],
            "website": row["website"],
            "description": row["description"],
            "known_institution_types": known_types,
        }
        for row in rows
    ]
    payload = {
        "metadata": {
            "generated_at": utc_now(),
            "database": str(database_path),
            "selection": "Institutes with a website and no institution_type",
            "batch_size": 10,
            "known_institution_types": known_types,
        },
        "institutions": institutions,
    }
    write_json_atomic(output_path, payload)
    print(f"Wrote {len(institutions)} legacy institute records to {output_path}")
    return len(institutions)


def prompt_for(institution: dict[str, Any], prompt_path: Path) -> str:
    context = {
        "institution_id": institution["institution_id"],
        "database_id": institution["database_id"],
        "name": institution["name"],
        "city": institution.get("city"),
        "state": institution.get("state"),
        "website": institution["website"],
        "known_institution_types": institution.get(
            "known_institution_types", []
        ),
    }
    template = prompt_path.read_text(encoding="utf-8")
    return template.replace(
        "{{INSTITUTION_CONTEXT}}",
        json.dumps(context, ensure_ascii=False, indent=2),
    )


def validate_result(
    result: dict[str, Any],
    institution: dict[str, Any],
    schema_path: Path,
) -> list[str]:
    schema = load_json(schema_path)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = [error.message for error in validator.iter_errors(result)]
    if errors:
        return errors

    expected_id = institution["institution_id"]
    if result["institution_id"] != expected_id:
        errors.append("institution_id does not match the assigned record")
    if result["database_id"] != institution["database_id"]:
        errors.append("database_id does not match the assigned record")
    if result["name"] != institution["name"]:
        errors.append("name does not match the assigned record")
    if result["website"] != institution["website"]:
        errors.append("website does not match the assigned record")

    outcome = result["outcome"]
    source_url = result.get("source_url")
    if source_url is not None:
        if not is_http_url(source_url):
            errors.append("source_url must be an HTTP(S) URL")
        elif not belongs_to_website(source_url, institution["website"]):
            errors.append("source_url is outside the supplied official website")

    if outcome == "classified":
        if not isinstance(result.get("institution_type"), str) or not result[
            "institution_type"
        ].strip():
            errors.append("classified result requires institution_type")
        if source_url is None:
            errors.append("classified result requires source_url")
        if result.get("confidence") not in {"high", "medium", "low"}:
            errors.append("classified result requires confidence")
        if not isinstance(result.get("evidence"), str) or not result["evidence"].strip():
            errors.append("classified result requires evidence")
    else:
        if any(result.get(field) is not None for field in ("institution_type", "source_url", "confidence", "evidence")):
            errors.append("manual_review result must not include a classification")
    return errors


def run_one(
    institution: dict[str, Any],
    batch_dir: Path,
    *,
    schema_path: Path,
    prompt_path: Path,
    codex_bin: str,
    timeout_seconds: int,
    force: bool,
) -> dict[str, Any]:
    institution_id = institution["institution_id"]
    result_dir = batch_dir / "results"
    logs_dir = batch_dir / "logs"
    metrics_dir = batch_dir / "metrics"
    workspace = batch_dir / "workspaces" / institution_id
    for path in (result_dir, logs_dir, metrics_dir, workspace, workspace / "tmp"):
        path.mkdir(parents=True, exist_ok=True)
    result_path = result_dir / f"{institution_id}.json"
    temporary_result = result_dir / f".{institution_id}.result.tmp"
    metrics_path = metrics_dir / f"{institution_id}.json"
    log_path = logs_dir / f"{institution_id}.jsonl"

    if result_path.exists() and not force:
        try:
            existing = load_json(result_path)
            errors = validate_result(existing, institution, schema_path)
        except Exception as exc:
            errors = [f"existing result could not be read: {exc}"]
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
    temporary_result.unlink(missing_ok=True)
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
        str(workspace),
        "--output-schema",
        str(schema_path),
        "--output-last-message",
        str(temporary_result),
        "--json",
        "-",
    ]
    started_at = utc_now()
    started = time.monotonic()
    timed_out = False
    return_code: int | None = None

    def terminate(process: subprocess.Popen[str]) -> None:
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
        environment = os.environ.copy()
        environment["TMPDIR"] = str(workspace / "tmp")
        process = subprocess.Popen(
            command,
            cwd=workspace,
            stdin=subprocess.PIPE,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
            env=environment,
        )
        try:
            process.communicate(
                input=prompt_for(institution, prompt_path),
                timeout=timeout_seconds,
            )
            return_code = process.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            terminate(process)
            return_code = process.returncode

    errors: list[str] = []
    result: dict[str, Any] | None = None
    if timed_out:
        errors.append(f"agent timed out after {timeout_seconds} seconds")
    if return_code != 0:
        errors.append(f"codex exec exited with code {return_code}")
    if not temporary_result.exists():
        errors.append("codex exec did not create a final result")
    else:
        try:
            loaded = load_json(temporary_result)
            if not isinstance(loaded, dict):
                errors.append("agent result must be an object")
            else:
                if isinstance(loaded.get("institution_type"), str):
                    loaded["institution_type"] = normalize_type(
                        loaded["institution_type"]
                    )
                result = loaded
                errors.extend(validate_result(result, institution, schema_path))
        except Exception as exc:
            errors.append(f"agent result could not be validated: {exc}")

    status = "failed"
    if not errors and result is not None:
        write_json_atomic(result_path, result)
        temporary_result.unlink(missing_ok=True)
        status = "completed"
    elif temporary_result.exists():
        temporary_result.replace(result_dir / f"{institution_id}.invalid.json")

    metrics = {
        "institution_id": institution_id,
        "status": status,
        "started_at": started_at,
        "finished_at": utc_now(),
        "duration_seconds": round(time.monotonic() - started, 3),
        "return_code": return_code,
        "timed_out": timed_out,
        "errors": errors,
        "result_path": str(result_path) if status == "completed" else None,
        "log_path": str(log_path),
    }
    write_json_atomic(metrics_path, metrics)
    return metrics


def ensure_type_columns(connection: sqlite3.Connection) -> None:
    columns = {
        row[1] for row in connection.execute("PRAGMA table_info(institutes)")
    }
    additions = {
        "institution_type": "TEXT",
        "institution_type_source_url": "TEXT",
        "institution_type_confidence": "TEXT",
        "institution_type_notes": "TEXT",
        "institution_type_verified_at": "TEXT",
    }
    for name, data_type in additions.items():
        if name not in columns:
            connection.execute(
                f"ALTER TABLE institutes ADD COLUMN {name} {data_type}"
            )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_institutes_type "
        "ON institutes(institution_type)"
    )


def collect_batch(
    batch_dir: Path,
    inventory: dict[str, Any],
    database_path: Path,
    schema_path: Path,
) -> dict[str, Any]:
    by_id = {
        record["institution_id"]: record for record in inventory["institutions"]
    }
    result_paths = sorted(
        path
        for path in (batch_dir / "results").glob("*.json")
        if not path.name.endswith(".invalid.json")
    )
    classified = 0
    manual_review = 0
    skipped = 0
    errors: dict[str, list[str]] = {}
    connection = sqlite3.connect(database_path)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("BEGIN IMMEDIATE")
        ensure_type_columns(connection)
        for result_path in result_paths:
            result = load_json(result_path)
            institution = by_id.get(result.get("institution_id"))
            if institution is None:
                errors[result_path.name] = ["result is not in the inventory"]
                continue
            result_errors = validate_result(result, institution, schema_path)
            if result_errors:
                errors[result_path.name] = result_errors
                continue
            if result["outcome"] == "manual_review":
                manual_review += 1
                continue
            cursor = connection.execute(
                """
                UPDATE institutes
                SET institution_type = ?,
                    institution_type_source_url = ?,
                    institution_type_confidence = ?,
                    institution_type_notes = ?,
                    institution_type_verified_at = ?
                WHERE id = ? AND institution_type IS NULL
                """,
                (
                    result["institution_type"],
                    result["source_url"],
                    result["confidence"],
                    json.dumps(
                        {"evidence": result["evidence"], "notes": result["notes"]},
                        ensure_ascii=False,
                    ),
                    utc_now(),
                    result["database_id"],
                ),
            )
            if cursor.rowcount == 1:
                classified += 1
            else:
                skipped += 1
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    summary = {
        "batch": batch_dir.name,
        "result_count": len(result_paths),
        "classified": classified,
        "manual_review": manual_review,
        "skipped_existing": skipped,
        "validation_errors": errors,
        "collected_at": utc_now(),
    }
    write_json_atomic(batch_dir / "collection_summary.json", summary)
    return summary


def run_batch(
    batch_records: list[dict[str, Any]],
    batch_number: int,
    run_dir: Path,
    *,
    inventory: dict[str, Any],
    database_path: Path,
    schema_path: Path,
    prompt_path: Path,
    codex_bin: str,
    parallelism: int,
    timeout_seconds: int,
    force: bool,
) -> dict[str, Any]:
    batch_dir = run_dir / f"batch_{batch_number:03d}"
    results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=parallelism) as executor:
        futures = {
            executor.submit(
                run_one,
                record,
                batch_dir,
                schema_path=schema_path,
                prompt_path=prompt_path,
                codex_bin=codex_bin,
                timeout_seconds=timeout_seconds,
                force=force,
            ): record
            for record in batch_records
        }
        for future in as_completed(futures):
            record = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = {
                    "institution_id": record["institution_id"],
                    "status": "orchestrator_error",
                    "errors": [f"{type(exc).__name__}: {exc}"],
                }
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)
    results.sort(key=lambda item: item["institution_id"])
    collection = collect_batch(batch_dir, inventory, database_path, schema_path)
    summary = {
        "batch": batch_number,
        "institution_ids": [record["institution_id"] for record in batch_records],
        "results": results,
        "completed": sum(item["status"] == "completed" for item in results),
        "failed": sum(item["status"] == "failed" for item in results),
        "collection": collection,
        "finished_at": utc_now(),
    }
    write_json_atomic(batch_dir / "batch_summary.json", summary)
    return summary


def load_or_create_state(path: Path) -> dict[str, Any]:
    if path.exists():
        return load_json(path)
    return {
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "attempted_ids": [],
        "completed_batches": [],
        "current_batch": None,
    }


def run_continuous(args: argparse.Namespace) -> int:
    inventory_path = args.inventory.resolve()
    if not inventory_path.exists() or args.rebuild_inventory:
        build_inventory(args.database.resolve(), inventory_path)
    inventory = load_inventory(inventory_path)
    run_dir = (args.runs_root / args.run_id).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    state_path = run_dir / "continuous_state.json"
    state = load_or_create_state(state_path)
    write_json_atomic(state_path, state)
    batches_this_run = 0

    while args.max_batches == 0 or batches_this_run < args.max_batches:
        attempted = set(state.get("attempted_ids", []))
        current = state.get("current_batch")
        if current is None:
            remaining = [
                record
                for record in inventory["institutions"]
                if record["institution_id"] not in attempted
            ]
            if not remaining:
                break
            records = remaining[:10]
            batch_number = len(state.get("completed_batches", [])) + 1
            manifest = {
                "batch": batch_number,
                "created_at": utc_now(),
                "institution_ids": [record["institution_id"] for record in records],
                "records": records,
            }
            manifest_path = run_dir / "manifests" / f"batch_{batch_number:03d}.json"
            write_json_atomic(manifest_path, manifest)
            current = {
                "batch": batch_number,
                "manifest": str(manifest_path),
                "institution_ids": manifest["institution_ids"],
                "started_at": utc_now(),
            }
            state["current_batch"] = current
            state["updated_at"] = utc_now()
            write_json_atomic(state_path, state)
        records = load_json(Path(current["manifest"]))["records"]
        summary = run_batch(
            records,
            current["batch"],
            run_dir,
            inventory=inventory,
            database_path=args.database.resolve(),
            schema_path=args.schema.resolve(),
            prompt_path=args.prompt.resolve(),
            codex_bin=args.codex_bin,
            parallelism=args.parallelism,
            timeout_seconds=args.timeout_seconds,
            force=args.force,
        )
        completed = {
            **current,
            "finished_at": utc_now(),
            "summary": summary,
        }
        state.setdefault("completed_batches", []).append(completed)
        state["attempted_ids"] = sorted(
            attempted | set(current["institution_ids"])
        )
        state["current_batch"] = None
        state["updated_at"] = utc_now()
        write_json_atomic(state_path, state)
        batches_this_run += 1
        print(json.dumps(completed, ensure_ascii=False), flush=True)

    final = {
        "run_id": args.run_id,
        "finished_at": utc_now(),
        "batches_completed": len(state.get("completed_batches", [])),
        "attempted_count": len(state.get("attempted_ids", [])),
        "inventory_count": len(inventory["institutions"]),
        "state_path": str(state_path),
    }
    write_json_atomic(run_dir / "continuous_summary.json", final)
    print(json.dumps(final, ensure_ascii=False), flush=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    parser.add_argument("--runs-root", type=Path, default=DEFAULT_RUNS_ROOT)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--prompt", type=Path, default=DEFAULT_PROMPT)
    parser.add_argument("--codex-bin", default=os.environ.get("CODEX_BIN", "codex"))
    parser.add_argument("--parallelism", type=int, default=10)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    parser.add_argument("--max-batches", type=int, default=0)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--rebuild-inventory", action="store_true")
    parser.add_argument(
        "--build-inventory-only",
        action="store_true",
        help="Generate the legacy inventory and stop before research.",
    )
    args = parser.parse_args()
    if not 1 <= args.parallelism <= 10:
        raise SystemExit("parallelism must be between 1 and 10")
    if args.timeout_seconds < 1:
        raise SystemExit("timeout-seconds must be positive")
    if args.max_batches < 0:
        raise SystemExit("max-batches cannot be negative")
    if args.build_inventory_only:
        build_inventory(args.database.resolve(), args.inventory.resolve())
        return 0
    return run_continuous(args)


if __name__ == "__main__":
    raise SystemExit(main())
