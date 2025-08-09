# Epic: Stage 5.5 Relationship Discovery (construction first plan)

This epic is the single source of truth for plan and progress. It is kept in sync with a GitHub issue and updated as tasks are completed. Grounded in: Status Report, Continuation Prompt, Redesign, Project Status, Spec v1.2, README.

## Definition of Done
- Discovered edges write reliably (parity 100 percent for a test run).
- Two tier edges (Candidate vs Verified) with confidence and provenance stored on relationships.
- Gates met:
  - Mean degree ≥ 0.3 trending to ≥ 1.0
  - Largest connected component coverage ≥ 70 percent
  - Verb diversity ≥ 5 glossary verbs beyond co_occurs_with
  - Answerability: ≥ 60 percent of top 50 questions produce a valid path sentence with citations
- Navigator slice ships: entity cards with path sentences, edge inspector with promote to Verified, rights echo in responses.

## Tasks
### A) Reconcile and freeze pipeline shape
- [ ] Insert Stage 5.5 into docs and code comments. Align Stage 6 as Representation and retrieval indices per spec.
- [ ] Remove any Stage 4 relationship work. Stage 4 is entity extraction only.
- [ ] Rewrite PROJECT_STATUS.md and Status Report sections that mislabel Stage 6.

### B) Make creation reliable before discovery volume
- [ ] Implement Graph::NodeLocator (single source for node lookup and labels).
- [ ] Refactor create_graph_relationship to route through NodeLocator and to use canonical ids per pool. Verify parity discovered vs created on a small batch.
- [ ] Add tests and a rails runner script that prints discovered vs created counts.

### C) Two tier edge model and provenance
- [ ] Relationship properties: status: "candidate" or "verified", confidence: float, discovered_by: symbol, evidence_snippet: string, evidence_item_id: int, created_at.
- [ ] Write type using the VERB_GLOSSARY canonical verb. Store reverse names only if the schema requires.
- [ ] Path textization stored for each Verified edge's minimal path where available.

### D) Stage 5.5 multi pass discovery (construction)
- [ ] Pass A: Co occurrence scaffolding (symmetric, low confidence, Candidate).
- [ ] Pass B: Embedding led clustering using Neo4j GenAI vectors, discover with glossary verbs, attach provenance sentences.
- [ ] Pass C: Graph topology expansion from high centrality nodes (expand k nearest in vector space, attempt bridges).
- [ ] Pass D: Static analyzers for code sources (imports, inheritance, calls) mapped to glossary verbs. Mark as Verified when evidence is structural.
- [ ] Pass E: Human in the loop curation in UI to promote or reject Candidate edges.

### E) Metrics and gates
- [ ] Add script/metrics/graph_gates.rb to compute mean degree, LCC coverage, verb diversity, answerability sample. Wire a Rails task that fails if gates are red.
- [ ] Add script/metrics/show_parity.rb to assert discovered == created before running heavy discovery.

### F) Navigator vertical slice (Stage 9 starter)
- [ ] Entity card view that shows path sentences and citations and rights echo.
- [ ] Edge inspector that lists Candidate vs Verified edges with confidence and sources plus one click Promote to Verified.
- [ ] Result modes: graph view, timeline view, simple table.

### G) Documentation and governance
- [ ] One pipeline diagram and one glossary in docs, remove older misaligned text.
- [ ] Keep this epic updated as tasks complete. Cross link commits and PRs.

## Useful queries and commands

### Rails runner snippets
# Count nodes and relationships (excluding HAS_RIGHTS)
rails runner 'ekn = IngestBatch.last.ekn; s = Graph::Connection.instance.driver.session(database: ekn.neo4j_database_name); s.read_transaction {|tx| puts tx.run("MATCH (n) RETURN count(n) AS n UNION ALL MATCH ()-[r]->() WHERE type(r) <> \"HAS_RIGHTS\" RETURN count(r) AS r").to_a }'

# Run Stage 5.5 once
rails runner 'run = EknPipelineRun.create!(status: "running", current_stage: "relationships", current_stage_number: 5.5, stage_statuses: {"relationships" => "running"}, ingest_batch: IngestBatch.last, ekn: IngestBatch.last.ekn); Graph::RelationshipDiscoveryJob.perform_now(run.id)'

# Tail failures
rails runner 'SolidQueue::FailedExecution.order(created_at: :desc).limit(5).each { |f| puts "#{f.job.class_name}: #{f.error["message"]}" }'

### Cypher hints (example)
# Average out degree (rough) excluding HAS_RIGHTS
# MATCH ()-[r]->() WHERE type(r) <> "HAS_RIGHTS" RETURN toFloat(count(r)) / toFloat(count(DISTINCT startNode(r))) AS avg_out_degree;