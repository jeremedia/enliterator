#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test Stage 7: Literacy Scoring & Gaps implementation
# Usage: rails runner script/test_literacy_scoring.rb

require 'json'

class LiteracyScoringTester
  def initialize
    @batch_id = ENV['BATCH_ID'] || get_latest_batch_id
    @verbose = ENV['VERBOSE'] == 'true'
    @results = {}
    @errors = []
  end
  
  def run
    puts "\n" + "="*80
    puts "STAGE 7: LITERACY SCORING & GAPS - TEST SUITE"
    puts "="*80
    puts "Batch ID: #{@batch_id}"
    puts "Time: #{Time.current}"
    puts "="*80
    
    # Check prerequisites
    unless check_prerequisites
      puts "\n❌ Prerequisites not met. Please complete Stages 1-6 first."
      return false
    end
    
    # Run all tests
    test_coverage_analyzer
    test_maturity_assessor
    test_gap_identifier
    test_enliteracy_scorer
    test_scoring_job
    test_rake_tasks
    
    # Display summary
    display_summary
    
    @errors.empty?
  end
  
  private
  
  def get_latest_batch_id
    batch = IngestBatch.order(created_at: :desc).first
    batch&.id || raise("No ingest batches found. Please run Stages 1-6 first.")
  end
  
  def check_prerequisites
    puts "\n📋 Checking Prerequisites..."
    
    checks = {
      "IngestBatch exists" => -> { IngestBatch.exists?(id: @batch_id) },
      "Rights assigned" => -> { ProvenanceAndRights.where(batch_id: @batch_id).exists? },
      "Lexicon extracted" => -> { Lexicon::CanonicalTerm.where(batch_id: @batch_id).exists? },
      "Entities extracted" => -> { 
        Idea.where(batch_id: @batch_id).exists? || 
        Manifest.where(batch_id: @batch_id).exists? 
      },
      "Graph assembled" => -> { check_neo4j_data },
      "Embeddings generated" => -> { Embedding.where(batch_id: @batch_id).exists? }
    }
    
    all_passed = true
    checks.each do |name, check|
      begin
        passed = check.call
        status = passed ? "✅" : "❌"
        puts "  #{status} #{name}"
        all_passed = false unless passed
      rescue => e
        puts "  ❌ #{name}: #{e.message}"
        all_passed = false
      end
    end
    
    all_passed
  end
  
  def check_neo4j_data
    neo4j = Graph::Connection.instance
    neo4j.read_transaction do |tx|
      query = "MATCH (n) WHERE n.batch_id = $batch_id RETURN count(n) as count LIMIT 1"
      result = tx.run(query, batch_id: @batch_id).single
      result[:count] > 0
    end
  rescue => e
    puts "  Neo4j check failed: #{e.message}" if @verbose
    false
  end
  
  def test_coverage_analyzer
    puts "\n🔍 Testing CoverageAnalyzer..."
    
    begin
      analyzer = Literacy::CoverageAnalyzer.new(@batch_id)
      coverage = analyzer.analyze_all
      
      # Validate structure
      required_keys = [:idea_coverage, :relationship_density, :path_completeness, 
                      :temporal_coverage, :spatial_coverage, :pool_distribution]
      
      missing_keys = required_keys - coverage.keys
      if missing_keys.any?
        raise "Missing keys in coverage analysis: #{missing_keys.join(', ')}"
      end
      
      # Check idea coverage
      idea_cov = coverage[:idea_coverage]
      puts "  ✓ Idea coverage: #{idea_cov[:coverage_percentage]}% (#{idea_cov[:status]})"
      
      # Check relationship density
      density = coverage[:relationship_density]
      puts "  ✓ Avg edges per node: #{density[:average_edges_per_node]}"
      puts "  ✓ Orphan nodes: #{density[:orphan_nodes]} (#{density[:orphan_percentage]}%)"
      
      # Check temporal coverage
      temporal = coverage[:temporal_coverage]
      puts "  ✓ Temporal coverage: #{temporal[:temporal_coverage_percentage]}%"
      
      # Check spatial coverage
      spatial = coverage[:spatial_coverage]
      puts "  ✓ Spatial coverage: #{spatial[:spatial_coverage_percentage]}%"
      
      # Check pool distribution
      distribution = coverage[:pool_distribution]
      puts "  ✓ Pools identified: #{distribution[:pool_count]}"
      puts "  ✓ Distribution balance: #{distribution[:balance_score]}%"
      
      @results[:coverage] = coverage
      puts "✅ CoverageAnalyzer test passed"
      
    rescue => e
      @errors << "CoverageAnalyzer: #{e.message}"
      puts "❌ CoverageAnalyzer test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end
  
  def test_maturity_assessor
    puts "\n🎯 Testing MaturityAssessor..."
    
    begin
      assessor = Literacy::MaturityAssessor.new(@batch_id)
      assessment = assessor.assess_batch
      
      # Validate structure
      required_keys = [:batch_id, :maturity_level, :level_name, :level_description, 
                      :capabilities, :requirements_met, :next_level_requirements]
      
      missing_keys = required_keys - assessment.keys
      if missing_keys.any?
        raise "Missing keys in maturity assessment: #{missing_keys.join(', ')}"
      end
      
      puts "  ✓ Current level: #{assessment[:maturity_level]} - #{assessment[:level_name]}"
      puts "  ✓ Description: #{assessment[:level_description]}"
      
      # Check capabilities
      caps = assessment[:capabilities]
      puts "  ✓ Capabilities checked:"
      [:has_ingest_batch, :has_rights_assigned, :has_lexicon, 
       :has_entities, :has_graph, :has_embeddings].each do |cap|
        status = caps[cap] ? "✓" : "✗"
        puts "    #{status} #{cap}"
      end
      
      # Check progress
      if assessment[:details]
        puts "  ✓ Progress to next level: #{assessment[:details][:progress_to_next]}%"
      end
      
      @results[:maturity] = assessment
      puts "✅ MaturityAssessor test passed"
      
    rescue => e
      @errors << "MaturityAssessor: #{e.message}"
      puts "❌ MaturityAssessor test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end
  
  def test_gap_identifier
    puts "\n🔎 Testing GapIdentifier..."
    
    begin
      identifier = Literacy::GapIdentifier.new(@batch_id)
      gaps = identifier.identify_all_gaps
      
      # Check all gap types
      gap_types = [:orphaned_entities, :missing_canonicals, :ambiguous_rights,
                  :sparse_relationships, :temporal_gaps, :missing_embeddings]
      
      puts "  Gap Analysis Results:"
      gap_types.each do |gap_type|
        gap_data = gaps[gap_type]
        next unless gap_data
        
        count = gap_data[:total_count] || gap_data[:missing_embeddings] || 0
        severity = gap_data[:severity] || 'unknown'
        puts "    ✓ #{gap_type.to_s.humanize}: #{count} issues (#{severity})"
      end
      
      # Check summary
      if gaps[:summary]
        puts "  ✓ Total issues identified: #{gaps[:summary][:total_issues]}"
        puts "  ✓ Critical gaps: #{gaps[:summary][:critical_gaps]}"
        puts "  ✓ Overall severity: #{gaps[:summary][:overall_severity]}"
      end
      
      # Check prioritized actions
      if gaps[:prioritized_actions]&.any?
        puts "  ✓ Prioritized actions generated: #{gaps[:prioritized_actions].size}"
        top_action = gaps[:prioritized_actions].first
        puts "    Top priority: #{top_action[:action]}"
      end
      
      @results[:gaps] = gaps
      puts "✅ GapIdentifier test passed"
      
    rescue => e
      @errors << "GapIdentifier: #{e.message}"
      puts "❌ GapIdentifier test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end
  
  def test_enliteracy_scorer
    puts "\n📊 Testing EnliteracyScorer..."
    
    begin
      scorer = Literacy::EnliteracyScorer.new(@batch_id)
      
      # Test score calculation
      score_data = scorer.calculate_score
      
      # Validate structure
      required_keys = [:batch_id, :enliteracy_score, :passes_threshold, 
                      :minimum_required, :component_scores, :weights]
      
      missing_keys = required_keys - score_data.keys
      if missing_keys.any?
        raise "Missing keys in score data: #{missing_keys.join(', ')}"
      end
      
      puts "  📈 ENLITERACY SCORE: #{score_data[:enliteracy_score]}/100"
      puts "  #{score_data[:passes_threshold] ? '✅' : '❌'} Passes threshold (min: #{score_data[:minimum_required]})"
      
      # Check component scores
      puts "  Component scores:"
      score_data[:component_scores].each do |component, score|
        status = score >= 70 ? "✓" : "✗"
        puts "    #{status} #{component.capitalize}: #{score.round(1)}%"
      end
      
      # Test report generation
      report = scorer.generate_report
      
      # Validate report structure
      report_keys = [:executive_summary, :enliteracy_score, :maturity_assessment, 
                    :gap_analysis, :readiness_assessment, :next_steps]
      
      missing_report_keys = report_keys - report.keys
      if missing_report_keys.any?
        raise "Missing keys in report: #{missing_report_keys.join(', ')}"
      end
      
      puts "  ✓ Full report generated successfully"
      
      # Check recommendations
      if score_data[:recommendations]&.any?
        puts "  ✓ Recommendations: #{score_data[:recommendations].size}"
        puts "    Top: #{score_data[:recommendations].first[:message]}"
      end
      
      @results[:score] = score_data
      @results[:report] = report
      puts "✅ EnliteracyScorer test passed"
      
    rescue => e
      @errors << "EnliteracyScorer: #{e.message}"
      puts "❌ EnliteracyScorer test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end
  
  def test_scoring_job
    puts "\n⚙️  Testing ScoringJob..."
    
    begin
      job = Literacy::ScoringJob.new
      results = job.perform(@batch_id, { save_results: false, notify: false })
      
      # Validate job results
      required_keys = [:batch_id, :started_at, :coverage_analysis, 
                      :maturity_assessment, :gap_identification, 
                      :enliteracy_score, :completed_at]
      
      missing_keys = required_keys - results.keys
      if missing_keys.any?
        raise "Missing keys in job results: #{missing_keys.join(', ')}"
      end
      
      puts "  ✓ Job completed in #{results[:processing_time_seconds]}s"
      puts "  ✓ All analysis stages completed"
      
      # Check batch status update
      batch = IngestBatch.find(@batch_id)
      expected_status = results[:enliteracy_score][:passes_threshold] ? 
                       'literacy_complete' : 'literacy_insufficient'
      
      if batch.status == expected_status
        puts "  ✓ Batch status updated to: #{batch.status}"
      else
        puts "  ⚠️  Batch status not updated (current: #{batch.status})"
      end
      
      @results[:job] = results
      puts "✅ ScoringJob test passed"
      
    rescue => e
      @errors << "ScoringJob: #{e.message}"
      puts "❌ ScoringJob test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @verbose
    end
  end
  
  def test_rake_tasks
    puts "\n🔧 Testing Rake Tasks..."
    
    tasks_to_test = [
      'enliterator:literacy:maturity',
      'enliterator:literacy:gaps',
      'enliterator:literacy:score'
    ]
    
    tasks_to_test.each do |task_name|
      begin
        puts "  Testing #{task_name}..."
        
        # Capture output
        output = StringIO.new
        original_stdout = $stdout
        $stdout = output
        
        # Load and invoke the task
        Rake::Task[task_name].reenable
        Rake::Task[task_name].invoke(@batch_id)
        
        $stdout = original_stdout
        result = output.string
        
        if result.include?("Error") || result.include?("failed")
          raise "Task output contains errors"
        end
        
        puts "    ✓ #{task_name} executed successfully"
        
      rescue => e
        $stdout = original_stdout if $stdout != original_stdout
        puts "    ❌ #{task_name} failed: #{e.message}"
        @errors << "Rake task #{task_name}: #{e.message}"
      end
    end
    
    if @errors.none? { |e| e.start_with?("Rake task") }
      puts "✅ All rake tasks passed"
    end
  end
  
  def display_summary
    puts "\n" + "="*80
    puts "TEST SUMMARY"
    puts "="*80
    
    if @errors.empty?
      puts "✅ ALL TESTS PASSED!"
      
      if @results[:score]
        score = @results[:score][:enliteracy_score]
        threshold_status = @results[:score][:passes_threshold]
        
        puts "\n📊 Final Results:"
        puts "  Enliteracy Score: #{score}/100"
        puts "  Status: #{threshold_status ? 'READY FOR STAGE 8' : 'NEEDS IMPROVEMENT'}"
        
        if @results[:maturity]
          puts "  Maturity Level: #{@results[:maturity][:maturity_level]}"
        end
        
        if !threshold_status
          gap = Literacy::EnliteracyScorer::MINIMUM_PASSING_SCORE - score
          puts "\n⚠️  Score is #{gap.round(1)} points below the minimum threshold."
          puts "  Please address identified gaps before proceeding to Stage 8."
        end
      end
      
    else
      puts "❌ TESTS FAILED"
      puts "\nErrors encountered:"
      @errors.each_with_index do |error, i|
        puts "  #{i+1}. #{error}"
      end
    end
    
    # Save test results
    if ENV['SAVE_RESULTS']
      results_path = Rails.root.join('tmp', 'test_results', "literacy_test_#{Time.current.to_i}.json")
      FileUtils.mkdir_p(File.dirname(results_path))
      
      test_output = {
        batch_id: @batch_id,
        timestamp: Time.current.iso8601,
        passed: @errors.empty?,
        errors: @errors,
        results: @results
      }
      
      File.write(results_path, JSON.pretty_generate(test_output))
      puts "\n📁 Test results saved to: #{results_path}"
    end
    
    puts "="*80
  end
end

# Run the test
begin
  tester = LiteracyScoringTester.new
  success = tester.run
  exit(success ? 0 : 1)
rescue => e
  puts "\n❌ Fatal error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  exit(1)
end