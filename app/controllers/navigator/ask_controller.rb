class Navigator::AskController < ApplicationController
  def show
    @ekn = Ekn.find_by!(slug: params[:ekn_slug])

    unless @ekn
      render plain: "No EKN found", status: :not_found
      return
    end

    # Get EKN stats for display
    @batch = @ekn.ingest_batches.last
    @ekn_stats = calculate_ekn_stats

    q = params[:question].presence || params[:q].presence

    if q
      # Queue background job for OpenAI processing if not cached
      @question = q
      @mode = params[:mode] || "conversation"
      
      # Check if we have a cached answer
      cache_key = "ask_answer:#{@ekn.slug}:#{Digest::MD5.hexdigest(q)}:#{@mode}"
      @answer = Rails.cache.read(cache_key)
      
      if @answer.nil?
        # Queue the job and show loading state
        job = Navigator::ProcessQuestionJob.perform_later(
          ekn_slug: @ekn.slug,
          question: q,
          mode: @mode,
          cache_key: cache_key
        )
        @job_id = job.job_id
        @answer = { processing: true, job_id: job.job_id }
      end
    else
      # Don't calculate metrics here - let the Stimulus controller handle it
      @metrics = nil
      @batch_report = nil
    end
  end

  def metrics
    ekn = Ekn.find_by!(slug: params[:ekn_slug])
    batch = params[:batch_id] ? IngestBatch.find(params[:batch_id]) : ekn.ingest_batches.last
    
    # Calculate metrics
    metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: batch)
    metrics = metrics_service.calculate_all_metrics
    
    render json: { 
      metrics: metrics,
      ekn_slug: ekn.slug,
      batch_id: batch.id
    }
  rescue => e
    Rails.logger.error "Error calculating metrics: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  def answer_status
    @ekn = Ekn.find_by!(slug: params[:ekn_slug])
    cache_key = params[:cache_key]
    answer = Rails.cache.read(cache_key)
    
    if answer
      render json: { ready: true, answer: answer }
    else
      # Check if job is still running
      job = SolidQueue::Job.find_by(active_job_id: params[:job_id])
      if job && job.finished_at.nil?
        render json: { ready: false, status: 'processing' }
      elsif job && job.finished_at
        # Job finished but answer not in cache might mean it failed
        render json: { ready: false, status: 'failed', message: 'Question processing completed but no answer found' }
      else
        # Job not found or failed
        render json: { ready: false, status: 'failed', message: 'Question processing failed' }
      end
    end
  end

  private

  def calculate_ekn_stats
    {
      total_files: @batch.ingest_items.count,
      processed_files: @batch.ingest_items.where.not(pool_status: nil).count,
      total_batches: @ekn.ingest_batches.count,
      created_at: @ekn.created_at,
      last_updated: @batch.updated_at,
      pipeline_status: @batch.status,
      lexicon_terms: @batch.lexicon_entries.count,
      graph_nodes: @batch.pool_items.count
    }
  rescue => e
    Rails.logger.error "Error calculating EKN stats: #{e.message}"
    {}
  end
end
