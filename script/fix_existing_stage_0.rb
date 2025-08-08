#!/usr/bin/env ruby

puts "Fixing Stage 0 status for existing pipelines..."
puts "="*60
puts

# Find all pipelines that have started but don't have Stage 0 marked as completed
pipelines_to_fix = EknPipelineRun.where.not(status: 'initialized')
                                  .where("stage_statuses->>'initialized' IS NULL OR stage_statuses->>'initialized' != 'completed'")

puts "Found #{pipelines_to_fix.count} pipelines to fix"
puts

pipelines_to_fix.each do |pipeline|
  puts "Pipeline ##{pipeline.id} (EKN: #{pipeline.ekn.name})"
  puts "  Current status: #{pipeline.status}"
  puts "  Current stage: #{pipeline.current_stage} (#{pipeline.current_stage_number})"
  
  # Fix Stage 0 status
  pipeline.stage_statuses['initialized'] = 'completed'
  pipeline.save!
  
  puts "  ✅ Fixed Stage 0 status"
  puts
end

puts "All pipelines updated!"
puts

# Verify the fix
puts "Verification - Pipeline #37 stage statuses:"
pr = EknPipelineRun.find(37)
pr.stage_statuses.each do |stage, status|
  icon = case status
         when 'completed' then '✅'
         when 'failed' then '❌'
         when 'running' then '🔄'
         else '⏳'
         end
  puts "  #{stage}: #{icon} #{status || 'pending'}"
end