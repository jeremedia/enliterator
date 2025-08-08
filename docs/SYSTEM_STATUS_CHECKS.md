# System Status Checks - Standard Operating Procedures

## Purpose
This document provides standardized procedures for checking Enliterator system status to prevent redundant checks and flailing.

## 1. Rails Server Status

### Check if Rails is running:
```bash
# Method 1: Check port binding (PREFERRED)
lsof -i :3077 | grep LISTEN

# Method 2: Check process (less reliable)
ps aux | grep "puma.*3077" | grep -v grep

# Method 3: Check PID file
cat tmp/pids/server.pid 2>/dev/null && ps -p $(cat tmp/pids/server.pid) > /dev/null && echo "Rails server is running" || echo "Rails server is NOT running"
```

### Access URLs:
- Development: https://e.dev.domt.app
- Mission Control: https://e.dev.domt.app/jobs
- Admin: https://e.dev.domt.app/admin

## 2. Solid Queue Status

### Check via database (MOST RELIABLE):
```bash
rails runner 'puts "SQ Processes: #{SolidQueue::Process.count}"; puts "Active Workers: #{SolidQueue::Process.where(kind: "Worker").count}"; puts "Jobs Ready: #{SolidQueue::ReadyExecution.count}"; puts "Jobs Failed: #{SolidQueue::FailedExecution.count}"'
```

### Check for stale processes:
```bash
rails runner 'stale = SolidQueue::Process.where("last_heartbeat_at < ?", 5.minutes.ago); puts "Stale processes: #{stale.count}"; stale.destroy_all if stale.any?'
```

### Quick job status:
```bash
rails runner 'puts "Ready: #{SolidQueue::ReadyExecution.count} | Failed: #{SolidQueue::FailedExecution.count} | Scheduled: #{SolidQueue::ScheduledExecution.count}"'
```

## 3. Pipeline Status

### Check active pipeline runs:
```bash
rails runner 'EknPipelineRun.where(status: ["running", "paused"]).each { |pr| puts "Run ##{pr.id}: #{pr.status} at stage #{pr.current_stage}" }'
```

### Check last pipeline run:
```bash
rails runner 'pr = EknPipelineRun.last; puts "Run ##{pr.id}: #{pr.status} (#{pr.current_stage}) - #{pr.error_message}"' 
```

## 4. Neo4j Status

### Check connection:
```bash
# Use centralized connection from neo4j.rb - see /docs/NEO4J.md
rails runner 'puts Graph::Connection.instance.driver.session.run("MATCH (n) RETURN count(n) as count").single[:count]'
```

### Quick health check:
```bash
rails runner script/check_neo4j_health.rb
```

## 5. Starting Services

### If Rails is NOT running:
```bash
# First, remove stale PID file if exists
rm -f tmp/pids/server.pid

# Then start services
bin/dev
```

### If Solid Queue workers are missing:
```bash
# Start just the worker
bundle exec rails solid_queue:start &

# Or restart everything
pkill -f solid_queue
sleep 2
bundle exec rails solid_queue:start &
```

## 6. Debugging Failed Jobs

### View last failed job error:
```bash
rails runner 'f = SolidQueue::FailedExecution.last; puts "Class: #{f.job.class_name}"; puts "Error: #{f.error["message"]}"'
```

### Retry all failed jobs:
```bash
rails runner 'SolidQueue::FailedExecution.all.each { |f| f.retry }'
```

### Clear all failed jobs:
```bash
rails runner 'SolidQueue::FailedExecution.destroy_all'
```

## 7. Common Issues

### "Server already running" error:
```bash
# Check if actually running
lsof -i :3077

# If not running, remove PID file
rm -f tmp/pids/server.pid

# Then start
bin/dev
```

### Multiple Solid Queue processes:
```bash
# This is NORMAL - Solid Queue uses supervisors, dispatchers, and workers
# Clean up stale processes only:
rails runner 'SolidQueue::Process.where("last_heartbeat_at < ?", 5.minutes.ago).destroy_all'
```

### Jobs not processing:
1. Check if workers exist: `rails runner 'puts SolidQueue::Process.where(kind: "Worker").count'`
2. Check for failed jobs: Access https://e.dev.domt.app/jobs
3. Check logs: `tail -f log/development.log | grep -i solid`

## 8. DO NOT DO

- ❌ Don't repeatedly run `bin/dev` without checking if services are running
- ❌ Don't kill all Solid Queue processes - multiple processes are normal
- ❌ Don't check using process names alone - use port checks or database status
- ❌ Don't assume no output means not running - use explicit checks

## 9. Standard Check Sequence

When debugging pipeline issues, run in this order:

```bash
# 1. Check Rails
lsof -i :3077 | grep LISTEN

# 2. Check Solid Queue
rails runner 'puts "Workers: #{SolidQueue::Process.where(kind: "Worker").count} | Ready: #{SolidQueue::ReadyExecution.count} | Failed: #{SolidQueue::FailedExecution.count}"'

# 3. Check last pipeline
rails runner 'pr = EknPipelineRun.last; puts "Run ##{pr.id}: #{pr.status} - #{pr.current_stage}"'

# 4. If jobs failed, check error
rails runner 'f = SolidQueue::FailedExecution.last; puts f.error["message"] if f'
```

This provides all critical information without redundant checks.