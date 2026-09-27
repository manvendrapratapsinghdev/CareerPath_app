# State college verification agents

This workflow verifies colleges from any Indian state in isolated, resumable
Codex workers. It keeps discovery, official-site verification, curation, and
database import separate: no worker or merge preview writes the shared app
database.

## State inventory contract

The inventory must contain an `institutions` array. Each item needs:

- `id`: stable, unique slug;
- `nirf_name`: source-list institution name (the field is retained for schema compatibility);
- `nirf_city`: source-list city;
- `state`: the state being processed;
- `participating_categories`, `rankings`, and `existing_database_records` (empty arrays are valid);
- pending verification fields such as `website_verification_status: "pending"`.

Because government portals have different HTML formats, first export or
transcribe the official list into a small JSON file, then normalize it:

```bash
python3 tooling/prepare_state_inventory.py \
  --state Gujarat \
  --source-list research/gujarat_government_colleges.json \
  --source-url https://example.gujarat.gov.in/colleges \
  --output research/gujarat_state_inventory.json
```

The repository includes an official NIRF discovery command for a broad
state-wide candidate set:

```bash
python3 tooling/discover_nirf_state_inventory.py \
  --state "Uttar Pradesh" \
  --limit 150 \
  --output research/uttar_pradesh_nirf_candidates.json

python3 tooling/prepare_state_inventory.py \
  --state "Uttar Pradesh" \
  --source-list research/uttar_pradesh_nirf_candidates.json \
  --source-url https://www.nirfindia.org/Rankings/2025/ \
  --output research/uttar_pradesh_nirf_state_inventory.json
```

NIRF is discovery-only. It supplies candidate names, cities, categories, and
priority hints; agents must still verify the institution and catalogue from
the institution's official website.

The command never claims a website or course is verified. Replace the example
URL with the real official state portal URL.

## Prepare and run batches

Create deterministic assignments for a state. The default command prepares up to 200 candidates in forty isolated batches of five. Use `--batch-count 20 --batch-size 5` for 100 candidates, `--batch-count 40 --batch-size 5` for 200 candidates, or `--candidate-limit 0` to remove the explicit candidate limit and let the batch plan determine capacity. Batch size may be increased up to ten when a larger isolated batch is deliberately preferred. Assignment order is IIT, IIM, NIT/IIIT, central university/institute, state university, private university/college, government/aided degree college, polytechnic, medical, law, agriculture, then specialized institutes.

The inventory must contain 100–200 pending candidates for a full discovery wave. Already verified records are excluded from assignments; manual-review and removal outcomes are excluded from the curated verification file and database import.

```bash
python3 tooling/discover_nirf_state_inventory.py \
  --state "Madhya Pradesh" \
  --limit 200 \
  --output research/madhya_pradesh_nirf_candidates.json

python3 tooling/prepare_state_inventory.py \
  --state "Madhya Pradesh" \
  --source-list research/madhya_pradesh_nirf_candidates.json \
  --source-url https://www.nirfindia.org/Rankings/2025/ \
  --output research/madhya_pradesh_nirf_state_inventory.json

python3 tooling/prepare_college_agent_manifest.py \
  --inventory research/madhya_pradesh_nirf_state_inventory.json \
  --candidate-limit 200 \
  --batch-count 40 --batch-size 5 \
  --output research/madhya_pradesh_agent_assignments.json --force
```

To run the agents, pass the same Madhya Pradesh inventory and manifest to
`run_college_master.py` with `--dry-run` first. Each worker receives a copy of
`assets/data/career_path.db`, uses the shared strict JSON schema and official-
site prompt, and writes only to its own run directory. Network research is
performed by the worker; NIRF is discovery-only and never counts as official
website verification.

For a single batch instead of the ten-batch master:

```bash
python3 tooling/run_college_batch.py \
  --batch 1 \
  --inventory research/gujarat_state_inventory.json \
  --manifest research/gujarat_agent_assignments.json \
  --run-id gujarat-wave-01 \
  --parallelism 10
```

## Validate, collect, and import

First create a non-destructive merge preview. By default, only `verified`
results are collected; `manual_review` and `remove_candidate` results are
skipped and never reach the database.

```bash
python3 tooling/collect_college_agent_results.py \
  --run-dir research/agent_runs/gujarat-wave-01 \
  --inventory research/gujarat_state_inventory.json \
  --verifications research/gujarat_institution_verifications.json
```

After reviewing the preview, atomically apply only validated result records:

```bash
python3 tooling/collect_college_agent_results.py \
  --run-dir research/agent_runs/gujarat-wave-01 \
  --inventory research/gujarat_state_inventory.json \
  --verifications research/gujarat_institution_verifications.json \
  --apply

python3 tooling/validate_verifications.py \
  --verifications research/gujarat_institution_verifications.json \
  --inventory research/gujarat_state_inventory.json \
  --database assets/data/career_path.db
```

Only after that validation succeeds, import into a copy of the database first:

```bash
cp assets/data/career_path.db /tmp/career_path.gujarat.db
python3 tooling/import_verified_institutions.py \
  --database /tmp/career_path.gujarat.db \
  --verifications research/gujarat_institution_verifications.json \
  --inventory research/gujarat_state_inventory.json
```

The generic importer re-runs full verification-file validation before opening
its write transaction. It admits only records with verified official website,
district, description, and complete official catalogue statuses; only verified
course statuses are accepted. It uses `BEGIN IMMEDIATE`, checks foreign keys,
rolls back on every error, and commits only after all records pass. Review the
resulting database, then replace the packaged asset deliberately as part of
the release/data-update process.

## Rajasthan compatibility

The original Rajasthan commands and paths remain available. The old
`import_verified_rajasthan_institutions.py` and
`validate_rajasthan_verifications.py` files are compatibility wrappers around
the generic implementations. Existing Rajasthan manifests, batch scripts, and
tests continue to use their original defaults.
