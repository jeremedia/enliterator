# Start-of-Session Checklist

Read Order
- README.md → CLAUDE.md → AGENTS.md → docs/NEO4J.md → docs/PROJECT_STATUS.md

Run & Verify
- Dev server: `bin/dev` (port 3077; Foreman runs web, Tailwind, Solid Queue)
- Tests: `bin/rails test` and `bin/rails test:system`
- Neo4j health: `rails runner 'puts Graph::Connection.instance.driver.verify_connectivity'`

Pipeline Essentials
- Ingest: `bin/rails enliterator:ingest[path/to/bundle.zip]`
- Graph: `bin/rails enliterator:graph:sync[batch_id]`
- Embeddings (Neo4j GenAI): `bin/rails enliterator:embed:generate[batch_id]`
- Literacy: `bin/rails enliterator:literacy:score[batch_id]`
- Deliverables: `bin/rails enliterator:deliverables:generate[batch_id]`

Key Concepts
- Top-level unit: EKN (own Neo4j DB `ekn-{id}`) accumulating multiple ingest batches.
- Embeddings live in Neo4j GenAI (not pgvector). See `docs/NEO4J.md`.
- MCP tool implemented: `extract_and_link`; others are specified in CLAUDE.md.

Contributor Notes
- Follow AGENTS.md for structure, commands, style, tests, and PR guidance.
- Always start services via `bin/dev`. Use rights- and provenance-first patterns.
