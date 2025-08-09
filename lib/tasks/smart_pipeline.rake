# frozen_string_literal: true

namespace :pipeline do
  desc "Run smart pipeline with intelligent stage skipping"
  task :smart_run, [:batch_id, :force_stages, :skip_expensive, :dry_run] => :environment do |_t, args|
    batch_id = args[:batch_id]&.to_i
    force_stages = args[:force_stages]&.split(',')&.map(&:to_f) || []
    skip_expensive = args[:skip_expensive] == 'true'
    dry_run = args[:dry_run] == 'true'
    
    unless batch_id
      puts "Usage: rails pipeline:smart_run[batch_id]"
      puts "Options:"
      puts "  force_stages: Comma-separated stage numbers to force re-run (e.g., '4,6')"
      puts "  skip_expensive: Skip expensive stages (3,4,5.5,6) unless forced"
      puts "  dry_run: Show what would be done without executing"
      puts ""
      puts "Examples:"
      puts "  rails pipeline:smart_run[75]                    # Run with smart skipping"
      puts "  rails pipeline:smart_run[75,4,true,false]       # Force stage 4, skip other expensive"
      puts "  rails pipeline:smart_run[75,,true,true]         # Dry run, skip expensive"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    ekn = batch.ekn
    
    puts "=" * 80
    puts "Smart Pipeline Run for Batch ##{batch.id}: #{batch.name}"
    puts "EKN: #{ekn.name} (#{ekn.id})"
    puts "Options:"
    puts "  Force stages: #{force_stages.any? ? force_stages.join(', ') : 'none'}"
    puts "  Skip expensive: #{skip_expensive}"
    puts "  Dry run: #{dry_run}"
    puts "=" * 80
    puts
    
    runner = Pipeline::SmartRunner.new(
      ekn: ekn,
      batch: batch,
      options: {
        force_stages: force_stages,
        skip_expensive: skip_expensive,
        dry_run: dry_run
      }
    )
    
    results = runner.run_full_pipeline
    
    puts
    puts "=" * 80
    puts "Pipeline Results:"
    puts "=" * 80
    
    results.each do |stage_num, result|
      stage_name = StageCompletion::STAGES[stage_num][:name]
      expensive = StageCompletion::STAGES[stage_num][:expensive] ? " [EXPENSIVE]" : ""
      
      status_color = case result[:status]
      when 'completed' then "\e[32m" # Green
      when 'skipped', 'would_skip' then "\e[33m" # Yellow
      when 'failed' then "\e[31m" # Red
      else "\e[0m" # Default
      end
      
      puts "#{status_color}Stage #{stage_num} (#{stage_name})#{expensive}: #{result[:status]}\e[0m"
      
      if result[:reason]
        puts "  Reason: #{result[:reason]}"
      end
      
      if result[:metrics] && !result[:metrics].empty?
        puts "  Metrics: #{result[:metrics].to_json[0..200]}"
      end
      
      if result[:error]
        puts "  \e[31mError: #{result[:error]}\e[0m"
      end
      
      puts
    end
  end
  
  desc "Check what stages would be skipped without running"
  task :check_completion, [:batch_id] => :environment do |_t, args|
    batch_id = args[:batch_id]&.to_i
    
    unless batch_id
      puts "Usage: rails pipeline:check_completion[batch_id]"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    ekn = batch.ekn
    
    puts "Checking completion status for Batch ##{batch.id}: #{batch.name}"
    puts
    
    StageCompletion::STAGES.each do |stage_num, stage_info|
      completion = StageCompletion.find_or_initialize_by(
        ingest_batch: batch,
        ekn: ekn,
        stage_number: stage_num
      )
      completion.stage_name = stage_info[:name]
      
      can_skip = completion.can_be_skipped?
      expensive = stage_info[:expensive] ? " [EXPENSIVE]" : ""
      
      status_icon = if completion.status == 'completed'
        "✅"
      elsif can_skip
        "⏭️"
      else
        "❌"
      end
      
      puts "#{status_icon} Stage #{stage_num} (#{stage_info[:name]})#{expensive}"
      puts "   Status: #{completion.status || 'not run'}"
      puts "   Can skip: #{can_skip ? 'YES' : 'NO'}"
      
      if completion.completion_metrics.present?
        puts "   Metrics: #{completion.completion_metrics.to_json[0..150]}"
      end
      
      if can_skip && stage_info[:expensive]
        cost_saved = case stage_num
        when 4 then "$5-10" # Pool filling
        when 6 then "$2-5"  # Embeddings
        when 3 then "$1-2"  # Lexicon
        when 5.5 then "$3-5" # Relationships
        else "$0"
        end
        puts "   💰 Estimated cost saved by skipping: #{cost_saved}"
      end
      
      puts
    end
  end
  
  desc "Force re-run specific stage"
  task :force_stage, [:batch_id, :stage_number] => :environment do |_t, args|
    batch_id = args[:batch_id]&.to_i
    stage_number = args[:stage_number]&.to_f
    
    unless batch_id && stage_number
      puts "Usage: rails pipeline:force_stage[batch_id,stage_number]"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    ekn = batch.ekn
    
    runner = Pipeline::SmartRunner.new(ekn: ekn, batch: batch)
    result = runner.run_stage(stage_number, force: true)
    
    puts "Stage #{stage_number} result: #{result[:status]}"
    puts "Metrics: #{result[:metrics]}" if result[:metrics]
  end
  
  desc "Show cost analysis for batch processing"
  task :cost_analysis, [:batch_id] => :environment do |_t, args|
    batch_id = args[:batch_id]&.to_i
    
    unless batch_id
      puts "Usage: rails pipeline:cost_analysis[batch_id]"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    completions = batch.stage_completions
    
    puts "Cost Analysis for Batch ##{batch.id}: #{batch.name}"
    puts "=" * 60
    
    total_cost = 0
    total_calls = 0
    
    StageCompletion::STAGES.each do |stage_num, stage_info|
      next unless stage_info[:expensive]
      
      completion = completions.find { |c| c.stage_number == stage_num }
      
      if completion
        cost = completion.api_cost_usd || 0
        calls = completion.api_calls_made || 0
        
        total_cost += cost
        total_calls += calls
        
        status = completion.status == 'skipped' ? " (SKIPPED)" : ""
        
        puts "Stage #{stage_num} (#{stage_info[:name]})#{status}:"
        puts "  API Calls: #{calls}"
        puts "  Cost: $#{'%.4f' % cost}"
        
        if completion.status == 'skipped'
          puts "  💰 Cost saved by skipping!"
        end
      else
        puts "Stage #{stage_num} (#{stage_info[:name]}): Not run yet"
      end
      puts
    end
    
    puts "-" * 60
    puts "Total API Calls: #{total_calls}"
    puts "Total Cost: $#{'%.4f' % total_cost}"
    
    # Calculate potential savings
    skipped_stages = completions.select { |c| c.status == 'skipped' && c.expensive? }
    if skipped_stages.any?
      estimated_savings = skipped_stages.sum do |c|
        case c.stage_number
        when 4 then 7.50  # Pool filling average
        when 6 then 3.50  # Embeddings average
        when 3 then 1.50  # Lexicon average
        when 5.5 then 4.00 # Relationships average
        else 0
        end
      end
      
      puts
      puts "💰 Estimated savings from smart skipping: $#{'%.2f' % estimated_savings}"
    end
  end
end