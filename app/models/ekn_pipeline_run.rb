# frozen_string_literal: true

# == Schema Information
#
# Table name: ekn_pipeline_runs
#
#  id                          :bigint           not null, primary key
#  ekn_id                      :bigint           not null
#  ingest_batch_id             :bigint           not null
#  status                      :string           default("initialized"), not null
#  current_stage               :string
#  current_stage_number        :integer          default(0)
#  stage_statuses              :jsonb
#  stage_metrics               :jsonb
#  stage_started_at            :datetime
#  stage_completed_at          :datetime
#  started_at                  :datetime
#  completed_at                :datetime
#  total_items_processed       :integer          default(0)
#  total_nodes_created         :integer          default(0)
#  total_relationships_created :integer          default(0)
#  literacy_score              :float
#  failed_stage                :string
#  error_message               :text
#  error_details               :jsonb
#  retry_count                 :integer          default(0)
#  last_retry_at               :datetime
#  options                     :jsonb
#  auto_advance                :boolean          default(TRUE)
#  skip_failed_items           :boolean          default(FALSE)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
# Indexes
#
#  index_ekn_pipeline_runs_on_current_stage          (current_stage)
#  index_ekn_pipeline_runs_on_ekn_id                 (ekn_id)
#  index_ekn_pipeline_runs_on_ekn_id_and_created_at  (ekn_id,created_at)
#  index_ekn_pipeline_runs_on_ekn_id_and_status      (ekn_id,status)
#  index_ekn_pipeline_runs_on_ingest_batch_id        (ingest_batch_id)
#  index_ekn_pipeline_runs_on_status                 (status)
#
class EknPipelineRun < ApplicationRecord
  include AASM
  include Loggable
  
  belongs_to :ekn
  belongs_to :ingest_batch
  
  # Pipeline stages in order (0-9)
  PIPELINE_STAGES = {
    0 => { name: 'initialized', job: nil, description: 'Frame the mission - Configuration and goal setting' },
    1 => { name: 'intake', job: 'Pipeline::IntakeJob', description: 'Bundle discovery and file processing' },
    2 => { name: 'rights', job: 'Rights::TriageJob', description: 'Rights assignment and quarantine' },
    3 => { name: 'lexicon', job: 'Lexicon::BootstrapJob', description: 'Term extraction and canonical forms' },
    4 => { name: 'pools', job: 'Pools::ExtractionJob', description: 'Ten Pool Canon entity extraction' },
    5 => { name: 'graph', job: 'Graph::AssemblyJob', description: 'Neo4j knowledge graph construction' },
    6 => { name: 'embeddings', job: 'Embedding::RepresentationJob', description: 'Generate vector embeddings' },
    7 => { name: 'literacy', job: 'Literacy::ScoringJob', description: 'Calculate enliteracy score' },
    8 => { name: 'deliverables', job: 'Deliverables::GenerationJob', description: 'Generate export artifacts' },
    9 => { name: 'fine_tuning', job: 'FineTune::DatasetBuilderJob', description: 'Build fine-tuning dataset' }
  }.freeze
  
  # State machine for overall pipeline
  aasm column: :status do
    state :initialized, initial: true
    state :running
    state :paused
    state :completed
    state :failed
    state :retrying
    state :cancelled
    
    event :start do
      transitions from: [:initialized, :paused, :failed], to: :running
      after do
        update!(started_at: Time.current) if started_at.nil?
        
        # Mark Stage 0 (initialized/frame) as completed since we're starting
        stage_statuses['initialized'] = 'completed'
        save!
        
        log_info("🚀 PIPELINE STARTED for EKN: #{ekn.name}", label: "pipeline")
        advance_to_next_stage!
      end
    end
    
    event :pause do
      transitions from: :running, to: :paused
      after do
        log_warn("⏸️ Pipeline paused at stage #{current_stage}", label: "pipeline")
      end
    end
    
    event :complete do
      transitions from: :running, to: :completed
      after do
        update!(completed_at: Time.current)
        calculate_final_metrics!
        log_info("🎉 PIPELINE COMPLETE! Duration: #{duration_so_far}s, Score: #{literacy_score}", label: "pipeline")
        notify_completion!
      end
    end
    
    event :fail do
      transitions from: [:running, :retrying], to: :failed
      after do |error|
        update!(
          error_message: error.message,
          error_details: { 
            backtrace: error.backtrace&.first(10),
            stage: current_stage,
            timestamp: Time.current
          }
        )
        log_error("💥 Pipeline failed: #{error.message}", label: "errors")
        notify_failure!
      end
    end
    
    event :retry_pipeline do
      transitions from: :failed, to: :retrying, guard: :can_retry?
      after do
        increment!(:retry_count)
        update!(last_retry_at: Time.current)
        log_info("🔄 Retrying pipeline from stage #{current_stage} (attempt #{retry_count})", label: "pipeline")
        resume_from_failed_stage!
      end
    end
    
    event :cancel do
      transitions from: [:running, :paused, :retrying, :initialized], to: :cancelled
      after do
        log_warn("⛔ Pipeline cancelled at stage #{current_stage}", label: "pipeline")
        cancel_pending_jobs!
        notify_cancellation!
      end
    end
  end
  
  # Guard methods
  def can_retry?
    retry_count < 3
  end
  
  # Stage progression methods
  def advance_to_next_stage!
    next_stage_num = current_stage_number + 1
    
    if next_stage_num > 9
      log_info("✅ All stages complete, finishing pipeline", label: "pipeline")
      complete!
      return
    end
    
    stage_info = PIPELINE_STAGES[next_stage_num]
    
    log_info("🚀 Advancing to Stage #{next_stage_num}: #{stage_info[:name].upcase}", label: "pipeline")
    log_debug("Description: #{stage_info[:description]}", label: "stage_#{next_stage_num}")
    
    update!(
      current_stage: stage_info[:name],
      current_stage_number: next_stage_num,
      stage_started_at: Time.current
    )
    
    # Record stage start
    stage_statuses[stage_info[:name]] = 'running'
    save!
    
    # Queue or run the job for this stage
    if stage_info[:job].present?
      job_class = stage_info[:job].constantize

      if inline_mode?
        log_info("Running job inline: #{stage_info[:job]}", label: "stage_#{next_stage_num}")
        # Run synchronously in-process. The job's BaseJob wrapper will
        # mark stage completion and auto-advance if configured.
        job_class.perform_now(self.id)
      else
        log_info("Queuing job: #{stage_info[:job]}", label: "stage_#{next_stage_num}")
        # Queue the job and verify it was created
        job = job_class.perform_later(self.id)

        # Verify job was actually created in database
        if job && job.job_id
          log_info("Job queued successfully with ID: #{job.job_id}", label: "stage_#{next_stage_num}")

          # Double-check job exists in Solid Queue
          if defined?(SolidQueue::Job)
            queue_job = SolidQueue::Job.where("arguments LIKE ?", "%#{job.job_id}%").first
            if queue_job
              log_debug("Verified job in queue: #{queue_job.class_name}", label: "stage_#{next_stage_num}")
            else
              log_warn("⚠️ Job #{job.job_id} not found in Solid Queue!", label: "errors")
            end
          end
        else
          log_error("❌ Failed to queue job for stage #{next_stage_num}!", label: "errors")
          fail!("Failed to queue job: #{stage_info[:job]}")
        end
      end
    end
    
    broadcast_stage_change!
  end

  # Prefer explicit env flag to avoid guessing worker state
  def inline_mode?
    # Run synchronously when PIPELINE_INLINE is truthy or in test
    ActiveModel::Type::Boolean.new.cast(ENV["PIPELINE_INLINE"]) || Rails.env.test?
  end
  
  def mark_stage_complete!(metrics = {})
    # Calculate duration if stage_started_at is set
    duration = if stage_started_at
      (Time.current - stage_started_at).round(2)
    else
      0 # If no start time, assume instant completion
    end
    stage_name = current_stage
    
    # Log completion with metrics
    log_info("✅ Stage COMPLETED in #{duration}s", label: "stage_#{current_stage_number}")
    log_debug("Metrics: #{metrics.to_json}", label: "stage_#{current_stage_number}")
    
    # Record completion
    stage_statuses[stage_name] = 'completed'
    stage_metrics[stage_name] = metrics.merge(duration: duration)
    self.stage_completed_at = Time.current
    save!
    
    # Log summary
    Rails.logger.info "=" * 80
    Rails.logger.info "✅ Stage #{current_stage_number}: #{stage_name&.upcase || 'UNKNOWN'} COMPLETED"
    Rails.logger.info "   Duration: #{duration}s"
    Rails.logger.info "   Metrics: #{metrics.to_json}"
    Rails.logger.info "=" * 80
    
    # Auto-advance if enabled
    if auto_advance
      advance_to_next_stage!
    else
      log_info("Auto-advance disabled, pausing pipeline", label: "pipeline")
      pause!
    end
  end
  
  def mark_stage_failed!(error)
    stage_name = current_stage
    
    # Log the failure
    log_error("❌ Stage FAILED: #{error.message}", label: "stage_#{current_stage_number}")
    log_debug("Backtrace: #{error.backtrace&.first(5)&.join("\n")}", label: "errors")
    
    stage_statuses[stage_name] = 'failed'
    self.failed_stage = stage_name
    save!
    
    Rails.logger.error "=" * 80
    Rails.logger.error "❌ Stage #{current_stage_number}: #{stage_name.upcase} FAILED"
    Rails.logger.error "   Error: #{error.message}"
    Rails.logger.error "=" * 80
    
    # FIXED: Check if we can transition before calling fail!
    if aasm.may_fire_event?(:fail)
      fail!(error)
    elsif !failed?
      # If not in failed state and can't transition, force it
      update_column(:status, 'failed')
      update!(error_message: error.is_a?(Exception) ? error.message : error.to_s)
    else
      # Already failed, just update the error message
      update!(error_message: error.is_a?(Exception) ? error.message : error.to_s)
    end
  end
  
  # Observable status for monitoring
  def detailed_status
    {
      id: id,
      ekn_id: ekn_id,
      ekn_name: ekn.name,
      batch_id: ingest_batch_id,
      status: status,
      current_stage: current_stage,
      stage_number: "#{current_stage_number}/9",
      progress_percentage: (current_stage_number / 9.0 * 100).round,
      stages_completed: stage_statuses.select { |_, v| v == 'completed' }.keys,
      stages_failed: stage_statuses.select { |_, v| v == 'failed' }.keys,
      duration_seconds: duration_so_far,
      metrics: aggregate_metrics,
      can_resume: failed? && can_retry?,
      next_action: suggested_next_action
    }
  end
  
  # Agent-friendly monitoring methods
  def current_stage_logs(limit: 10)
    find_or_create_log("stage_#{current_stage_number}")
      .log_items
      .last(limit)
      .map(&:text)
  end
  
  def latest_activity
    logs.flat_map(&:log_items)
        .sort_by(&:created_at)
        .last(5)
        .map { |item| "[#{item.log.label}] #{item.text}" }
  end
  
  def has_errors?
    find_or_create_log("errors").log_items.any?
  end
  
  def error_summary
    return nil unless has_errors?
    
    find_or_create_log("errors").log_items.map(&:text).join("\n")
  end
  
  def agent_status
    {
      run_id: id,
      status: status,
      current_stage: "#{current_stage_number}/9 - #{current_stage}",
      progress: "#{(current_stage_number / 9.0 * 100).round}%",
      duration: duration_so_far,
      latest_logs: latest_activity,
      has_errors: has_errors?,
      error_summary: error_summary,
      next_action: suggested_next_action
    }
  end
  
  def duration_so_far
    return 0 unless started_at
    ((completed_at || Time.current) - started_at).round(2)
  end
  
  def aggregate_metrics
    {
      items_processed: total_items_processed,
      nodes_created: total_nodes_created,
      relationships_created: total_relationships_created,
      literacy_score: literacy_score,
      stage_metrics: stage_metrics
    }
  end
  
  def suggested_next_action
    case status
    when 'initialized'
      "Run: EknPipelineRun.find(#{id}).start!"
    when 'paused'
      "Run: EknPipelineRun.find(#{id}).start!"
    when 'failed'
      if can_retry?
        "Run: EknPipelineRun.find(#{id}).retry_pipeline!"
      else
        "Max retries reached. Manual intervention required."
      end
    when 'running'
      if stage_stuck?
        "⚠️ Stage appears stuck! Consider cancelling and restarting. Stage running for #{stage_duration_minutes} minutes."
      else
        "Monitoring... Current stage: #{current_stage}"
      end
    when 'completed'
      "Pipeline complete! Literacy score: #{literacy_score}"
    when 'cancelled'
      "Pipeline was cancelled. Start a new run to process this EKN."
    else
      "Unknown status"
    end
  end
  
  def stage_stuck?
    return false unless running? && stage_started_at
    
    # Consider stage stuck if running for more than 30 minutes
    stage_duration_minutes > 30
  end
  
  def stage_duration_minutes
    return 0 unless stage_started_at
    ((Time.current - stage_started_at) / 60).round
  end
  
  private
  
  def broadcast_stage_change!
    # Broadcast to ActionCable for real-time updates (if configured)
    # ActionCable.server.broadcast(
    #   "pipeline_run_#{id}",
    #   detailed_status
    # )
    
    # For now, just log the change
    Rails.logger.info "Broadcasting stage change: #{current_stage}"
  end
  
  def notify_completion!
    Rails.logger.info "🎉 PIPELINE COMPLETE for EKN #{ekn.name}!"
    Rails.logger.info detailed_status.to_json
    
    # Could send email, Slack notification, etc.
  end
  
  def notify_failure!
    Rails.logger.error "💥 PIPELINE FAILED for EKN #{ekn.name}"
    Rails.logger.error detailed_status.to_json
    
    # Could send alerts
  end
  
  def notify_cancellation!
    Rails.logger.info "⛔ PIPELINE CANCELLED for EKN #{ekn.name}"
    Rails.logger.info detailed_status.to_json
    
    # Could send notifications
  end
  
  def cancel_pending_jobs!
    # Cancel any pending jobs for this pipeline run
    job_count = 0
    
    # Find all jobs with this pipeline run ID in arguments
    begin
      SolidQueue::Job.where('arguments LIKE ?', "%\"#{id}\"%").each do |job|
        unless job.finished?
          Rails.logger.info "Cancelling job #{job.id} (#{job.class_name})"
          job.destroy
          job_count += 1
        end
      end
      
      log_info("Cancelled #{job_count} pending jobs", label: "pipeline")
    rescue => e
      log_error("Error cancelling jobs: #{e.message}", label: "errors")
    end
  end
  
  def resume_from_failed_stage!
    # Resume from the failed stage
    stage_info = PIPELINE_STAGES[current_stage_number]
    
    log_info("Resuming from stage #{current_stage_number}: #{stage_info[:name]}", label: "pipeline")
    
    # Reset stage status to running
    stage_statuses[current_stage] = 'running'
    self.stage_started_at = Time.current
    save!
    
    # Queue the job again
    if stage_info[:job].present?
      job_class = stage_info[:job].constantize
      job_class.perform_later(self.id)
    end
  end
  
  def calculate_final_metrics!
    # Aggregate all metrics from the pipeline
    self.total_nodes_created = ekn.total_nodes
    self.total_relationships_created = ekn.total_relationships
    self.literacy_score = ingest_batch.literacy_score || 0
    self.total_items_processed = ingest_batch.ingest_items.count
    save!
  end
end
