#!/usr/bin/env ruby

pr = EknPipelineRun.find(37)
batch = pr.ingest_batch

puts "Pipeline ##{pr.id} - Current Stage #{pr.current_stage_number}: #{pr.current_stage}"
puts "Status: #{pr.status}"

# Define stages and check completion
stages = {
  1 => ["intake", batch.ingest_items.where.not(content: [nil, ""]).count == 10],
  2 => ["rights", batch.ingest_items.joins(:provenance_and_rights).distinct.count == 10],
  3 => ["lexicon", batch.ingest_items.where(lexicon_status: "extracted").count == 10],
  4 => ["pools", batch.ingest_items.where(pool_status: "extracted").count == 10],
  5 => ["graph", false],  # To be implemented
  6 => ["embeddings", false],  # To be implemented
  7 => ["literacy", false],  # To be implemented
  8 => ["deliverables", false],  # To be implemented
  9 => ["navigator", false]  # To be implemented
}

current = pr.current_stage_number
if stages[current][1]
  puts "\n✅ Stage #{current} complete!"
  
  # Fix status if failed
  if pr.status == "failed"
    pr.update_column(:status, "running")
    puts "Fixed status: failed → running"
  end
  
  # Advance to next stage
  next_stage = current + 1
  if next_stage <= 9
    pr.update!(
      current_stage: stages[next_stage][0],
      current_stage_number: next_stage
    )
    puts "Advanced to Stage #{next_stage}: #{stages[next_stage][0]}"
    
    # Queue the appropriate job
    case next_stage
    when 5
      Graph::AssemblyJob.perform_later(pr.id)
      puts "Queued Graph::AssemblyJob"
    when 6
      Embedding::RepresentationJob.perform_later(pr.id)
      puts "Queued Embedding::RepresentationJob"
    when 7
      Literacy::ScoringJob.perform_later(pr.id)
      puts "Queued Literacy::ScoringJob"
    when 8
      Deliverables::GenerationJob.perform_later(pr.id)
      puts "Queued Deliverables::GenerationJob"
    when 9
      puts "Stage 9 (Navigator) - Manual implementation needed"
    end
  else
    puts "Pipeline complete!"
    pr.update!(status: "completed")
  end
else
  puts "\n⏳ Stage #{current} not yet complete"
end