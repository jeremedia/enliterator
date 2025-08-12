# 🔒 Database Backup - Quick Reference

## **PROTECT YOUR EXPENSIVE DATA!**

Previous Claude Code sessions cost $100+ by wiping databases after expensive OpenAI processing. **Always backup before risky operations.**

## Backup Commands

```bash
# Create backup (saves to /backups with timestamp)
rake enliterator:seed:backup

# List available backups
rake enliterator:seed:restore

# Restore from backup
rake enliterator:seed:restore[YYYYMMDD_HHMMSS]
```

## What Gets Backed Up

- **PostgreSQL**: 9+ MB - All processed documents, API calls, entities
- **Neo4j**: 1+ MB - Knowledge graph with relationships
- **README**: Restore instructions and database statistics

## When to Backup

✅ **BEFORE** any Claude Code session  
✅ **AFTER** successful pipeline completion  
✅ **BEFORE** database migrations or schema changes  
✅ **AFTER** expensive OpenAI processing (>$10 cost)  

## Backup Files Location

```
backups/
├── backup_YYYYMMDD_HHMMSS_README.txt     # Instructions
├── enliterator_dev_YYYYMMDD_HHMMSS.sql   # PostgreSQL  
└── neo4j_dev_YYYYMMDD_HHMMSS.cypher      # Neo4j graph
```

## Emergency Recovery

If database is accidentally wiped:

1. **DON'T PANIC** - Check if backup exists
2. `ls backups/` to see available backups
3. `rake enliterator:seed:restore[TIMESTAMP]` 
4. Follow PostgreSQL + Neo4j restore steps
5. Verify data integrity

## Full Documentation

See `/docs/DATABASE_BACKUP_SYSTEM.md` for complete details.

---

> **Remember**: 1 backup = $100+ saved in reprocessing costs!