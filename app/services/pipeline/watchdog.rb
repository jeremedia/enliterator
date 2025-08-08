# frozen_string_literal: true

module Pipeline
  # Watchdog that monitors a pipeline run, attempts light-touch recovery,
  # and triggers acceptance when appropriate.
  class Watchdog
    POLL_SECONDS_DEFAULT = 15
    STUCK_MINUTES_DEFAULT = 20

    def initialize(run_id:, poll_seconds: POLL_SECONDS_DEFAULT, stuck_minutes: STUCK_MINUTES_DEFAULT, logger: Rails.logger)
      @run = EknPipelineRun.find(run_id)
      @poll_seconds = poll_seconds.to_i
      @stuck_minutes = stuck_minutes.to_i
      @logger = logger
    end

    def call
      loop do
        @run.reload
        log_status

        case @run.status
        when 'completed'
          run_acceptance
          break
        when 'failed'
          attempt_retry
        when 'running', 'retrying'
          attempt_unstick_if_needed
          trigger_stage_job_if_missing
        when 'paused'
          safe_log(:warn, 'Run is paused; waiting...')
        else
          safe_log(:warn, "Unknown status: #{@run.status}; waiting...")
        end

        sleep @poll_seconds
      end
    rescue ActiveRecord::RecordNotFound
      safe_log(:error, 'Pipeline run not found, stopping watchdog')
    end

    private

    def log_status
      safe_log(:info, "Run ##{@run.id} — #{@run.status} — stage #{@run.current_stage_number}/9 (#{@run.current_stage})")
    end

    def attempt_retry
      if can_retry?
        safe_log(:warn, 'Run failed; attempting retry via Orchestrator.resume')
        Pipeline::Orchestrator.resume(@run.id)
      else
        safe_log(:error, 'Run failed and cannot retry; manual intervention required')
      end
    rescue => e
      safe_log(:error, "Retry attempt failed: #{e.message}")
    end

    def attempt_unstick_if_needed
      if stage_stuck?
        safe_log(:warn, "Stage appears stuck (#{@run.stage_duration_minutes} min). Re-enqueuing stage job.")
        enqueue_current_stage_job
      end
    end

    def trigger_stage_job_if_missing
      # If no jobs in Ready/Claimed for this run and stage recently advanced, try to enqueue
      # Keep this conservative to avoid duplicate work.
      return unless recent_stage_change?
      return if any_stage_job_claimed_or_ready?

      safe_log(:info, 'No matching jobs found for current stage; enqueueing stage job')
      enqueue_current_stage_job
    rescue => e
      safe_log(:error, "Job presence check failed: #{e.message}")
    end

    def enqueue_current_stage_job
      job_class = job_class_for(@run.current_stage)
      if job_class
        if inline_mode?
          job_class.constantize.perform_now(@run.id)
          safe_log(:info, "Ran inline #{job_class}")
        else
          job_class.constantize.perform_later(@run.id)
          safe_log(:info, "Enqueued #{job_class}")
        end
      else
        safe_log(:warn, "No job class mapping for stage #{@run.current_stage}")
      end
    rescue => e
      safe_log(:error, "Failed to enqueue current stage job: #{e.message}")
    end

    def run_acceptance
      batch_id = @run.ingest_batch_id
      safe_log(:info, 'Running acceptance gates...')
      result = Acceptance::GateRunner.new(batch_id).run_all
      summary = result[:summary]
      passed = result[:passed]
      safe_log(passed ? :info : :error, summary)
      result[:checks].each do |c|
        mark = c[:passed] ? '✅' : '❌'
        safe_log(:info, "#{mark} #{c[:name]}")
      end
    rescue => e
      safe_log(:error, "Acceptance check failed: #{e.message}")
    end

    def job_class_for(stage)
      # Prefer the mapping in EknPipelineRun if available
      mapping = {
        'intake'      => 'Pipeline::IntakeJob',
        'rights'      => 'Rights::TriageJob',
        'lexicon'     => 'Lexicon::BootstrapJob',
        'pools'       => 'Pools::ExtractionJob',
        'graph'       => 'Graph::AssemblyJob',
        'embeddings'  => 'Embedding::RepresentationJob',
        'literacy'    => 'Literacy::ScoringJob',
        'deliverables'=> 'Deliverables::GenerationJob'
      }
      mapping[stage.to_s]
    end

    def any_stage_job_claimed_or_ready?
      class_name = job_class_for(@run.current_stage)
      return false unless class_name
      arg = @run.id.to_s
      SolidQueue::ReadyExecution.joins(:job).where(solid_queue_jobs: { class_name: class_name })
                                 .where("solid_queue_jobs.arguments LIKE ?", "%\"#{arg}\"")
                                 .exists? ||
        SolidQueue::ClaimedExecution.joins(:job).where(solid_queue_jobs: { class_name: class_name })
                                     .where("solid_queue_jobs.arguments LIKE ?", "%\"#{arg}\"")
                                     .exists?
    rescue NameError
      # SolidQueue tables not present in some contexts
      false
    end

    def recent_stage_change?
      # If stage started within 2 minutes, allow enqueue if no job found
      return false unless @run.stage_started_at
      (Time.current - @run.stage_started_at) < 120
    end

    def stage_stuck?
      @run.running? && @run.stage_started_at && @run.stage_duration_minutes >= @stuck_minutes
    end

    def can_retry?
      @run.respond_to?(:can_retry?) ? @run.can_retry? : true
    end

    def safe_log(level, msg)
      @logger.send(level, "[Watchdog ##{@run.id}] #{msg}")
    end

    def inline_mode?
      ActiveModel::Type::Boolean.new.cast(ENV['PIPELINE_INLINE']) || Rails.env.test?
    end
  end
end
