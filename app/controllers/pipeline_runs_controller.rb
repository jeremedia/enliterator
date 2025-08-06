# frozen_string_literal: true

# Controller for monitoring and managing pipeline runs
class PipelineRunsController < ApplicationController
  before_action :set_pipeline_run, only: [:show, :resume, :pause, :logs]
  
  def index
    @runs = EknPipelineRun.includes(:ekn, :ingest_batch)
                          .order(created_at: :desc)
                          .page(params[:page])
    
    @active_runs = @runs.select { |r| %w[running retrying].include?(r.status) }
    @failed_runs = @runs.select { |r| r.status == 'failed' }
    @completed_runs = @runs.select { |r| r.status == 'completed' }
  end
  
  def show
    @status = @pipeline_run.detailed_status
    @logs = @pipeline_run.latest_activity
    
    respond_to do |format|
      format.html
      format.json { render json: @status }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "pipeline_run_#{@pipeline_run.id}",
          partial: "pipeline_runs/status",
          locals: { run: @pipeline_run, status: @status }
        )
      end
    end
  end
  
  def logs
    @logs = @pipeline_run.logs.includes(:log_items)
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          run_id: @pipeline_run.id,
          logs: @logs.map do |log|
            {
              label: log.label,
              items: log.log_items.map { |item| 
                {
                  text: item.text,
                  status: item.status,
                  created_at: item.created_at
                }
              }
            }
          end
        }
      end
    end
  end
  
  def resume
    begin
      Pipeline::Orchestrator.resume(@pipeline_run.id)
      redirect_to @pipeline_run, notice: "Pipeline resumed successfully"
    rescue => e
      redirect_to @pipeline_run, alert: "Failed to resume: #{e.message}"
    end
  end
  
  def pause
    begin
      Pipeline::Orchestrator.pause(@pipeline_run.id)
      redirect_to @pipeline_run, notice: "Pipeline paused"
    rescue => e
      redirect_to @pipeline_run, alert: "Failed to pause: #{e.message}"
    end
  end
  
  def new
    @ekn = Ekn.find(params[:ekn_id]) if params[:ekn_id]
    @ekns = Ekn.active
  end
  
  def create
    ekn = Ekn.find(params[:ekn_id])
    
    # Gather files based on source type
    source_files = case params[:source_type]
    when 'upload'
      # Handle file uploads
      handle_uploaded_files(params[:files])
    when 'directory'
      # Process directory
      Dir.glob(File.join(params[:directory_path], '**', '*')).select { |f| File.file?(f) }
    when 'meta_enliterator'
      # Special case for Meta-Enliterator
      return create_meta_enliterator
    else
      []
    end
    
    if source_files.empty?
      redirect_to new_pipeline_run_path, alert: "No files to process"
      return
    end
    
    # Start pipeline
    pipeline_run = Pipeline::Orchestrator.process_ekn(
      ekn,
      source_files,
      batch_name: params[:batch_name],
      auto_advance: params[:auto_advance] != 'false'
    )
    
    redirect_to pipeline_run_path(pipeline_run), 
                notice: "Pipeline started with #{source_files.count} files"
  end
  
  private
  
  def set_pipeline_run
    @pipeline_run = EknPipelineRun.find(params[:id])
  end
  
  def handle_uploaded_files(files)
    return [] unless files
    
    upload_dir = Rails.root.join('tmp', 'uploads', SecureRandom.hex(8))
    FileUtils.mkdir_p(upload_dir)
    
    files.map do |file|
      path = upload_dir.join(file.original_filename)
      File.open(path, 'wb') { |f| f.write(file.read) }
      path.to_s
    end
  end
  
  def create_meta_enliterator
    pipeline_run = Pipeline::Orchestrator.process_meta_enliterator
    redirect_to pipeline_run_path(pipeline_run), 
                notice: "Meta-Enliterator pipeline started"
  end
end