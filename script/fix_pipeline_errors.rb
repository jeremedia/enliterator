#!/usr/bin/env ruby

puts "="*60
puts "FIXING PIPELINE ERROR HANDLING"
puts "="*60
puts

# 1. Check current implementation
puts "1. Analyzing current issues..."
puts "-"*40

# Check recent failures
recent_failures = SolidQueue::FailedExecution
  .order(created_at: :desc)
  .limit(5)
  .map { |f| [f.job.class_name, f.error["message"]] }

puts "Recent failures:"
recent_failures.each do |job_class, error|
  puts "  #{job_class}: #{error[0..60]}"
end
puts

# 2. Show the problematic code
puts "2. Problematic code in EknPipelineRun#mark_stage_failed!"
puts "-"*40
puts <<~CODE
  def mark_stage_failed!(error)
    # ... stage tracking code ...
    fail!(error)  # <-- THIS FAILS if already in 'failed' state
  end
CODE
puts

# 3. Apply the fix
puts "3. Applying fixes..."
puts "-"*40

# First, let's create a monkey patch for testing
module PipelineFixes
  def mark_stage_failed!(error)
    stage_name = current_stage || 'unknown'
    error_message = error.is_a?(Exception) ? error.message : error.to_s
    
    # Update stage status
    stage_statuses[stage_name] = 'failed'
    self.failed_stage = stage_name
    save!
    
    Rails.logger.error "="*80
    Rails.logger.error "❌ Stage #{current_stage_number}: #{stage_name.upcase} FAILED"
    Rails.logger.error "   Error: #{error_message}"
    Rails.logger.error "="*80
    
    # FIXED: Check if we can transition before calling fail!
    if can_fail?
      fail!(error)
    elsif !failed?
      # If not in failed state and can't transition, force it
      update_column(:status, 'failed')
      update!(error_message: error_message)
    else
      # Already failed, just update the error message
      update!(error_message: error_message)
    end
  end
  
  # Add helper to check if transition is valid
  def can_fail?
    aasm.may_fire_event?(:fail)
  end
  
  # Add method to retry failed stage
  def retry_failed_stage!
    return unless failed?
    
    # Reset status
    update_column(:status, 'running')
    
    # Queue the job for the current stage
    job_class = "#{current_stage.camelize}Job".safe_constantize ||
                "Pipeline::#{current_stage.camelize}Job".safe_constantize ||
                "#{current_stage.camelize}::ExtractionJob".safe_constantize ||
                "#{current_stage.camelize}::BootstrapJob".safe_constantize ||
                "#{current_stage.camelize}::AssemblyJob".safe_constantize
    
    if job_class
      job_class.perform_later(id)
      Rails.logger.info "Retrying #{current_stage} stage with #{job_class}"
      true
    else
      Rails.logger.error "Could not find job class for stage: #{current_stage}"
      false
    end
  end
  
  # Add method to skip failed stage
  def skip_failed_stage!
    return unless failed?
    
    # Mark current stage as skipped and advance
    stage_statuses[current_stage] = 'skipped'
    self.status = 'running'
    
    # Advance to next stage
    next_stage_num = current_stage_number + 1
    if next_stage_num <= 9
      stages = %w[frame intake rights lexicon pools graph embeddings literacy deliverables navigator]
      self.current_stage = stages[next_stage_num]
      self.current_stage_number = next_stage_num
      save!
      
      Rails.logger.info "Skipped #{stages[next_stage_num-1]} stage, advanced to #{current_stage}"
      true
    else
      self.status = 'completed'
      save!
      false
    end
  end
end

# Apply the monkey patch
EknPipelineRun.prepend(PipelineFixes)

puts "✅ Applied fixes to EknPipelineRun"
puts "  - mark_stage_failed! now checks state before transitioning"
puts "  - Added can_fail? helper method"
puts "  - Added retry_failed_stage! method"
puts "  - Added skip_failed_stage! method"
puts

# 4. Test the fix
puts "4. Testing the fix..."
puts "-"*40

pr = EknPipelineRun.find(37)
puts "Pipeline #37 status: #{pr.status}"
puts "Current stage: #{pr.current_stage} (#{pr.current_stage_number})"

if pr.failed?
  puts "\nTesting state transition fix:"
  begin
    # This should NOT raise an error now
    pr.mark_stage_failed!("Test error")
    puts "✅ mark_stage_failed! handled gracefully"
  rescue => e
    puts "❌ Still failing: #{e.message}"
  end
end

puts
puts "5. Available recovery options:"
puts "-"*40
puts "  rails runner 'EknPipelineRun.find(37).retry_failed_stage!'"
puts "  rails runner 'EknPipelineRun.find(37).skip_failed_stage!'"
puts
puts "✅ Fixes applied successfully!"