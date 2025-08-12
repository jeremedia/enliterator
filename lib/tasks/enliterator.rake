namespace :enliterator do
  desc "Run the full enliteration pipeline for a data bundle"
  task :ingest, [:bundle_path] => :environment do |t, args|
    unless args[:bundle_path]
      puts "Usage: rails enliterator:ingest[path/to/bundle.zip]"
      exit 1
    end
    
    bundle_path = args[:bundle_path]
    puts "Starting ingest for: #{bundle_path}"
    
    # Create or find ingest batch
    batch_name = "ingest_#{File.basename(bundle_path, '.*')}_#{Time.current.strftime('%Y%m%d_%H%M%S')}"
    batch = IngestBatch.find_or_create_by(name: batch_name) do |b|
      b.source_type = 'zip_bundle'
      b.metadata = { source_path: bundle_path }
      b.status = :pending
      b.started_at = Time.current
    end
    
    puts "Created/found batch: #{batch.name} (ID: #{batch.id})"
    
    # Process the bundle and create ingest items
    begin
      require 'zip'
      
      item_count = 0
      Zip::File.open(bundle_path) do |zip_file|
        zip_file.each do |entry|
          next if entry.directory?
          next if entry.name.end_with?('/')
          
          # Skip certain files
          next if entry.name.include?('.git/')
          next if entry.name.include?('node_modules/')
          next if entry.name.include?('vendor/bundle/')
          next if entry.name.include?('tmp/')
          next if entry.name.match?(/\.(log|tmp|pid|lock|DS_Store)$/i)
          
          # Read content safely
          content = begin
            entry.get_input_stream.read.force_encoding('UTF-8')
          rescue Encoding::UndefinedConversionError
            # Binary file or encoding issue - store as base64
            "[BINARY FILE - #{entry.size} bytes]"
          end
          
          # Create ingest item
          item = batch.ingest_items.find_or_create_by(
            file_path: entry.name
          ) do |i|
            i.media_type = detect_media_type(entry.name)
            i.size_bytes = entry.size
            i.content = content
            i.triage_status = :pending
            i.source_type = 'file'
            i.content_sample = content&.truncate(500)
            i.metadata = {
              file_name: File.basename(entry.name),
              directory: File.dirname(entry.name),
              extension: File.extname(entry.name),
              original_size: entry.size
            }
          end
          
          item_count += 1
          print "."
          
          # Flush periodically
          if item_count % 50 == 0
            print " #{item_count}\n"
          end
        end
      end
      
      batch.update!(
        status: :intake_completed,
        completed_at: Time.current,
        statistics: {
          items_processed: item_count,
          processing_time: Time.current - batch.started_at
        }
      )
      
      puts "\n✅ Ingest complete: #{batch.ingest_items.count} items processed"
      puts "Batch ID: #{batch.id}"
      
    rescue => e
      batch.update!(status: :intake_failed)
      puts "\n❌ Ingest failed: #{e.message}"
      puts "Backtrace: #{e.backtrace.first(5).join("\n")}" if ENV['DEBUG']
      raise e
    end
  end
  
  namespace :graph do
    desc "Sync entities to Neo4j graph database"
    task :sync, [:batch_id] => :environment do |t, args|
      batch_id = args[:batch_id] || IngestBatch.last&.id
      
      unless batch_id
        puts "Usage: rails enliterator:graph:sync[batch_id]"
        puts "Available batches:"
        IngestBatch.pluck(:id, :name).each { |id, name| puts "  #{id}: #{name}" }
        exit 1
      end
      
      puts "Syncing batch #{batch_id} to Neo4j..."
      job = Graph::AssemblyJob.new
      result = job.perform(batch_id)
      puts "Graph sync complete: #{result[:status]}"
    end
    
    desc "Clear the Neo4j graph database"
    task clear: :environment do
      puts "Clearing Neo4j graph..."
      neo4j = Neo4j::Driver::GraphDatabase.driver(
        ENV.fetch('NEO4J_URL'),
        Neo4j::Driver::AuthTokens.basic(
          ENV.fetch('NEO4J_USERNAME', 'neo4j'),
          ENV.fetch('NEO4J_PASSWORD')
        )
      )
      
      neo4j.session do |session|
        session.run("MATCH (n) DETACH DELETE n")
      end
      neo4j.close
      
      puts "Graph cleared"
    end
  end
  
  namespace :embed do
    desc "Generate embeddings for all eligible entities and paths (Neo4j GenAI)"
    task :generate, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:embed:generate[batch_id]"
        exit 1
      end

      puts "Generating embeddings in Neo4j for batch #{args[:batch_id]}..."
      job = EmbeddingServices::Neo4jBuilderJob.new
      results = job.perform(batch_id: args[:batch_id], options: { batch_size: 200 })

      if results[:status] == 'success'
        entity_info = results.dig(:steps, :entity_embeddings, :total_processed) || 0
        path_info   = results.dig(:steps, :path_embeddings, :total_processed) || 0
        puts "✅ Embeddings generated successfully"
        puts "   Entities: #{entity_info}"
        puts "   Paths: #{path_info}"
      else
        puts "❌ Embedding generation failed: #{results[:error]}"
      end
    end
    
    desc "Check status of batch API jobs"
    task :batch_status, [:batch_id] => :environment do |t, args|
      if args[:batch_id]
        # Check specific OpenAI batch
        batch = OPENAI.batches.retrieve(args[:batch_id])
        puts "\nBatch: #{batch.id}"
        puts "  Status: #{batch.status}"
        puts "  Progress: #{batch.request_counts['completed']}/#{batch.request_counts['total']}"
        puts "  Failed: #{batch.request_counts['failed']}"
        puts "  Created: #{Time.at(batch.created_at)}"
        puts "  Expires: #{Time.at(batch.expires_at)}"
      else
        # Check all recent batches
        list = OPENAI.batches.list(limit: 10)
        puts "\nRecent Batch API Jobs:"
        puts "-" * 60
        
        list.data.each do |batch|
          puts "ID: #{batch.id}"
          puts "  Status: #{batch.status}"
          puts "  Progress: #{batch.request_counts['completed']}/#{batch.request_counts['total']}"
          puts "  Created: #{Time.at(batch.created_at)}"
          puts ""
        end
      end
    end
    
    desc "Process completed batch API results"
    task :process_batch, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:embed:process_batch[batch_id]"
        exit 1
      end
      
      puts "Processing batch #{args[:batch_id]}..."
      
      processor = EmbeddingServices::BatchProcessor.new(ingest_batch_id: nil)
      results = processor.process_results(args[:batch_id])
      
      puts "Results:"
      puts "  Status: #{results[:status]}"
      puts "  Processed: #{results[:processed]}"
      puts "  Failed: #{results[:failed]}"
    end
    
    desc "Refresh embeddings for a batch (clear + regenerate in Neo4j)"
    task :refresh, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:embed:refresh[batch_id]"
        exit 1
      end

      batch = IngestBatch.find(args[:batch_id])
      database_name = batch.neo4j_database_name
      driver = Graph::Connection.instance.driver

      puts "Clearing existing embeddings in Neo4j database: #{database_name}..."
      session = driver.session(database: database_name)
      begin
        session.write_transaction do |tx|
          tx.run("MATCH (n) WHERE exists(n.embedding) REMOVE n.embedding")
          tx.run("MATCH ()-[r]-() WHERE exists(r.embedding) REMOVE r.embedding")
        end
      ensure
        session.close
      end
      puts "Cleared embeddings. Regenerating..."

      Rake::Task['enliterator:embed:generate'].invoke(args[:batch_id])
    end
    
    desc "Build or rebuild Neo4j vector indexes for a batch's EKN"
    task :reindex, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:embed:reindex[batch_id]"
        exit 1
      end

      batch = IngestBatch.find(args[:batch_id])
      database_name = batch.neo4j_database_name
      puts "Building vector indexes in Neo4j database: #{database_name}..."

      vector_service = Neo4j::VectorIndexService.new(database_name)
      vector_service.create_indexes
      puts "✅ Vector indexes ensured/created"
    end
    
    desc "Show embedding statistics (Neo4j)"
    task :stats, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:embed:stats[batch_id]"
        exit 1
      end

      service = Neo4j::EmbeddingService.new(args[:batch_id])
      stats = service.verify_embeddings

      puts "\nEmbedding Statistics (Neo4j)"
      puts "=" * 40
      puts "Total embeddings: #{stats[:total_embeddings]}"
      puts "Avg dimensions: #{stats[:avg_dimensions]}"
      puts "Pools: #{Array(stats[:pools_with_embeddings]).join(', ')}"
      puts "Status: #{stats[:status]}"
      puts "Error: #{stats[:error]}" if stats[:status] == 'error'
    end
    
    desc "Test semantic search via Neo4j (requires batch_id)"
    task :search, [:batch_id, :query] => :environment do |t, args|
      unless args[:batch_id] && args[:query]
        puts "Usage: rails enliterator:embed:search[batch_id,'your search query']"
        exit 1
      end

      puts "Searching in batch #{args[:batch_id]} for: #{args[:query]}"
      service = Neo4j::EmbeddingService.new(args[:batch_id])
      results = service.semantic_search(args[:query], limit: 10)

      puts "\nTop results:"
      results.each_with_index do |row, i|
        puts "#{i+1}. [#{row['entity_type']}] #{row['entity_name']} (score: #{row['similarity']})"
      end
    end
  end
  
  namespace :literacy do
    desc "Calculate literacy score for a batch"
    task :score, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:literacy:score[batch_id]"
        puts "Available batches:"
        IngestBatch.pluck(:id, :name).each do |id, name|
          puts "  #{id}: #{name}"
        end
        exit 1
      end
      
      puts "Calculating literacy score for batch #{args[:batch_id]}..."
      puts "=" * 60
      
      job = Literacy::ScoringJob.new
      results = job.perform(
        args[:batch_id], 
        save_results: true,
        notify: true,
        generate_report: false
      )
      
      # Display results
      puts "\n📊 ENLITERACY SCORE: #{results[:enliteracy_score][:enliteracy_score]}/100"
      puts "   Status: #{results[:enliteracy_score][:passes_threshold] ? '✅ PASS' : '❌ FAIL'}"
      puts "   Minimum Required: #{Literacy::EnliteracyScorer::MINIMUM_PASSING_SCORE}"
      
      puts "\n📈 Component Scores:"
      results[:enliteracy_score][:component_scores].each do |component, score|
        status = score >= 70 ? "✓" : "✗"
        puts "   #{status} #{component.to_s.capitalize}: #{score.round(1)}%"
      end
      
      puts "\n🎯 Maturity Level: #{results[:maturity_assessment][:maturity_level]} - #{results[:maturity_assessment][:level_name]}"
      
      if results[:gap_identification][:summary]
        puts "\n⚠️  Gap Analysis:"
        puts "   Total Issues: #{results[:gap_identification][:summary][:total_issues]}"
        puts "   Critical Gaps: #{results[:gap_identification][:summary][:critical_gaps]}"
        puts "   High Priority: #{results[:gap_identification][:summary][:high_priority_gaps]}"
      end
      
      if results[:enliteracy_score][:recommendations]&.any?
        puts "\n💡 Top Recommendations:"
        results[:enliteracy_score][:recommendations].first(3).each do |rec|
          puts "   [#{rec[:priority]}] #{rec[:message]}"
        end
      end
      
      if results[:enliteracy_score][:passes_threshold]
        puts "\n✅ READY FOR STAGE 8: Autogenerated Deliverables"
      else
        gap = Literacy::EnliteracyScorer::MINIMUM_PASSING_SCORE - results[:enliteracy_score][:enliteracy_score]
        puts "\n❌ Score is #{gap.round(1)} points below threshold. Address gaps before proceeding."
      end
    end
    
    desc "Generate detailed gap report"
    task :gaps, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:literacy:gaps[batch_id]"
        exit 1
      end
      
      puts "Identifying gaps for batch #{args[:batch_id]}..."
      
      identifier = Literacy::GapIdentifier.new(args[:batch_id])
      gaps = identifier.identify_all_gaps
      
      puts "\n📋 GAP ANALYSIS REPORT"
      puts "=" * 60
      
      # Summary
      if gaps[:summary]
        puts "\nSummary:"
        puts "  Total Issues: #{gaps[:summary][:total_issues]}"
        puts "  Critical Gaps: #{gaps[:summary][:critical_gaps]}"
        puts "  Overall Severity: #{gaps[:summary][:overall_severity].to_s.upcase}"
      end
      
      # Detailed gaps
      [:orphaned_entities, :missing_canonicals, :ambiguous_rights, 
       :sparse_relationships, :temporal_gaps, :missing_embeddings].each do |gap_type|
        gap_data = gaps[gap_type]
        next unless gap_data
        
        puts "\n#{gap_type.to_s.humanize}:"
        puts "  Count: #{gap_data[:total_count] || gap_data[:missing_embeddings] || 0}"
        puts "  Severity: #{gap_data[:severity]}"
        
        if gap_data[:sample]&.any?
          puts "  Sample:"
          gap_data[:sample].first(3).each do |item|
            puts "    - #{item.inspect}"
          end
        end
      end
      
      # Prioritized actions
      if gaps[:prioritized_actions]&.any?
        puts "\n🎯 Prioritized Actions:"
        gaps[:prioritized_actions].each_with_index do |action, i|
          puts "#{i+1}. [#{action[:severity].to_s.upcase}] #{action[:action]}"
          puts "   Effort: #{action[:estimated_effort]}"
        end
      end
    end
    
    desc "Generate full literacy report"
    task :report, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:literacy:report[batch_id]"
        exit 1
      end
      
      puts "Generating comprehensive literacy report for batch #{args[:batch_id]}..."
      
      scorer = Literacy::EnliteracyScorer.new(args[:batch_id])
      report = scorer.generate_report
      
      # Save report
      report_path = Rails.root.join('tmp', 'literacy_reports', "batch_#{args[:batch_id]}_full_report.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, JSON.pretty_generate(report))
      
      puts "\n📊 LITERACY REPORT GENERATED"
      puts "=" * 60
      
      # Executive Summary
      summary = report[:executive_summary]
      puts "\nExecutive Summary:"
      puts "  Status: #{summary[:status]}"
      puts "  Enliteracy Score: #{summary[:enliteracy_score]}/100"
      puts "  Maturity Level: #{summary[:maturity_level]}"
      
      if summary[:key_strengths]&.any?
        puts "\n  Strengths:"
        summary[:key_strengths].each { |s| puts "    ✓ #{s}" }
      end
      
      if summary[:key_weaknesses]&.any?
        puts "\n  Weaknesses:"
        summary[:key_weaknesses].each { |w| puts "    ✗ #{w}" }
      end
      
      # Readiness
      readiness = report[:readiness_assessment]
      puts "\nReadiness Assessment:"
      puts "  Stage 8 Ready: #{readiness[:stage_8_ready] ? 'YES' : 'NO'}"
      
      if readiness[:blocking_issues]&.any?
        puts "  Blocking Issues:"
        readiness[:blocking_issues].each { |issue| puts "    - #{issue}" }
      end
      
      # Next Steps
      if report[:next_steps]&.any?
        puts "\nNext Steps:"
        report[:next_steps].each_with_index do |step, i|
          puts "#{i+1}. #{step[:action]}"
          puts "   Priority: #{step[:priority]}"
        end
      end
      
      puts "\n📁 Full report saved to: #{report_path}"
    end
    
    desc "Check maturity level"
    task :maturity, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:literacy:maturity[batch_id]"
        exit 1
      end
      
      assessor = Literacy::MaturityAssessor.new(args[:batch_id])
      assessment = assessor.assess_batch
      
      puts "\n🎯 MATURITY ASSESSMENT"
      puts "=" * 60
      puts "Batch: #{args[:batch_id]}"
      puts "Level: #{assessment[:maturity_level]} - #{assessment[:level_name]}"
      puts "Description: #{assessment[:level_description]}"
      
      if assessment[:capabilities][:metrics]
        puts "\nMetrics:"
        assessment[:capabilities][:metrics].each do |key, value|
          puts "  #{key.to_s.humanize}: #{value}"
        end
      end
      
      if assessment[:next_level_requirements]&.any?
        puts "\nRequirements for Next Level:"
        assessment[:next_level_requirements].each do |req|
          status_icon = req[:status] == 'complete' ? '✓' : '✗'
          puts "  #{status_icon} #{req[:description]}"
        end
      end
      
      if assessment[:details]
        puts "\nProgress to Next Level: #{assessment[:details][:progress_to_next]}%"
        
        if assessment[:details][:blockers]&.any?
          puts "Blockers:"
          assessment[:details][:blockers].each { |b| puts "  - #{b}" }
        end
      end
    end
  end
  
  namespace :deliverables do
    desc "Generate all deliverables for a batch"
    task :generate, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:deliverables:generate[batch_id]"
        puts "\nAvailable batches with literacy scores ≥70:"
        IngestBatch.where('literacy_score >= ?', 70).pluck(:id, :name, :literacy_score).each do |id, name, score|
          puts "  #{id}: #{name} (score: #{score})"
        end
        exit 1
      end
      
      puts "🚀 Starting deliverables generation for batch #{args[:batch_id]}..."
      puts "=" * 60
      
      # Run the generation job
      job = Deliverables::GenerationJob.new
      results = job.perform(args[:batch_id])
      
      if results[:success]
        puts "\n✅ DELIVERABLES GENERATED SUCCESSFULLY"
        puts "Output directory: #{results[:output_dir]}"
        
        if results[:results]
          # Graph exports
          if results[:results][:graph_exports]
            puts "\n📊 Graph Exports:"
            puts "  - Cypher dump generated"
            puts "  - Query templates created"
            puts "  - Statistics exported"
            puts "  - Path catalog built"
          end
          
          # Prompt packs
          if results[:results][:prompt_packs]
            puts "\n💬 Prompt Packs:"
            [:discovery, :exploration, :synthesis, :temporal, :spatial].each do |type|
              if results[:results][:prompt_packs][type]
                count = results[:results][:prompt_packs][type][:prompt_count] || 0
                puts "  - #{type.capitalize}: #{count} prompts"
              end
            end
          end
          
          # Evaluation bundle
          if results[:results][:evaluation_bundle]
            puts "\n🧪 Evaluation Bundle:"
            bundle = results[:results][:evaluation_bundle]
            puts "  - Test questions: #{bundle[:test_questions][:question_count] rescue 0}"
            puts "  - Expected answers generated"
            puts "  - Test suites created"
            puts "  - Evaluation rubric defined"
            puts "  - Baseline scores calculated"
          end
          
          # Refresh schedule
          if results[:results][:refresh_schedule]
            schedule = results[:results][:refresh_schedule]
            cadence = schedule[:recommended_cadence][:recommended_cadence] rescue 'unknown'
            cost = schedule[:recommended_cadence][:monthly_cost] rescue 0
            puts "\n📅 Refresh Schedule:"
            puts "  - Recommended cadence: #{cadence}"
            puts "  - Monthly cost: $#{cost}"
          end
          
          # Format exports
          if results[:results][:format_exports]
            puts "\n📁 Format Exports:"
            results[:results][:format_exports].each do |format, info|
              puts "  - #{format}: generated"
            end
          end
          
          # Archive
          if results[:results][:archive]
            archive = results[:results][:archive]
            size_mb = (archive[:size] / 1024.0 / 1024.0).round(2)
            puts "\n📦 Archive:"
            puts "  - File: #{archive[:filename]}"
            puts "  - Size: #{size_mb} MB"
          end
        end
        
        puts "\n📖 README and manifest generated"
        puts "\n✨ Stage 8 complete! Deliverables ready at:"
        puts "   #{results[:output_dir]}"
      else
        puts "\n❌ DELIVERABLES GENERATION FAILED"
        puts "Error: #{results[:error]}"
        
        if results[:errors]&.any?
          puts "\nDetailed errors:"
          results[:errors].each { |err| puts "  - #{err}" }
        end
      end
    end
    
    desc "Export graph in specific format"
    task :export, [:batch_id, :format] => :environment do |t, args|
      unless args[:batch_id] && args[:format]
        puts "Usage: rails enliterator:deliverables:export[batch_id,format]"
        puts "Formats: json_ld, graphml, rdf, csv, markdown, sql"
        exit 1
      end
      
      puts "Exporting batch #{args[:batch_id]} to #{args[:format]}..."
      
      exporter = Deliverables::FormatExporter.new(args[:batch_id], format: args[:format])
      result = exporter.call
      
      puts "Export complete:"
      if result[:files]
        # CSV returns multiple files
        result[:files].each do |file|
          puts "  - #{file[:filename]} (#{file[:row_count]} rows)"
        end
      else
        # Single file formats
        puts "  - #{result[:filename]}"
        puts "  - Size: #{(result[:size] / 1024.0).round(2)} KB"
        puts "  - Path: #{result[:path]}"
      end
    end
    
    desc "Generate prompt pack only"
    task :prompts, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:deliverables:prompts[batch_id]"
        exit 1
      end
      
      puts "Generating prompt packs for batch #{args[:batch_id]}..."
      
      generator = Deliverables::PromptPackGenerator.new(args[:batch_id])
      results = generator.call
      
      puts "\nPrompt packs generated:"
      total_prompts = 0
      
      [:discovery, :exploration, :synthesis, :temporal, :spatial].each do |type|
        if results[type]
          count = results[type][:prompt_count] || 0
          total_prompts += count
          puts "  #{type.capitalize}: #{count} prompts"
        end
      end
      
      if results[:examples]
        puts "  Examples: #{results[:examples][:example_count]} examples"
      end
      
      puts "\nTotal: #{total_prompts} prompts generated"
      puts "Output: #{results[:discovery][:path].sub(/discovery_prompts\.json$/, '')}" if results[:discovery]
    end
    
    desc "Create evaluation bundle"
    task :evaluation, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:deliverables:evaluation[batch_id]"
        exit 1
      end
      
      puts "Creating evaluation bundle for batch #{args[:batch_id]}..."
      
      bundler = Deliverables::EvaluationBundler.new(args[:batch_id])
      results = bundler.call
      
      puts "\nEvaluation bundle created:"
      puts "  Test questions: #{results[:test_questions][:question_count] rescue 0}"
      puts "  Test categories:"
      puts "    - Groundedness tests: #{results[:groundedness_tests][:test_count] rescue 0}"
      puts "    - Rights compliance: #{results[:rights_compliance_tests][:test_count] rescue 0}"
      puts "    - Coverage tests: #{results[:coverage_tests][:test_count] rescue 0}"
      puts "    - Path accuracy: #{results[:path_accuracy_tests][:test_count] rescue 0}"
      puts "    - Temporal consistency: #{results[:temporal_consistency_tests][:test_count] rescue 0}"
      
      # Validate bundle
      validation = bundler.validate
      if validation[:valid]
        puts "\n✅ Bundle validation: PASSED"
      else
        puts "\n❌ Bundle validation: FAILED"
        validation[:errors].each { |err| puts "  - #{err}" }
      end
      
      if results[:baseline_scores]
        scores = results[:baseline_scores][:scores][:expected_performance] rescue {}
        puts "\nExpected baseline performance:"
        puts "  Overall: #{scores[:overall]}%" if scores[:overall]
      end
    end
    
    desc "Calculate refresh cadence"
    task :refresh, [:batch_id] => :environment do |t, args|
      unless args[:batch_id]
        puts "Usage: rails enliterator:deliverables:refresh[batch_id]"
        exit 1
      end
      
      puts "Calculating optimal refresh cadence for batch #{args[:batch_id]}..."
      
      calculator = Deliverables::RefreshCalculator.new(args[:batch_id])
      analysis = calculator.call
      
      puts "\n📊 Data Analysis:"
      puts "  Volatility score: #{(analysis[:data_volatility][:overall_score] * 100).round(1)}%"
      puts "  Temporal density: #{analysis[:temporal_density][:average_events_per_day]} events/day"
      puts "  Relationship growth: #{(analysis[:relationship_growth][:growth_rate] * 100).round(1)}% monthly"
      puts "  Saturation level: #{(analysis[:relationship_growth][:saturation_level] * 100).round(1)}%"
      
      if analysis[:gap_closure_velocity][:priority_gaps]&.any?
        puts "\n⚠️  Priority Gaps:"
        analysis[:gap_closure_velocity][:priority_gaps].each do |gap|
          puts "  - #{gap[:type]}: #{gap[:recommendation]}"
        end
      end
      
      puts "\n💰 Cost Analysis:"
      costs = analysis[:cost_analysis]
      puts "  Per refresh: $#{costs[:per_refresh][:total]}"
      puts "  Monthly costs by cadence:"
      costs[:monthly_costs].each do |cadence, cost|
        savings = costs[:batch_api_savings][:monthly_savings][cadence] rescue nil
        savings_str = savings ? " (or $#{savings} with batch API)" : ""
        puts "    #{cadence}: $#{cost}#{savings_str}"
      end
      
      puts "\n🎯 RECOMMENDATION:"
      rec = analysis[:recommended_cadence]
      puts "  Cadence: #{rec[:recommended_cadence].upcase}"
      puts "  Monthly cost: $#{rec[:monthly_cost]}"
      puts "  Annual cost: $#{rec[:annual_cost]}"
      puts "  Confidence: #{rec[:confidence_score]}%"
      
      puts "\n  Decision factors:"
      rec[:decision_factors].each { |factor| puts "    - #{factor}" }
      
      puts "\n📅 Schedule:"
      schedule = analysis[:refresh_schedule]
      puts "  Next refresh: #{schedule[:next_refresh]}"
      puts "  Pattern: #{schedule[:schedule_pattern]}"
    end
    
    desc "Schedule recurring deliverables generation"
    task :schedule, [:batch_id, :cadence] => :environment do |t, args|
      unless args[:batch_id] && args[:cadence]
        puts "Usage: rails enliterator:deliverables:schedule[batch_id,cadence]"
        puts "Cadences: daily, weekly, bi-weekly, monthly, quarterly"
        exit 1
      end
      
      puts "Setting up recurring generation for batch #{args[:batch_id]}..."
      puts "Cadence: #{args[:cadence]}"
      
      # This would integrate with Solid Queue recurring jobs
      # For now, just show the configuration
      
      cron = case args[:cadence]
      when 'daily'
        '0 2 * * *'
      when 'weekly'
        '0 2 * * 1'
      when 'bi-weekly'
        '0 2 */14 * 1'
      when 'monthly'
        '0 2 1 * *'
      when 'quarterly'
        '0 2 1 */3 *'
      else
        puts "Invalid cadence: #{args[:cadence]}"
        exit 1
      end
      
      puts "\nRecurring job configuration:"
      puts "  Job: Deliverables::GenerationJob"
      puts "  Arguments: [#{args[:batch_id]}]"
      puts "  Cron: #{cron}"
      puts "  Queue: default"
      
      puts "\nTo activate, add to config/recurring.yml:"
      puts "deliverables_batch_#{args[:batch_id]}:"
      puts "  class: Deliverables::GenerationJob"
      puts "  args: [#{args[:batch_id]}]"
      puts "  cron: '#{cron}'"
      puts "  queue: default"
    end
  end
  
  namespace :fine_tune do
    desc "Build dataset for fine-tuning"
    task build: :environment do
      puts "Building fine-tune dataset..."
      # Implementation will be added in Stage 9
      puts "Fine-tune dataset building not yet implemented"
    end
  end
  
  desc "Run the full evaluation suite"
  task evaluate: :environment do
    puts "Running evaluation suite..."
    
    # Run all test scripts
    scripts = [
      'script/test_lexicon_bootstrap.rb',
      'script/test_graph_assembly.rb',
      'script/test_embeddings.rb'
    ]
    
    scripts.each do |script|
      if File.exist?(script)
        puts "\nRunning #{script}..."
        system("rails runner #{script}")
      end
    end
  end

  namespace :seed do
    desc "Process Arctic EKN through full pipeline (complementary to db:seed)"
    task process_arctic: :environment do
      puts "🚀 PROCESSING ARCTIC EKN THROUGH FULL PIPELINE"
      puts "=" * 60
      
      arctic_ekn = Ekn.find_by!(slug: "arctic-research")
      batch = arctic_ekn.ingest_batches.find_by!(name: "Arctic Research Documents Collection")
      
      puts "EKN: #{arctic_ekn.name} (ID: #{arctic_ekn.id})"
      puts "Batch: #{batch.name} (#{batch.ingest_items.count} items)"
      
      # Create pipeline run and execute
      pipeline_run = EknPipelineRun.create!(
        ekn: arctic_ekn,
        ingest_batch: batch,
        auto_advance: true,
        skip_failed_items: false,
        options: {
          inline_mode: true,
          demo_run: false
        }
      )
      
      puts "Created Pipeline Run: #{pipeline_run.id}"
      puts "Starting 9-stage pipeline processing..."
      
      start_time = Time.current
      ENV["PIPELINE_INLINE"] = "true"
      
      pipeline_run.start!
      
      end_time = Time.current
      total_duration = (end_time - start_time).round(2)
      
      pipeline_run.reload
      puts "\n" + "=" * 60
      puts "🎯 ARCTIC PIPELINE PROCESSING COMPLETE"
      puts "=" * 60
      puts "Status: #{pipeline_run.status}"
      puts "Final Stage: #{pipeline_run.current_stage} (#{pipeline_run.current_stage_number}/10)"
      puts "Duration: #{total_duration} seconds"
      puts "Literacy Score: #{pipeline_run.literacy_score || 'Not calculated'}"
      
      if pipeline_run.completed?
        puts "\n✅ SUCCESS! Arctic Research Navigator fully operational"
        puts "🌐 Access: https://e.dev.domt.app/#{arctic_ekn.slug}/chat"
      else
        puts "\n⚠️ Pipeline incomplete or failed"
        puts "Error: #{pipeline_run.error_message}" if pipeline_run.error_message
      end
    end
    
    desc "Complete reset and rebuild of Arctic EKN (DESTRUCTIVE - asks for confirmation)"
    task reset_arctic: :environment do
      puts "🔄 RESETTING ARCTIC EKN (DESTROY AND RECREATE)"
      puts "=" * 60
      
      # CRITICAL: Cost protection check
      arctic_ekn = Ekn.find_by(slug: "arctic-research")
      if arctic_ekn
        completed_runs = arctic_ekn.ekn_pipeline_runs.where(status: 'completed').count
        if completed_runs > 0
          estimated_cost = completed_runs * 50
          puts "💰 COST WARNING: This will destroy #{completed_runs} completed pipeline run(s)"
          puts "   Estimated recreation cost: $#{estimated_cost}+ in OpenAI API calls"
          puts "   Last processing: #{arctic_ekn.updated_at}"
          puts ""
          puts "Are you SURE you want to delete this expensive data?"
          puts "Type 'YES DELETE EXPENSIVE DATA' to confirm:"
          
          confirmation = STDIN.gets.chomp
          unless confirmation == "YES DELETE EXPENSIVE DATA"
            puts "❌ Reset aborted - expensive data protected"
            puts "💡 Use 'rails db:seed' to add data without destroying existing"
            exit 0
          end
        end
        
        puts "Destroying existing Arctic EKN..."
        arctic_ekn.destroy!
        puts "✅ Destroyed"
      else
        puts "No existing Arctic EKN found"
      end
      
      # Run seeds to recreate
      puts "\nRunning db:seed..."
      Rake::Task["db:seed"].invoke
      
      # Process pipeline
      puts "\nProcessing Arctic pipeline..."
      Rake::Task["enliterator:seed:process_arctic"].invoke
      
      puts "\n🎉 Arctic EKN completely rebuilt and operational!"
    end
    
    desc "Check Arctic EKN and essential data status"
    task status: :environment do
      puts "📊 ARCTIC EKN STATUS CHECK"
      puts "=" * 60
      
      # Check admin user
      admin_user = User.find_by(email: "j@zinod.com")
      puts "Admin User (j@zinod.com): #{admin_user ? '✅ Present' : '❌ Missing'}"
      
      # Check Arctic EKN
      arctic_ekn = Ekn.find_by(slug: "arctic-research")
      if arctic_ekn
        puts "Arctic EKN: ✅ Present (ID: #{arctic_ekn.id})"
        puts "  Status: #{arctic_ekn.status || 'Unknown'}"
        puts "  Neo4j DB: #{arctic_ekn.neo4j_database_name}"
        puts "  Knowledge Graph: #{arctic_ekn.total_nodes || 0} nodes, #{arctic_ekn.total_relationships || 0} relationships"
        
        # Check batch
        batch = arctic_ekn.ingest_batches.find_by(name: "Arctic Research Documents Collection")
        if batch
          puts "  Research Batch: ✅ Present (#{batch.ingest_items.count} items)"
          puts "    Status: #{batch.status}"
          processed = batch.ingest_items.where.not(triage_status: ['pending', 'failed']).count
          puts "    Processed: #{processed}/#{batch.ingest_items.count}"
        else
          puts "  Research Batch: ❌ Missing"
        end
        
        # Check personality
        personality = arctic_ekn.ekn_personality_profile
        puts "  Personality Profile: #{personality ? '✅ Present' : '❌ Missing'}"
        
        # Check last pipeline run
        pipeline_run = arctic_ekn.ekn_pipeline_runs.last
        if pipeline_run
          puts "  Last Pipeline Run: ✅ #{pipeline_run.status} (Stage #{pipeline_run.current_stage})"
          puts "    Literacy Score: #{pipeline_run.literacy_score || 'Not calculated'}"
        else
          puts "  Pipeline Runs: ❌ None found"
        end
        
      else
        puts "Arctic EKN: ❌ Missing"
      end
      
      puts "\n🎯 RECOVERY COMMANDS:"
      puts "• Full rebuild: rails enliterator:seed:reset_arctic"
      puts "• Seed only: rails db:seed"
      puts "• Pipeline only: rails enliterator:seed:process_arctic"
    end

    desc "Add training questions to Arctic EKN"
    task add_training_questions: :environment do
      puts "🎯 ADDING ARCTIC TRAINING QUESTIONS"
      puts "=" * 60
      
      arctic_ekn = Ekn.find_by!(slug: "arctic-research")
      
      # Load training questions from the temp script
      load Rails.root.join("tmp", "create_arctic_training_questions.rb")
      
      puts "✅ Arctic training questions added successfully"
    end
    desc "Backup development database (PostgreSQL + Neo4j)"
    task backup: :environment do
      puts "🔒 BACKING UP ENLITERATOR DATABASE"
      puts "=" * 60
      
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      backup_dir = Rails.root.join("backups")
      FileUtils.mkdir_p(backup_dir)
      
      # PostgreSQL backup
      postgres_backup_file = backup_dir.join("enliterator_dev_#{timestamp}.sql")
      puts "📊 Backing up PostgreSQL database..."
      
      # Use pg_dump with connection parameters from database.yml
      db_config = Rails.configuration.database_configuration[Rails.env]["primary"] || Rails.configuration.database_configuration[Rails.env]
      pg_dump_cmd = [
        "pg_dump",
        "-h", db_config["host"] || "localhost", 
        "-U", db_config["username"] || ENV["USER"],
        "-d", db_config["database"],
        "-f", postgres_backup_file.to_s,
        "--no-password",
        "--verbose"
      ]
      
      success = system(*pg_dump_cmd)
      if success
        file_size_mb = (File.size(postgres_backup_file) / 1024.0 / 1024.0).round(2)
        puts "✅ PostgreSQL backup completed: #{postgres_backup_file} (#{file_size_mb} MB)"
      else
        puts "❌ PostgreSQL backup failed"
        exit 1
      end
      
      # Neo4j backup - export cypher dump
      neo4j_backup_file = backup_dir.join("neo4j_dev_#{timestamp}.cypher")
      puts "🕸️  Backing up Neo4j knowledge graph..."
      
      begin
        # Connect to Neo4j and export all nodes and relationships
        driver = Graph::Connection.instance.driver
        session = driver.session
        
        File.open(neo4j_backup_file, 'w') do |file|
          file.puts "// Neo4j Backup - #{Time.current}"
          file.puts "// Arctic Research Navigator Knowledge Graph"
          file.puts ""
          
          # Export all nodes with labels and properties
          result = session.run("MATCH (n) RETURN labels(n) as labels, properties(n) as props, id(n) as id")
          node_count = 0
          result.each do |record|
            labels = record["labels"].join(":")
            props = record["props"].map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
            file.puts "CREATE (n#{record['id']}:#{labels} {#{props}});"
            node_count += 1
          end
          
          file.puts ""
          file.puts "// Relationships"
          
          # Export all relationships with properties
          result = session.run("MATCH (a)-[r]->(b) RETURN id(a) as start_id, type(r) as rel_type, properties(r) as props, id(b) as end_id")
          rel_count = 0
          result.each do |record|
            props = record["props"].empty? ? "" : " {#{record['props'].map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}}"
            file.puts "MATCH (a), (b) WHERE id(a) = #{record['start_id']} AND id(b) = #{record['end_id']} CREATE (a)-[r:#{record['rel_type']}#{props}]->(b);"
            rel_count += 1
          end
          
          file.puts ""
          file.puts "// Backup completed: #{node_count} nodes, #{rel_count} relationships"
        end
        
        session.close
        file_size_kb = (File.size(neo4j_backup_file) / 1024.0).round(2)
        puts "✅ Neo4j backup completed: #{neo4j_backup_file} (#{file_size_kb} KB)"
        
      rescue => e
        puts "⚠️  Neo4j backup failed (non-critical): #{e.message}"
        # Don't exit - Neo4j backup is supplementary
      end
      
      # Create backup summary
      summary_file = backup_dir.join("backup_#{timestamp}_README.txt")
      File.open(summary_file, 'w') do |file|
        file.puts "ENLITERATOR DATABASE BACKUP - #{Time.current}"
        file.puts "=" * 60
        file.puts ""
        file.puts "This backup contains:"
        file.puts "1. PostgreSQL database dump: #{File.basename(postgres_backup_file)}"
        file.puts "2. Neo4j knowledge graph: #{File.basename(neo4j_backup_file)}"
        file.puts ""
        file.puts "RESTORE INSTRUCTIONS:"
        file.puts "1. PostgreSQL: dropdb enliterator_development && createdb enliterator_development && psql -d enliterator_development -f #{File.basename(postgres_backup_file)}"
        file.puts "2. Neo4j: Open Neo4j Browser, select 'ekn-1' database, run the .cypher file"
        file.puts ""
        file.puts "Pipeline Status at backup:"
        
        if EknPipelineRun.exists?
          latest_run = EknPipelineRun.last
          file.puts "- Latest Pipeline Run: ##{latest_run.id} (#{latest_run.status})"
          file.puts "- Current Stage: #{latest_run.current_stage} (#{latest_run.current_stage_number}/9)"
          file.puts "- EKN: #{latest_run.ekn.name}"
          file.puts "- Items Processed: #{latest_run.total_items_processed}"
        else
          file.puts "- No pipeline runs found"
        end
        
        file.puts ""
        file.puts "Database Statistics:"
        file.puts "- EKNs: #{Ekn.count}"
        file.puts "- Ingest Batches: #{IngestBatch.count}" 
        file.puts "- Ingest Items: #{IngestItem.count}"
        file.puts "- API Calls: #{ApiCall.count}"
        file.puts "- Lexicon Entries: #{defined?(Lexicon::CanonicalTerm) ? Lexicon::CanonicalTerm.count : 0}"
        file.puts ""
        file.puts "CRITICAL: This backup contains processed data from #{IngestItem.count} files"
        file.puts "representing significant OpenAI processing costs. Handle with care!"
      end
      
      puts ""
      puts "🎯 BACKUP COMPLETE!"
      puts "=" * 60
      puts "📁 Backup location: #{backup_dir}"
      puts "📊 PostgreSQL: #{File.basename(postgres_backup_file)}"
      puts "🕸️  Neo4j: #{File.basename(neo4j_backup_file)}"  
      puts "📋 Summary: #{File.basename(summary_file)}"
      puts ""
      puts "💡 To restore: rails enliterator:restore[#{timestamp}]"
    end
    
    desc "Restore database from backup [timestamp]"
    task :restore, [:timestamp] => :environment do |t, args|
      unless args[:timestamp]
        puts "Usage: rails enliterator:restore[TIMESTAMP]"
        puts "Available backups:"
        backup_dir = Rails.root.join("backups")
        if backup_dir.exist?
          Dir.glob(backup_dir.join("*_README.txt")).sort.reverse.each do |readme|
            timestamp = File.basename(readme).match(/backup_(\d{8}_\d{6})_README/)[1]
            puts "  #{timestamp}"
          end
        else
          puts "  No backups found in #{backup_dir}"
        end
        exit 1
      end
      
      timestamp = args[:timestamp]
      backup_dir = Rails.root.join("backups")
      postgres_file = backup_dir.join("enliterator_dev_#{timestamp}.sql")
      neo4j_file = backup_dir.join("neo4j_dev_#{timestamp}.cypher")
      
      unless postgres_file.exist?
        puts "❌ Backup not found: #{postgres_file}"
        exit 1
      end
      
      puts "⚠️  WARNING: This will completely replace your current database!"
      puts "📊 PostgreSQL backup: #{postgres_file}"
      puts "🕸️  Neo4j backup: #{neo4j_file}" if neo4j_file.exist?
      puts ""
      print "Type 'YES RESTORE DATABASE' to continue: "
      
      confirmation = STDIN.gets.chomp
      unless confirmation == "YES RESTORE DATABASE"
        puts "❌ Restore cancelled"
        exit 1
      end
      
      puts ""
      puts "🔄 RESTORING DATABASE FROM BACKUP"
      puts "=" * 60
      
      # Restore PostgreSQL
      puts "📊 Restoring PostgreSQL database..."
      db_config = Rails.configuration.database_configuration[Rails.env]["primary"] || Rails.configuration.database_configuration[Rails.env]
      
      # Drop and recreate database
      ActiveRecord::Base.connection.disconnect!
      system("dropdb", db_config["database"]) 
      system("createdb", db_config["database"])
      
      # Restore from backup
      restore_cmd = [
        "psql",
        "-h", db_config["host"] || "localhost",
        "-U", db_config["username"] || ENV["USER"], 
        "-d", db_config["database"],
        "-f", postgres_file.to_s,
        "--quiet"
      ]
      
      success = system(*restore_cmd)
      if success
        puts "✅ PostgreSQL database restored successfully"
      else
        puts "❌ PostgreSQL restore failed"
        exit 1
      end
      
      # Restore Neo4j (manual step)
      if neo4j_file.exist?
        puts ""
        puts "🕸️  Neo4j restore (manual step required):"
        puts "   1. Open Neo4j Browser (http://localhost:7474)"
        puts "   2. Select database: ekn-1"  
        puts "   3. Run: MATCH (n) DETACH DELETE n  // Clear existing data"
        puts "   4. Load file: #{neo4j_file}"
        puts "   5. Execute all CREATE statements"
      end
      
      puts ""
      puts "✅ RESTORE COMPLETE!"
      puts "🎯 Database restored from backup: #{timestamp}"
    end
  end
  
  desc "Show pipeline status"
  task status: :environment do
    puts "\nEnliterator Pipeline Status"
    puts "=" * 50
    
    # Check each stage
    stages = [
      { name: "Stage 1: Intake", check: -> { IngestBatch.any? } },
      { name: "Stage 2: Rights", check: -> { Rights::Record.any? } },
      { name: "Stage 3: Lexicon", check: -> { Lexicon::CanonicalTerm.any? } },
      { name: "Stage 4: Pools", check: -> { Idea.any? || Manifest.any? } },
      { name: "Stage 5: Graph", check: -> {
        neo4j = Neo4j::Driver::GraphDatabase.driver(
          ENV.fetch('NEO4J_URL'),
          Neo4j::Driver::AuthTokens.basic(
            ENV.fetch('NEO4J_USERNAME', 'neo4j'),
            ENV.fetch('NEO4J_PASSWORD')
          )
        )
        count = 0
        neo4j.session do |session|
          result = session.run("MATCH (n) RETURN count(n) as count LIMIT 1")
          count = result.single[:count] rescue 0
        end
        neo4j.close
        count > 0
      }},
      { name: "Stage 6: Embeddings", check: -> { Embedding.any? } }
    ]
    
    stages.each do |stage|
      begin
        status = stage[:check].call ? "✅ Complete" : "⏳ Pending"
      rescue => e
        status = "❌ Error: #{e.message}"
      end
      puts "#{stage[:name]}: #{status}"
    end
    
    # Show counts
    puts "\nEntity Counts:"
    %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
      count = pool.constantize.count rescue 0
      puts "  #{pool}: #{count}"
    end
    
    puts "\nEmbedding Count: #{Embedding.count}"
  end
end

namespace :enliterator do
  namespace :bundle do
    desc "Build deterministic bundles: micro (10 files) or full"
    task :build, [:mode] => :environment do |t, args|
      mode = (args[:mode] || 'micro').to_s
      bundles_dir = Rails.root.join('data', 'bundles')
      FileUtils.mkdir_p(bundles_dir)

      case mode
      when 'micro'
        seed = (ENV['SEED'] || '1337').to_i
        files = []
        files += Dir.glob(Rails.root.join('app', 'models', '**', '*.rb'))
        files += Dir.glob(Rails.root.join('app', 'services', '**', '*.rb'))
        files += Dir.glob(Rails.root.join('app', 'jobs', '**', '*.rb'))
        files += Dir.glob(Rails.root.join('docs', '**', '*.md'))
        files.uniq!
        srand(seed)
        pick = files.sample(10).sort
        path = bundles_dir.join('micro.zip')
        create_zip(path, pick)
        puts "Built micro bundle: #{path} (#{pick.size} files)"
      when 'full'
        files = []
        files += Dir.glob(Rails.root.join('app', '**', '*')).select { |f| File.file?(f) }
        files += Dir.glob(Rails.root.join('docs', '**', '*')).select { |f| File.file?(f) }
        %w[.git node_modules tmp log storage vendor/bundle].each do |skip|
          files.reject! { |f| f.include?("/#{skip}/") }
        end
        files.uniq!
        path = bundles_dir.join('enliterator-full.zip')
        create_zip(path, files)
        puts "Built full bundle: #{path} (#{files.size} files)"
      else
        abort "Unknown mode: #{mode}. Use micro or full."
      end
    end
  end

  namespace :acceptance do
    desc "Run acceptance gates and print rubric"
    task :verify, [:batch_id] => :environment do |t, args|
      abort "Usage: rails enliterator:acceptance:verify[batch_id]" unless args[:batch_id]
      runner = Acceptance::GateRunner.new(args[:batch_id])
      result = runner.run_all
      puts "\n=== Acceptance Rubric ==="
      result[:checks].each do |c|
        mark = c[:passed] ? '✅' : '❌'
        puts "#{mark} #{c[:name]}"
        if ENV['DETAILS'] == 'true' && c[:details]
          puts "   details: #{c[:details].inspect}"
        end
      end
      puts "\n#{result[:summary]}"
      abort "Gates failed" unless result[:passed]
    end
  end
end

# Helper to zip files with relative paths from project root
def create_zip(path, files)
  require 'zip'
  FileUtils.rm_f(path)
  Zip::File.open(path, Zip::File::CREATE) do |zip|
    files.each do |abs|
      rel = Pathname.new(abs).relative_path_from(Rails.root).to_s
      zip.add(rel, abs)
    end
  end
end

# Helper method for media type detection (returns enum values for IngestItem)
def detect_media_type(filename)
  ext = File.extname(filename).downcase
  case ext
  when '.rb', '.rake', '.gemspec' then 'text'
  when '.md', '.txt' then 'text'
  when '.yml', '.yaml' then 'structured'
  when '.json', '.xml' then 'structured'
  when '.js', '.html', '.erb', '.css', '.scss' then 'text'
  when '.sql', '.csv' then 'structured'
  when '.png', '.jpg', '.jpeg', '.gif', '.svg' then 'image'
  when '.mp3', '.wav', '.ogg' then 'audio'
  when '.mp4', '.avi', '.mov' then 'video'
  when '.zip', '.tar', '.gz' then 'binary'
  else 'unknown'
  end
end
