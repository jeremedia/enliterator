#!/usr/bin/env ruby

puts '=== RUNNING FIXED POOL EXTRACTION ==='
batch = IngestBatch.find(30)

# Reset failed items back to pending so they can be retried
failed_items = batch.ingest_items.where(pool_status: 'failed')
puts "Resetting #{failed_items.count} failed items to pending..."
failed_items.update_all(pool_status: 'pending')

puts "\n=== RUNNING POOL EXTRACTION JOB ==="
begin
  job = Pools::ExtractionJob.new
  result = job.perform(batch.id)
  puts "Pool extraction completed successfully!"
  
  # Check results
  completed_items = batch.ingest_items.where(pool_status: 'extracted')
  failed_items = batch.ingest_items.where(pool_status: 'failed')
  
  puts "\nResults:"
  puts "  Extracted: #{completed_items.count} items"
  puts "  Failed: #{failed_items.count} items"
  
  # Show sample failures if any
  if failed_items.any?
    puts "\nSample failure reasons:"
    failed_items.limit(3).each do |item|
      puts "  #{File.basename(item.file_path)}: #{item.pool_metadata&.dig('error')&.truncate(100)}"
    end
  end
  
  # Check created entities
  puts "\nEntity counts (last 5 minutes):"
  %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
    recent_count = pool.constantize.where('created_at >= ?', 5.minutes.ago).count
    puts "  #{pool}: #{recent_count} new entities"
  end
  
rescue => e
  puts "ERROR in pool extraction: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end