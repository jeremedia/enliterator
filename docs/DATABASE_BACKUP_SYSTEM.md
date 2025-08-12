# Database Backup System

> **CRITICAL FEATURE**: Protects expensive OpenAI-processed pipeline data from accidental loss

## Overview

The Enliterator Database Backup System provides comprehensive backup and restore functionality for both PostgreSQL and Neo4j databases. This system is **essential** for protecting valuable pipeline data that represents significant OpenAI processing costs.

## Why This Matters

**Cost Protection**: Arctic Research Navigator processing can cost $50-100+ in OpenAI API calls. Previous Claude Code sessions accidentally wiped databases containing this expensive processed data, requiring complete reprocessing and additional costs.

**Data Protection**: Each EKN pipeline run processes documents through 9 stages of AI analysis:
- Stage 1: Intake (file processing)
- Stage 2: Rights & Provenance 
- Stage 3: Lexicon Bootstrap (terminology extraction)
- Stage 4: Pools (Ten Pool Canon entity extraction) 
- Stage 5: Graph Assembly (Neo4j knowledge graph)
- Stage 6: Embeddings (vector representations)
- Stage 7: Literacy Scoring
- Stage 8: Deliverables Generation
- Stage 9: Knowledge Navigator Interface

**Recovery Capability**: Complete system recovery without reprocessing costs.

## Usage

### Creating Backups

```bash
# Create a timestamped backup of development databases
rake enliterator:seed:backup

# This creates:
# - backups/enliterator_dev_YYYYMMDD_HHMMSS.sql (PostgreSQL)
# - backups/neo4j_dev_YYYYMMDD_HHMMSS.cypher (Neo4j)  
# - backups/backup_YYYYMMDD_HHMMSS_README.txt (instructions)
```

### Restoring from Backup

```bash
# List available backups
rake enliterator:seed:restore

# Restore from specific timestamp
rake enliterator:seed:restore[20250811_232433]
```

### Checking Available Backups

```bash
ls backups/
# Shows:
# backup_20250811_232433_README.txt
# enliterator_dev_20250811_232433.sql  
# neo4j_dev_20250811_232433.cypher
```

## What Gets Backed Up

### PostgreSQL Database (9+ MB typical)
- **EKNs**: Knowledge Navigator configurations
- **IngestBatches**: Document collections and processing status
- **IngestItems**: Individual processed documents (25 PDFs for Arctic)
- **ApiCalls**: OpenAI API usage tracking with costs
- **Lexicon Entries**: Extracted canonical terminology (337 entries for Arctic)
- **Entity Data**: Ten Pool Canon entities (Ideas, Manifests, Experiences, etc.)
- **Pipeline Runs**: Processing history and results
- **User Data**: Admin users and configurations

### Neo4j Knowledge Graph (1+ MB typical)
- **Nodes**: Entities with labels (Idea, Manifest, Experience, etc.)
- **Relationships**: Connections between entities with properties
- **Embeddings**: Vector representations for semantic search
- **Graph Statistics**: Node/relationship counts and topology

## Backup File Structure

```
backups/
├── backup_20250811_232433_README.txt     # Restore instructions & stats
├── enliterator_dev_20250811_232433.sql   # PostgreSQL dump (9.23 MB)  
└── neo4j_dev_20250811_232433.cypher      # Neo4j export (1.6 MB)
```

## Safety Features

### Cost Protection Warnings
```bash
⚠️  WARNING: This will completely replace your current database!
📊 PostgreSQL backup: /path/to/backup.sql
🕸️  Neo4j backup: /path/to/backup.cypher

Type 'YES RESTORE DATABASE' to continue:
```

### Processing Cost Tracking
The README file includes:
```
CRITICAL: This backup contains processed data from 25 files
representing significant OpenAI processing costs. Handle with care!

Pipeline Status at backup:
- Latest Pipeline Run: #7 (completed)
- Current Stage: deliverables (9/9)
- EKN: Arctic Research Navigator
- Items Processed: 25
```

### Database Statistics
```
Database Statistics:
- EKNs: 1
- Ingest Batches: 1
- Ingest Items: 25
- API Calls: 184
- Lexicon Entries: 337
```

## Technical Implementation

### PostgreSQL Backup
- Uses `pg_dump` with proper connection parameters
- Handles Rails 8 multi-database configuration
- Creates complete schema + data dump
- Includes constraints, indexes, and foreign keys

### Neo4j Backup  
- Connects via Graph::Connection service
- Exports all nodes with labels and properties
- Exports relationships with start/end node references
- Creates executable Cypher statements for restore

### Error Handling
- Graceful fallback if Neo4j unavailable
- Database connection parameter validation
- File system error handling
- Clear error messages with troubleshooting steps

## Restore Process

### Automatic PostgreSQL Restore
1. Drops existing development database
2. Creates fresh database  
3. Imports schema and data from backup
4. Verifies restoration success

### Manual Neo4j Restore
1. Open Neo4j Browser (http://localhost:7474)
2. Select target database (e.g., `ekn-1`)
3. Clear existing data: `MATCH (n) DETACH DELETE n`
4. Load and execute backup Cypher file

## Best Practices

### When to Backup
- **Before major changes**: Database migrations, schema updates
- **After pipeline completion**: Successful processing of expensive data
- **Before Claude Code sessions**: Protect against accidental database wipes
- **Regular intervals**: Daily/weekly for active development

### Backup Retention
- Keep backups of completed pipeline runs indefinitely
- Archive older development backups after 30 days
- Store critical backups outside of project directory

### Recovery Testing
- Test restore process on separate development environment
- Verify data integrity after restoration
- Document any manual steps required

## Integration with Pipeline

### Automatic Backup Triggers
The backup system integrates with pipeline processing:

```ruby
# After successful pipeline completion
if pipeline_run.completed? && pipeline_run.literacy_score >= 70
  BackupJob.perform_later("post_pipeline_#{pipeline_run.id}")
end
```

### Cost-Based Backup Decisions
```ruby
# Backup if significant API costs incurred
total_cost = pipeline_run.api_calls.sum(:total_cost)
if total_cost > 10.0  # $10+ in processing costs
  BackupJob.perform_later("high_cost_#{pipeline_run.id}")
end
```

## Troubleshooting

### Common Issues

**PostgreSQL Authentication**
```bash
# If pg_dump fails with auth error
export PGPASSWORD="your_password"
rake enliterator:seed:backup
```

**Neo4j Connection Refused**
```bash
# Check Neo4j service status
systemctl status neo4j
# Or check Neo4j Desktop connection
```

**Insufficient Disk Space**
```bash
# Check available space before backup
df -h /Volumes/jer4TBv3/enliterator/backups
# Typical backup sizes: 10-50 MB total
```

### Backup Verification
```bash
# Verify PostgreSQL backup integrity
pg_restore --list backups/enliterator_dev_TIMESTAMP.sql

# Check Neo4j backup syntax
head -50 backups/neo4j_dev_TIMESTAMP.cypher
```

## Command Reference

```bash
# Create backup (full system)
rake enliterator:seed:backup

# List available backups  
rake enliterator:seed:restore

# Restore specific backup
rake enliterator:seed:restore[YYYYMMDD_HHMMSS]

# Check backup directory size
du -sh backups/

# Cleanup old backups (manual)
find backups/ -name "*.sql" -mtime +30 -delete
```

## Related Documentation

- [Database Protection Warning](DATABASE_PROTECTION_WARNING.md) - Prevention measures
- [Neo4j Configuration](NEO4J.md) - Graph database setup
- [Pipeline Architecture](enliterator_enliterated_dataset_literate_runtime_spec_v_1.md) - Processing stages
- [System Status Checks](SYSTEM_STATUS_CHECKS.md) - Monitoring procedures

## Security Considerations

### Data Sensitivity
- Backups may contain proprietary research documents
- API keys and credentials excluded from backups
- Consider encryption for production backups

### Access Control
- Limit backup directory access to authorized users
- Use environment-specific backup locations
- Implement backup retention policies

## Future Enhancements

### Planned Features
- **Automated scheduling**: Daily/weekly backup cron jobs
- **Cloud storage**: S3/Google Cloud backup destinations  
- **Incremental backups**: Delta changes only for large datasets
- **Backup verification**: Automated restore testing
- **Metrics integration**: Backup success/failure monitoring

### Performance Optimizations
- **Parallel processing**: PostgreSQL + Neo4j backups simultaneously
- **Compression**: Gzip backup files to reduce storage
- **Selective backup**: Choose specific EKNs or date ranges
- **Streaming**: Handle large datasets without memory limits

---

> **Remember**: This backup system exists because previous Claude Code sessions cost $100+ in reprocessing fees. Always backup before risky operations!