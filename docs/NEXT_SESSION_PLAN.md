# Next Session Plan — Meta‑Enliterator Completion

This document is a self‑contained bootstrap prompt and execution plan to start a fresh session with minimal context.

## Session Bootstrap Prompt
- You are assisting on the Enliterator repo to complete the Meta‑Enliterator pipeline (Stages 0–8) and make it reproducible, observable, and recoverable. Do not assume prior memory; use only in‑repo context.
- Read order on start: `README.md` → `CLAUDE.md` → `.claude/ON_START.md` → `AGENTS.md` → `docs/NEO4J.md` → `docs/PROJECT_STATUS.md` → `lib/tasks/enliterator.rake`.
- Non‑negotiables:
  - Use Neo4j GenAI for embeddings (no pgvector). Per‑EKN Neo4j DB (`ekn-{id}`); always use `Graph::Connection`.
  - GPT‑5: do NOT send `temperature` unless supported. Use `OpenaiConfig::SettingsManager` for models and zero‑temp extraction.
  - Rights/provenance‑first. Quarantine ambiguous items; never invent facts; always cite/ground.
  - Start app via `bin/dev`. Prefer rake tasks over ad‑hoc scripts.
- Success metric: Create a functional Meta‑EKN by ingesting this repo (code + docs), literacy score ≥ 70, all acceptance gates pass, deliverables generated. Provide a single‑command runner.

## Deliverables To Implement
- Rake tasks
  - `enliterator:bundle[full|micro]`: build `data/bundles/micro.zip` (10 seeded files) and `data/bundles/enliterator-full.zip` (code+docs, excludes).
  - `enliterator:acceptance:verify[batch_id]`: run stage gates; print rubric; exit non‑zero on fail.
  - `meta_enliterator:run[full|micro]`: ensure EKN/resources; run Stages 1–8; run gates; print artifact paths.
  - `meta_enliterator:status`: summarize latest run (stage, duration, errors, gates, artifacts).
  - `ops:status`: Rails/SolidQueue/Neo4j/Redis/OpenAI health summary.
- Acceptance gates (aligned to CLAUDE.md)
  - Stage 1–2: each item has id + time + rights pointer; ambiguous rights → quarantine list.
  - Stage 3–4: canonical names present; verbs from allow‑list appear in path textization.
  - Stage 5: graph constraints exist; no orphans; duplicates resolved.
  - Stage 6: embeddings for repr_text + path_text exist; per‑EKN vector indexes exist; minimum coverage threshold met.
  - Retrieval eval: small smoke suite for groundedness/rights.
- Archival: micro/full runs and logs under `storage/ekns/{id}/batches/{batch_id}/exports/`.

## Implementation Plan
1) Bundler
- Deterministic file selection (seeded):
  - Micro: 10 files across `app/models`, `app/services`, `app/jobs`, key docs.
  - Full: repo code + docs, exclude `.git`, `node_modules`, `tmp`, `log`, `storage`.
- Zip with relative paths, store under `data/bundles/`.

2) Acceptance Gates
- Add `Acceptance::GateRunner` service: `run_all(batch_id) → { passed, checks:[{name,passed,details}], summary }`.
- Wire to `enliterator:acceptance:verify[batch_id]`.

3) One‑Shot Runner
- `meta_enliterator:run[full|micro]` flow:
  - Ensure/create EKN “Meta‑Enliterator”; ensure resources (Neo4j DB `ekn-{id}` + storage).
  - Ingest bundle → `enliterator:graph:sync` → `enliterator:embed:generate` → `enliterator:literacy:score` → `enliterator:deliverables:generate`.
  - Run `enliterator:acceptance:verify[batch_id]`; print PASS/FAIL and artifact paths; exit non‑zero on fail unless `FORCE=true`.

4) Ops/Status
- `ops:status` prints: Rails up, Solid Queue queues/failed/claimed, Neo4j `verify_connectivity`, Redis ping, OpenAI `SettingsManager.current_configuration`.

5) Dry Run → Full Run
- Micro first; fix gates; re‑run.
- Full bundle; fix any failures; iterate until PASS.

## Command Cheatsheet
- Build bundles: `bin/rails enliterator:bundle[micro]` or `enliterator:bundle[full]`
- Run Meta‑EKN: `bin/rails meta_enliterator:run[micro]` then `meta_enliterator:run[full]`
- Verify gates: `bin/rails enliterator:acceptance:verify[batch_id]`
- Status: `bin/rails meta_enliterator:status`, `bin/rails ops:status`

## First‑Hour Checklist (Next Session)
- Verify services: `bin/rails ops:status` (add if missing) and `rails runner 'puts Graph::Connection.instance.driver.verify_connectivity'`.
- Implement `enliterator:bundle[micro]` and `meta_enliterator:run[micro]` (scaffold only if time‑boxed).
- Run micro; inspect logs and acceptance rubric; capture failures as TODOs in issue #54.
- Implement `enliterator:acceptance:verify[batch_id]` and wire gates progressively.

## Pitfalls & Toggles
- Neo4j GenAI not available: Dev only → allow fallback; Prod → fail fast with diagnostic.
- GPT‑5: do not send `temperature` unless model supports it (extractions zero‑temp policy remains).
- Rights ambiguity: quarantine items and print a report; do not block entire batch unless policy set.

---

This plan is intentionally operational: it creates a single‑command path to a passing Meta‑EKN run, with checks and visibility to iterate quickly.
