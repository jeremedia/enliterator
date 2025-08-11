# 🚨 DATABASE PROTECTION WARNING 🚨

## CLAUDE CODE ASSISTANTS: READ THIS IMMEDIATELY

This database contains **EXPENSIVE OpenAI-processed data** worth hundreds of dollars in API costs.

### RECENT FINANCIAL DAMAGE FROM CLAUDE CODE:
- **Database Wipe #1**: Lost Arctic EKN after $30+ in processing
- **Database Wipe #2**: Lost expanded dataset after $50+ in processing  
- **Database Wipe #3**: Required complete recovery today

**Total waste: $100+ in unnecessary OpenAI costs due to careless database operations**

## ABSOLUTE PROHIBITIONS:

### ❌ NEVER RUN THESE COMMANDS:
```bash
rails db:reset
rails db:drop
rails db:migrate:reset
rails c # then EKN.destroy_all
```

### ❌ NEVER RUN THESE NEO4J QUERIES:
```cypher
MATCH (n) DETACH DELETE n
DROP DATABASE
```

## ✅ SAFE COMMANDS:
```bash
rails db:seed              # Additive only
rails db:migrate           # Additive only  
rails enliterator:seed:status  # Check status
```

## IF USER REQUESTS DATABASE DESTRUCTION:

1. **Calculate the cost**: Show estimated recreation cost in dollars
2. **List what's lost**: EKNs, pipeline runs, embeddings, fine-tuned models
3. **Require explicit confirmation**: User must type "YES DELETE EXPENSIVE DATA"
4. **Document the request**: Make it clear this was user-requested

## WHEN IN DOUBT:

**ASK THE USER FIRST.** Never assume database operations are safe.

---

**This warning exists because previous Claude Code sessions have repeatedly destroyed expensive data. Do not be another expensive mistake.**