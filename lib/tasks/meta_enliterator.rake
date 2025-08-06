# frozen_string_literal: true

namespace :meta_enliterator do
  desc "Create and process Meta-Enliterator through complete pipeline"
  task create: :environment do
    puts "="*80
    puts "🚀 Creating Meta-Enliterator Knowledge Navigator"
    puts "="*80
    
    # Start the pipeline
    pipeline_run = Pipeline::Orchestrator.process_meta_enliterator(
      auto_advance: true,
      skip_failed_items: false
    )
    
    puts "\n✅ Pipeline started!"
    puts "   Run ID: ##{pipeline_run.id}"
    puts "   EKN: #{pipeline_run.ekn.name}"
    puts "   Batch: ##{pipeline_run.ingest_batch.id}"
    puts "   Items: #{pipeline_run.ingest_batch.ingest_items.count}"
    puts "\nMonitor progress with: rake meta_enliterator:status[#{pipeline_run.id}]"
    
    # Option to monitor in real-time
    if ENV['MONITOR'] == 'true'
      puts "\n📊 Monitoring pipeline progress...\n"
      monitor_pipeline(pipeline_run)
    end
  end
  
  desc "Monitor pipeline status"
  task :status, [:run_id] => :environment do |t, args|
    run_id = args[:run_id] || EknPipelineRun.last&.id
    
    unless run_id
      puts "❌ No pipeline runs found"
      exit 1
    end
    
    run = EknPipelineRun.find(run_id)
    status = run.detailed_status
    
    puts "="*80
    puts "📊 Pipeline Run ##{run.id} Status"
    puts "="*80
    puts "EKN: #{status[:ekn_name]}"
    puts "Status: #{status[:status].upcase}"
    puts "Current Stage: #{status[:current_stage]} (#{status[:stage_number]})"
    puts "Progress: #{'▓' * (status[:progress_percentage] / 5)}#{'░' * (20 - status[:progress_percentage] / 5)} #{status[:progress_percentage]}%"
    puts "Duration: #{status[:duration_seconds]}s"
    
    if status[:stages_completed].any?
      puts "\n✅ Completed Stages:"
      status[:stages_completed].each { |stage| puts "   - #{stage}" }
    end
    
    if status[:stages_failed].any?
      puts "\n❌ Failed Stages:"
      status[:stages_failed].each { |stage| puts "   - #{stage}" }
    end
    
    if status[:metrics].any?
      puts "\n📈 Metrics:"
      puts "   Nodes: #{status[:metrics][:nodes_created]}"
      puts "   Relationships: #{status[:metrics][:relationships_created]}"
      puts "   Literacy Score: #{status[:metrics][:literacy_score]}"
    end
    
    puts "\n💡 Next Action: #{status[:next_action]}"
  end
  
  desc "Resume a failed or paused pipeline"
  task :resume, [:run_id] => :environment do |t, args|
    run_id = args[:run_id]
    
    unless run_id
      # Find the most recent failed or paused run
      run = EknPipelineRun.where(status: ['failed', 'paused']).last
      unless run
        puts "❌ No failed or paused pipeline runs found"
        exit 1
      end
      run_id = run.id
    end
    
    puts "🔄 Resuming pipeline run ##{run_id}..."
    
    run = Pipeline::Orchestrator.resume(run_id)
    
    puts "✅ Pipeline resumed from stage: #{run.current_stage}"
    puts "Monitor with: rake meta_enliterator:status[#{run.id}]"
    
    # Option to monitor
    if ENV['MONITOR'] == 'true'
      monitor_pipeline(run)
    end
  end
  
  desc "Show detailed logs for a pipeline run"
  task :logs, [:run_id] => :environment do |t, args|
    run_id = args[:run_id] || EknPipelineRun.last&.id
    
    unless run_id
      puts "❌ No pipeline runs found"
      exit 1
    end
    
    run = EknPipelineRun.find(run_id)
    
    puts "="*80
    puts "📝 Logs for Pipeline Run ##{run.id}"
    puts "="*80
    
    # Print formatted log with timing
    run.print_log
    
    # Show any errors
    if run.has_errors?
      puts "\n❌ ERRORS:"
      puts run.error_summary
    end
  end
  
  desc "Monitor pipeline in real-time"
  task :monitor, [:run_id] => :environment do |t, args|
    run_id = args[:run_id] || EknPipelineRun.where(status: 'running').last&.id
    
    unless run_id
      puts "❌ No running pipeline found"
      exit 1
    end
    
    run = EknPipelineRun.find(run_id)
    monitor_pipeline(run)
  end
  
  desc "Verify Meta-Enliterator knowledge accumulation"
  task verify: :environment do
    ekn = Ekn.find_by(slug: 'meta-enliterator')
    
    unless ekn
      puts "❌ Meta-Enliterator not found"
      exit 1
    end
    
    puts "="*80
    puts "🔍 Verifying Meta-Enliterator Knowledge"
    puts "="*80
    
    puts "\n📊 EKN Statistics:"
    puts "   Name: #{ekn.name}"
    puts "   ID: #{ekn.id}"
    puts "   Status: #{ekn.status}"
    puts "   Batches: #{ekn.ingest_batches.count}"
    puts "   Total Nodes: #{ekn.total_nodes}"
    puts "   Total Relationships: #{ekn.total_relationships}"
    puts "   Literacy Score: #{ekn.literacy_score}"
    
    # Check Neo4j database
    if ekn.neo4j_database_exists?
      puts "\n✅ Neo4j database exists: #{ekn.neo4j_database_name}"
      
      service = Graph::QueryService.new(ekn.neo4j_database_name)
      stats = service.get_statistics
      
      puts "\n📈 Graph Statistics:"
      stats[:node_labels].each do |label, count|
        puts "   #{label}: #{count} nodes"
      end
      
      puts "\n🔗 Relationship Types:"
      stats[:relationship_types].each do |type, count|
        puts "   #{type}: #{count} relationships"
      end
    else
      puts "\n❌ Neo4j database does not exist!"
    end
    
    # Test some queries
    puts "\n🧪 Test Queries:"
    test_queries = [
      "What is an EKN?",
      "How does the pipeline work?",
      "What are the Ten Pools?"
    ]
    
    test_queries.each do |query|
      puts "   Q: #{query}"
      # In future, this would actually query the Knowledge Navigator
      puts "   A: [Would query Knowledge Navigator]"
    end
    
    # Check for accumulation
    if ekn.ingest_batches.count > 1
      puts "\n✅ Knowledge Accumulation Verified:"
      ekn.ingest_batches.each do |batch|
        puts "   Batch ##{batch.id}: #{batch.ingest_items.count} items → #{batch.pool_entities.count} entities"
      end
    else
      puts "\n⚠️  Only one batch processed - accumulation not yet demonstrated"
    end
  end
  
  desc "Clean up and reset Meta-Enliterator"
  task reset: :environment do
    puts "⚠️  This will delete the Meta-Enliterator and all its data!"
    print "Are you sure? (y/N): "
    
    confirmation = STDIN.gets.chomp.downcase
    unless confirmation == 'y'
      puts "Cancelled"
      exit 0
    end
    
    ekn = Ekn.find_by(slug: 'meta-enliterator')
    
    if ekn
      puts "🗑️  Deleting Meta-Enliterator..."
      
      # Delete Neo4j database if it exists
      if ekn.neo4j_database_exists?
        service = Graph::QueryService.new(ekn.neo4j_database_name)
        service.execute_query("MATCH (n) DETACH DELETE n")
        puts "   Cleared Neo4j database"
      end
      
      # Delete the EKN and all associated data
      ekn.destroy!
      puts "✅ Meta-Enliterator deleted"
    else
      puts "Meta-Enliterator not found"
    end
  end
  
  private
  
  def monitor_pipeline(pipeline_run)
    last_stage = nil
    spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    spinner_index = 0
    
    loop do
      pipeline_run.reload
      status = pipeline_run.detailed_status
      
      # Clear line and show spinner
      print "\r#{spinner[spinner_index]} "
      spinner_index = (spinner_index + 1) % spinner.length
      
      # Show current status
      print "Stage #{status[:stage_number]} - #{status[:current_stage]} | "
      print "Progress: #{status[:progress_percentage]}% | "
      print "Duration: #{status[:duration_seconds]}s"
      
      # Check for stage change
      if status[:current_stage] != last_stage
        puts "\n✅ Stage completed: #{last_stage}" if last_stage
        last_stage = status[:current_stage]
      end
      
      # Check for completion or failure
      case status[:status]
      when 'completed'
        puts "\n\n🎉 PIPELINE COMPLETE!"
        puts "   Total duration: #{status[:duration_seconds]}s"
        puts "   Literacy score: #{status[:metrics][:literacy_score]}"
        puts "   Nodes created: #{status[:metrics][:nodes_created]}"
        puts "   Relationships: #{status[:metrics][:relationships_created]}"
        break
      when 'failed'
        puts "\n\n❌ PIPELINE FAILED at stage: #{status[:current_stage]}"
        puts "   Error: Check logs with: rake meta_enliterator:logs[#{pipeline_run.id}]"
        puts "   Resume with: rake meta_enliterator:resume[#{pipeline_run.id}]"
        break
      when 'paused'
        puts "\n\n⏸️  PIPELINE PAUSED"
        puts "   Resume with: rake meta_enliterator:resume[#{pipeline_run.id}]"
        break
      end
      
      sleep 2
    end
  end
end