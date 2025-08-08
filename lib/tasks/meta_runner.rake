# Meta-Enliterator one-shot runner and ops tasks

namespace :meta_enliterator do
  desc "Run Meta‑Enliterator pipeline: meta_enliterator:run[mode] where mode is micro|full"
  task :run, [:mode] => :environment do |t, args|
    mode = (args[:mode] || 'micro').to_s
    inline = ActiveModel::Type::Boolean.new.cast(ENV['PIPELINE_INLINE'])
    puts "PIPELINE_INLINE: #{inline ? 'ON (running stages inline)' : 'OFF (using queue)'}"

    # Ensure or create Meta‑EKN
    ekn = Ekn.find_or_create_by!(slug: 'meta-enliterator') do |e|
      e.name = 'Meta-Enliterator'
      e.domain_type = 'technical'
      e.personality = 'helpful_guide'
      e.status = 'active'
    end
    ekn.ensure_resources_exist!

    pipeline_run = nil
    if mode == 'micro'
      # Deterministic 10-file selection
      seed = (ENV['SEED'] || '1337').to_i
      files = []
      files += Dir.glob(Rails.root.join('app', 'models', '**', '*.rb'))
      files += Dir.glob(Rails.root.join('app', 'services', '**', '*.rb'))
      files += Dir.glob(Rails.root.join('app', 'jobs', '**', '*.rb'))
      files += Dir.glob(Rails.root.join('docs', '**', '*.md'))
      files.uniq!
      srand(seed)
      pick = files.sample(10).sort
      raise 'No files selected for micro run' if pick.empty?
      pipeline_run = Pipeline::Orchestrator.process_ekn(ekn, pick, started_by: 'meta_runner', auto_advance: true)
    elsif mode == 'full'
      pipeline_run = Pipeline::Orchestrator.process_meta_enliterator(started_by: 'meta_runner', auto_advance: true)
    else
      abort "Unknown mode: #{mode}. Use micro or full."
    end

    puts "Started pipeline ##{pipeline_run.id} for EKN ##{ekn.id}"
    puts "Monitor: bin/rails meta_enliterator:status"
    puts "Tip: set PIPELINE_INLINE=true to run without workers" unless inline
  end

  desc "Run Meta‑Enliterator inline (synchronous stages): meta_enliterator:inline[mode]"
  task :inline, [:mode] => :environment do |t, args|
    ENV['PIPELINE_INLINE'] = 'true'
    Rake::Task['meta_enliterator:run'].invoke(args[:mode] || 'micro')
  end

  desc "Show latest Meta‑Enliterator pipeline status"
  task :status => :environment do
    ekn = Ekn.find_by(name: 'Meta-Enliterator')
    abort 'Meta‑Enliterator not found' unless ekn
    pr = ekn.ekn_pipeline_runs.order(created_at: :desc).first
    abort 'No pipeline runs yet' unless pr
    puts "Pipeline ##{pr.id} — status: #{pr.status}, stage #{pr.current_stage_number}/9 (#{pr.current_stage})"
    puts "Duration: #{pr.duration_so_far}s"
    puts "Errors: #{pr.has_errors? ? pr.error_summary : 'none'}"
  end

  desc "Watch a Meta‑Enliterator run and auto-recover if possible: meta_enliterator:watch[run_id,interval]"
  task :watch, [:run_id, :interval] => :environment do |t, args|
    ekn = Ekn.find_by(slug: 'meta-enliterator') || Ekn.find_by(name: 'Meta-Enliterator')
    abort 'Meta‑Enliterator not found' unless ekn
    run = if args[:run_id]
            EknPipelineRun.find(args[:run_id])
          else
            ekn.ekn_pipeline_runs.order(created_at: :desc).first
          end
    abort 'No pipeline runs yet' unless run
    interval = (args[:interval] || 15).to_i
    puts "Watching run ##{run.id} every #{interval}s... (Ctrl+C to stop)"

    Pipeline::Watchdog.new(run_id: run.id, poll_seconds: interval).call
  end

  desc "Manually advance the current stage inline: meta_enliterator:advance[run_id]"
  task :advance, [:run_id] => :environment do |t, args|
    run = if args[:run_id]
            EknPipelineRun.find(args[:run_id])
          else
            EknPipelineRun.order(created_at: :desc).first
          end
    abort 'No pipeline run found' unless run
    stage = run.current_stage
    mapping = {
      'intake'       => 'Pipeline::IntakeJob',
      'rights'       => 'Rights::TriageJob',
      'lexicon'      => 'Lexicon::BootstrapJob',
      'pools'        => 'Pools::ExtractionJob',
      'graph'        => 'Graph::AssemblyJob',
      'embeddings'   => 'Embedding::RepresentationJob',
      'literacy'     => 'Literacy::ScoringJob',
      'deliverables' => 'Deliverables::GenerationJob',
      'fine_tuning'  => 'FineTune::DatasetBuilderJob'
    }
    klass = mapping[stage]
    abort "No job mapping for stage: #{stage}" unless klass
    puts "Running #{klass} inline for run ##{run.id} (stage: #{stage})"
    klass.constantize.perform_now(run.id)
    puts "Done. Current stage: #{run.reload.current_stage_number}/9 (#{run.current_stage}) status=#{run.status}"
  end
end

namespace :ops do
  desc "Quick environment status (Rails, Solid Queue, Neo4j, Redis, OpenAI)"
  task :status => :environment do
    puts "Rails: OK (#{Rails.env})"
    begin
      queues = SolidQueue::Job.distinct.pluck(:queue_name)
      failed = SolidQueue::FailedExecution.count
      claimed = SolidQueue::ClaimedExecution.count
      ready = SolidQueue::ReadyExecution.count
      puts "SolidQueue: queues=#{queues.join(', ')} failed=#{failed} claimed=#{claimed} ready=#{ready}"
    rescue => e
      puts "SolidQueue: ERROR #{e.message}"
    end
    begin
      drv = Graph::Connection.instance.driver
      drv.verify_connectivity
      puts "Neo4j: connected"
    rescue => e
      puts "Neo4j: ERROR #{e.message}"
    end
    begin
      require 'redis'
      url = ENV['REDIS_URL'] || 'redis://localhost:6379'
      Redis.new(url: url).ping
      puts "Redis: connected"
    rescue => e
      puts "Redis: ERROR #{e.message}"
    end
    begin
      cfg = OpenaiConfig::SettingsManager.current_configuration
      puts "OpenAI: models=#{cfg[:models].inspect} batch_api=#{cfg[:batch_api].inspect}"
    rescue => e
      puts "OpenAI: ERROR #{e.message}"
    end
  end
end
