namespace :enliterator do
  desc "Run the full enliteration pipeline for a data bundle"
  task :ingest, [:bundle_path] => :environment do |t, args|
    unless args[:bundle_path]
      puts "Usage: rails enliterator:ingest[path/to/bundle.zip]"
      exit 1
    end
    
    puts "Starting ingest for: #{args[:bundle_path]}"
    # Implementation will be added
  end
  
  namespace :graph do
    desc "Sync entities to Neo4j graph database"
    task sync: :environment do
      puts "Syncing to Neo4j..."
      job = Graph::AssemblyJob.new
      result = job.perform
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
    desc "Generate embeddings for all eligible entities and paths"
    task :generate, [:batch_id, :mode] => :environment do |t, args|
      mode = args[:mode] || 'auto'
      puts "Generating embeddings (mode: #{mode})..."
      
      options = {
        auto_advance: false,
        search_quality: 'balanced'
      }
      
      # Force specific mode if requested
      case mode
      when 'batch'
        options[:use_batch_api] = true
        puts "Using Batch API (50% cost savings, 24hr turnaround)"
      when 'sync'
        options[:use_batch_api] = false
        puts "Using synchronous API (immediate results)"
      else
        puts "Auto-selecting based on data size and urgency"
      end
      
      job = Embedding::BuilderJob.new
      results = job.perform(
        batch_id: args[:batch_id],
        options: options
      )
      
      if results[:status] == 'success'
        if results[:mode] == 'batch_api'
          puts "✅ Embeddings queued via Batch API"
          puts "   Entities queued: #{results[:steps][:batch_api][:entities_queued]}"
          puts "   Paths queued: #{results[:steps][:batch_api][:paths_queued]}"
          puts "   Batches created: #{results[:steps][:batch_api][:batches_created].size}"
          puts "   Est. cost savings: $#{results[:steps][:batch_api][:total_cost_savings]}"
          puts "   Note: Results will be available within 24 hours"
        else
          puts "✅ Embeddings generated successfully"
          puts "   Entities: #{results[:steps][:entity_embeddings][:processed]}"
          puts "   Paths: #{results[:steps][:path_embeddings][:processed]}"
        end
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
      
      processor = Embedding::BatchProcessor.new(ingest_batch_id: nil)
      results = processor.process_results(args[:batch_id])
      
      puts "Results:"
      puts "  Status: #{results[:status]}"
      puts "  Processed: #{results[:processed]}"
      puts "  Failed: #{results[:failed]}"
    end
    
    desc "Refresh embeddings (regenerate all)"
    task refresh: :environment do
      puts "Refreshing all embeddings..."
      
      # Clear existing embeddings
      Embedding.destroy_all
      puts "Cleared existing embeddings"
      
      # Regenerate
      Rake::Task['enliterator:embed:generate'].invoke
    end
    
    desc "Build or rebuild vector indices"
    task :reindex, [:type] => :environment do |t, args|
      index_type = args[:type] || 'hnsw'
      
      puts "Building #{index_type} index..."
      
      builder = Embedding::IndexBuilder.new(
        index_type: index_type,
        force_rebuild: true
      )
      
      results = builder.call
      
      puts "Index built: #{results[:status]}"
      puts "Stats: #{results[:stats].inspect}"
    end
    
    desc "Show embedding statistics"
    task stats: :environment do
      stats = Embedding.coverage_stats
      
      puts "\nEmbedding Statistics"
      puts "=" * 40
      puts "Total embeddings: #{stats[:total]}"
      puts "\nBy type:"
      stats[:by_type].each do |type, count|
        puts "  #{type}: #{count}"
      end
      puts "\nBy pool:"
      stats[:by_pool].each do |pool, count|
        puts "  #{pool}: #{count}"
      end
      puts "\nRights:"
      puts "  Publishable: #{stats[:publishable]}"
      puts "  Training eligible: #{stats[:training_eligible]}"
      puts "  Indexed: #{stats[:indexed]}"
    end
    
    desc "Test similarity search"
    task :search, [:query] => :environment do |t, args|
      unless args[:query]
        puts "Usage: rails enliterator:embed:search['your search query']"
        exit 1
      end
      
      puts "Searching for: #{args[:query]}"
      
      # Generate embedding for query
      response = OPENAI.embeddings.create(
        input: args[:query],
        model: Embedding::OPENAI_MODEL,
        dimensions: Embedding::OPENAI_DIMENSIONS
      )
      
      query_embedding = response.data.first.embedding
      
      # Search
      results = Embedding.semantic_search(
        query_embedding,
        top_k: 10,
        require_rights: 'public'
      )
      
      puts "\nTop 10 results:"
      results.each_with_index do |embed, i|
        puts "#{i+1}. [#{embed.pool}] #{embed.source_text[0..100]}..."
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