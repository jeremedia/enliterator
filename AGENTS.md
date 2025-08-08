# Repository Guidelines

## Architecture Overview
- Product: Enliterated Knowledge Navigators (EKNs) — persistent, conversational interfaces to datasets.
- Pipeline: Stages 0–9 with Stage 5 Neo4j graph assembly and Stage 6 embeddings via Neo4j GenAI (unified vectors + graph).
- Services: Postgres (ops), Neo4j per EKN (`ekn-{id}`), Redis, OpenAI Responses + Structured Outputs.
- References: See `CLAUDE.md` (top-level spec) and `docs/NEO4J.md` (single source of truth for graph).

## Project Structure & Module Organization
- Code: `app/` (controllers, models, views, jobs, services/*), `lib/`, `config/`.
- Data & DB: `db/`, `storage/`, `data/`.
- Frontend: `app/javascript/`, `app/assets/` (Tailwind), `public/`.
- Tests: primary in `test/` (Minitest); experimental `spec/` exists but is secondary.
- Docs & Prompts: `docs/`, `agents/`, `prompts/`.
- Scripts: `bin/` (e.g., `bin/dev`, `bin/setup`, `bin/rails`).

## Build, Test, and Development Commands
- Setup: `bundle install` then `bin/setup` (db, dependencies). 
- Run dev: `bin/dev` (Foreman using `Procfile.dev`: web, tailwind, worker). Opens on port 3077.
- Migrate: `bin/rails db:create db:migrate`.
- Pipeline ops (examples): `bin/rails enliterator:ingest[path/to/data.zip]`, `bin/rails enliterator:graph:sync`.
- Tests (Minitest): `bin/rails test`, `bin/rails test:system`, or `bin/rails test test/services/**/*_test.rb`.

## Coding Style & Naming Conventions
- Ruby style: RuboCop Rails Omakase (`.rubocop.yml`). Run `bundle exec rubocop`.
- Indentation: 2 spaces; lines ≤ 100–120 chars where practical.
- Naming: classes `CamelCase`, methods/variables `snake_case`, constants `SCREAMING_SNAKE_CASE`.
- Views/partials: use descriptive names (`_card.html.erb`), helpers in `app/helpers/`.

## Testing Guidelines
- Framework: Minitest in `test/` with `_test.rb` naming. Keep tests fast and deterministic.
- System tests: `bin/rails test:system` for end‑to‑end UI.
- RSpec: `spec/` exists; prefer Minitest unless extending existing specs. Name with `_spec.rb`.
- Coverage: SimpleCov is available; enable in `test/test_helper.rb` if adding coverage gates.

## Commit & Pull Request Guidelines
- Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, etc. (see recent history).
- PRs: concise description, linked issues, screenshots for UI, migration notes if any, and test coverage notes.
- Scope: one logical change per PR; include migration + rollback instructions when altering schema.

## Security & Configuration Tips
- Secrets: use `.env`/`.env.example`; never commit real keys. OpenAI settings are managed via Admin UI.
- Neo4j/Postgres/Redis: see `docs/` for service config; Docker Compose is available (`docker compose up -d`).
