# Epic: Navigator Vertical Slice (Stage 9 Thin Slice)

A minimal but real slice of the **Knowledge Navigator**: entity cards, edge inspector, and an ask view that returns **path sentences with citations** and a **rights echo**. Grounded in the Spec v1.2 delivery rules and closed verb glossary; emphasizes **show your work** and rights.

## Definition of Done
- Entity Card: shows repr_text, grouped edges by **canonical verb**, and **one-sentence path** for Verified edges with citations + rights echo
- Edge Inspector: Candidate vs Verified management (Promote/Reject) with provenance fields and rights check
- Ask View: answers top-50 with path sentences where possible; otherwise states gaps and minimal next intake (spec "Only-if-blocked interactions")
- Whole-graph metrics posted to issue: answerability on top-50, mean degree, LCC coverage %, verb diversity (Verified), rights incidents = 0
- CI: Creation parity preflight still enforced before discovery runs

## Tasks
- [ ] Scaffold routes/controllers/views for Entity Card, Edge actions, and Ask
- [ ] Add minimal **NavigatorService** to fetch/format paths + rights echo
- [ ] Wire **RelationshipManager** Promote/Reject API; require rights check
- [ ] Group edges by **canonical verb** (closed glossary) and show path sentences
- [ ] Add "top-50" YAML and answerability test; post results
- [ ] Add tiny **Graph/Timeline** stubs (optional) to prove modality switching
- [ ] Post a demo GIF/screencap + metrics to this issue

## Architecture

### Routes
```ruby
namespace :navigator do
  resources :entities, only: :show
  resources :edges, only: [] do
    member do
      post :promote
      post :reject
    end
  end
  get "ask", to: "ask#show"
end
```

### Core Services
- **NavigatorService**: Handles path queries, textization, rights echo
- **RelationshipManager**: Manages two-tier edge promotion/rejection with rights checks
- **NodeLocator**: Resolves nodes by ID with pool detection

### Views
1. **Entity Card** (`/navigator/entities/:id`)
   - Display repr_text and pool
   - Group edges by canonical verb
   - Show path sentences for Verified edges
   - Provide Promote/Reject actions for Candidate edges

2. **Edge Inspector** (embedded in Entity Card)
   - List all edges with status (Candidate/Verified)
   - Show evidence, confidence, provenance
   - Enable curation with rights validation

3. **Ask View** (`/navigator/ask`)
   - Answer top-50 questions with path sentences
   - Show citations and rights echo
   - Provide fallback for unanswerable questions

## Metrics Tracking
- Answerability rate on top-50 questions
- Mean degree (whole graph)
- LCC coverage percentage
- Verb diversity (Verified edges only)
- Rights compliance (zero incidents)

## Success Criteria
- At least 15/50 questions answerable with valid path sentences
- Mean degree ≥ 0.3 maintained
- All promoted edges have valid rights checks
- Path sentences follow spec textization rules
- Citations properly linked to source items