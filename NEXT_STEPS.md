# Next Steps - Quick Reference

## 1. Start Development Environment

```bash
# Copy environment file and add your OpenAI API key
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY

# Start all services
docker compose up -d

# Run database setup
bin/rails db:create
bin/rails db:migrate
bin/rails db:create:all
bin/rails db:schema:load:cache
bin/rails db:schema:load:queue
bin/rails db:schema:load:cable

# Start development server
bin/dev
```

## 2. Complete Model Implementation

Create remaining models in app/models/:
- `relational.rb`
- `evolutionary.rb` 
- `practical.rb`
- `emanation.rb`
- `lexicon_and_ontology.rb`
- `intent_and_task.rb`

Each should include:
- `include HasRights`
- `include TimeTrackable` (where appropriate)
- Associations via join tables
- Graph sync callbacks

## 3. Create Pipeline Jobs

In app/jobs/:
- `pipeline/base_job.rb` - Base class with error handling
- `ingest/bundle_processor_job.rb` - Stage 1
- `rights/triage_job.rb` - Stage 2
- `lexicon/bootstrap_job.rb` - Stage 3

## 4. Implement MCP Server

Create controllers in app/controllers/mcp/:
- `base_controller.rb` - Authentication, validation
- `tools_controller.rb` - Route to services
- Implement each tool as a service

## 5. Critical Files to Review

- `/docs/enliterator_enliterated_dataset_literate_runtime_spec_v_1.md` - The spec
- `CLAUDE.md` - Implementation instructions
- `/docs/GITHUB_PROJECT_PLAN.md` - Full project plan
- `/docs/PROGRESS_SUMMARY.md` - Current status

## Remember: Responses API is REQUIRED

All entity extraction MUST use:
```ruby
response = OPENAI.chat.completions.create(
  messages: messages,
  model: "gpt-4o-2024-08-06",
  response_format: {
    type: "json_schema",
    json_schema: {
      strict: true,  # REQUIRED
      schema: { ... }
    }
  },
  temperature: 0
)
```