# Rajasthan college verification agents

This workflow verifies colleges in isolated, resumable Codex workers. Parallel
workers never edit the shared verification or master inventory files.

## Structure

- `run_college_agent.py`: one institution and one isolated Codex process.
- `run_college_batch.py`: one batch with at most ten concurrent agents.
- `college_batches/batch_01.sh` through `batch_10.sh`: the ten explicit batch
  entrypoints.
- `run_college_master.py`: runs all ten batch scripts concurrently, producing
  up to 100 concurrent agents.
- `collect_college_agent_results.py`: validates and serially collects results.
- `recover_college_agent_results.py`: safely repairs deterministic identifier
  formatting in preserved invalid results without repeating web research.
- `run_colleges_continuously.py`: runs resumable sequential waves of ten,
  collecting each wave before advancing to the next ten.
- `college_agents/agent_result.schema.json`: structured-output contract.
- `college_agents/worker_prompt.md`: shared official-site research contract.

Each worker has its own writable directory under
`research/agent_runs/<run-id>/workspaces/`. It receives only a copy of
`career_path.db`. The repository master files are not in its writable
workspace.

## Install research dependencies

```bash
python3 -m pip install -r tooling/requirements-research.txt
```

## Prepare the first 100 assignments

The manifest prioritizes all remaining ranked or banded institutions, then
sorts the other pending institutions deterministically.

```bash
python3 tooling/prepare_college_agent_manifest.py --force
```

The runner rejects a stale manifest when the master inventory changes.

Validate all ten scripts and 100 assignments without launching agents:

```bash
python3 tooling/run_college_master.py --dry-run
```

## Test one institution

```bash
python3 tooling/run_college_agent.py \
  --institution-id indian-institute-of-technology-jodhpur \
  --run-dir research/agent_runs/smoke-iitj \
  --timeout-seconds 1800
```

This stages a result only. It never modifies the curated verification file.

## Run one ten-agent batch

```bash
bash tooling/college_batches/batch_01.sh \
  --manifest research/rajasthan_agent_assignments.json \
  --run-id rajasthan-wave-01 \
  --parallelism 10
```

## Run ten batches of ten agents

```bash
python3 tooling/run_college_master.py \
  --manifest research/rajasthan_agent_assignments.json \
  --run-id rajasthan-wave-01 \
  --batch-parallelism 10 \
  --agent-parallelism 10
```

This permits up to 100 Codex processes at once. Account rate limits, RAM,
network capacity, and official-site anti-bot controls may make a smaller value
more reliable. Runs are resumable: a valid existing result is skipped unless
`--force` is supplied.

To process every remaining institution ten at a time:

```bash
python3 tooling/run_colleges_continuously.py \
  --run-id rajasthan-all-schools \
  --seed-run-dir research/agent_runs/rajasthan-wave-01-live \
  --seed-run-dir research/agent_runs/rajasthan-wave-02-live
```

## Validate and collect

Create a non-destructive merge preview:

```bash
python3 tooling/collect_college_agent_results.py \
  --run-dir research/agent_runs/rajasthan-wave-01
```

After reviewing the preview, atomically apply verified results:

```bash
python3 tooling/collect_college_agent_results.py \
  --run-dir research/agent_runs/rajasthan-wave-01 \
  --apply
```

`manual_review` results are always skipped. `remove_candidate` results are also
skipped unless `--include-removal-candidates` is explicitly supplied. Existing
curated records are preserved unless `--replace-existing` is supplied.

Finally regenerate and validate the master inventory:

```bash
python3 tooling/nirf_rajasthan_inventory.py \
  --output research/rajasthan_nirf_master_inventory.json
python3 tooling/validate_rajasthan_verifications.py
```

## Output and metrics

Every run records:

- one schema-validated result per institution;
- one JSONL execution log per institution;
- duration, return code, timeout, and validation errors per worker;
- one summary per batch;
- one master summary containing configured concurrency and batch outcomes.
