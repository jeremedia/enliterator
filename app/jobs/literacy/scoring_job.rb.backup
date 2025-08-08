# frozen_string_literal: true

module Literacy
  class ScoringJob < ApplicationJob
    queue_as :default
    
    class ScoringError < StandardError; end
    
    def perform(batch_id, options = {})
      @batch_id = batch_id
      @options = options
      @start_time = Time.current
      
      validate_batch!
      
      Rails.logger.info "[Literacy::ScoringJob] Starting literacy scoring for batch #{batch_id}"
      
      results = {
        batch_id: batch_id,
        started_at: @start_time,
        coverage_analysis: run_coverage_analysis,
        maturity_assessment: run_maturity_assessment,
        gap_identification: run_gap_identification,
        enliteracy_score: run_enliteracy_scoring,
        completed_at: Time.current
      }
      
      results[:processing_time_seconds] = (results[:completed_at] - results[:started_at]).round(2)
      
      save_results(results) if @options[:save_results]
      notify_completion(results) if @options[:notify]
      
      handle_threshold_failure(results) unless results[:enliteracy_score][:passes_threshold]
      
      Rails.logger.info "[Literacy::ScoringJob] Completed literacy scoring for batch #{batch_id}"
      Rails.logger.info "[Literacy::ScoringJob] Enliteracy Score: #{results[:enliteracy_score][:enliteracy_score]}"
      Rails.logger.info "[Literacy::ScoringJob] Passes Threshold: #{results[:enliteracy_score][:passes_threshold]}"
      
      results
    rescue StandardError => e
      handle_error(e)
    end
    
    private
    
    def validate_batch!
      batch = IngestBatch.find_by(id: @batch_id)
      raise ScoringError, "Batch #{@batch_id} not found" unless batch
      
      unless ['completed', 'graph_assembled', 'embeddings_generated'].include?(batch.status)
        raise ScoringError, "Batch #{@batch_id} is not ready for scoring (status: #{batch.status})"
      end
    end
    
    def run_coverage_analysis
      Rails.logger.info "[Literacy::ScoringJob] Running coverage analysis..."
      
      analyzer = Literacy::CoverageAnalyzer.new(@batch_id)
      coverage = analyzer.analyze_all
      
      log_coverage_summary(coverage)
      coverage
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Coverage analysis failed: #{e.message}"
      { error: e.message, status: 'failed' }
    end
    
    def run_maturity_assessment
      Rails.logger.info "[Literacy::ScoringJob] Running maturity assessment..."
      
      assessor = Literacy::MaturityAssessor.new(@batch_id)
      assessment = assessor.assess_batch
      
      Rails.logger.info "[Literacy::ScoringJob] Maturity Level: #{assessment[:maturity_level]} - #{assessment[:level_name]}"
      assessment
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Maturity assessment failed: #{e.message}"
      { error: e.message, status: 'failed' }
    end
    
    def run_gap_identification
      Rails.logger.info "[Literacy::ScoringJob] Running gap identification..."
      
      identifier = Literacy::GapIdentifier.new(@batch_id)
      gaps = identifier.identify_all_gaps
      
      log_gap_summary(gaps)
      gaps
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Gap identification failed: #{e.message}"
      { error: e.message, status: 'failed' }
    end
    
    def run_enliteracy_scoring
      Rails.logger.info "[Literacy::ScoringJob] Calculating enliteracy score..."
      
      scorer = Literacy::EnliteracyScorer.new(@batch_id)
      
      if @options[:generate_report]
        scorer.generate_report
      else
        scorer.calculate_score
      end
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Enliteracy scoring failed: #{e.message}"
      { error: e.message, status: 'failed', enliteracy_score: 0.0, passes_threshold: false }
    end
    
    def save_results(results)
      report_path = Rails.root.join('tmp', 'literacy_reports', "batch_#{@batch_id}_#{Time.current.to_i}.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      
      File.write(report_path, JSON.pretty_generate(results))
      Rails.logger.info "[Literacy::ScoringJob] Report saved to #{report_path}"
      
      update_batch_metadata(results)
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Failed to save results: #{e.message}"
    end
    
    def update_batch_metadata(results)
      batch = IngestBatch.find(@batch_id)
      
      batch.metadata ||= {}
      batch.metadata['literacy_scoring'] = {
        'enliteracy_score' => results[:enliteracy_score][:enliteracy_score],
        'passes_threshold' => results[:enliteracy_score][:passes_threshold],
        'maturity_level' => results[:maturity_assessment][:maturity_level],
        'scored_at' => results[:completed_at].iso8601,
        'processing_time_seconds' => results[:processing_time_seconds]
      }
      
      if results[:enliteracy_score][:passes_threshold]
        batch.status = 'literacy_complete'
      else
        batch.status = 'literacy_insufficient'
      end
      
      batch.save!
    rescue StandardError => e
      Rails.logger.error "[Literacy::ScoringJob] Failed to update batch metadata: #{e.message}"
    end
    
    def notify_completion(results)
      message = if results[:enliteracy_score][:passes_threshold]
        "✅ Batch #{@batch_id} passed literacy scoring with score: #{results[:enliteracy_score][:enliteracy_score]}"
      else
        "⚠️ Batch #{@batch_id} failed literacy scoring with score: #{results[:enliteracy_score][:enliteracy_score]} (minimum: 70)"
      end
      
      Rails.logger.info "[Literacy::ScoringJob] #{message}"
      
      # Here you could add email notification, Slack webhook, etc.
      # NotificationService.notify(message, results) if defined?(NotificationService)
    end
    
    def handle_threshold_failure(results)
      Rails.logger.warn "[Literacy::ScoringJob] Batch #{@batch_id} did not meet minimum threshold"
      Rails.logger.warn "[Literacy::ScoringJob] Score: #{results[:enliteracy_score][:enliteracy_score]} < 70"
      Rails.logger.warn "[Literacy::ScoringJob] Top recommendations:"
      
      results[:enliteracy_score][:recommendations]&.first(3)&.each do |rec|
        Rails.logger.warn "[Literacy::ScoringJob]   - [#{rec[:priority]}] #{rec[:message]}"
      end
      
      if @options[:raise_on_failure]
        raise ScoringError, "Enliteracy score #{results[:enliteracy_score][:enliteracy_score]} below threshold"
      end
    end
    
    def handle_error(error)
      Rails.logger.error "[Literacy::ScoringJob] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      begin
        batch = IngestBatch.find(@batch_id)
        batch.status = 'literacy_error'
        batch.metadata ||= {}
        batch.metadata['literacy_error'] = {
          'message' => error.message,
          'occurred_at' => Time.current.iso8601
        }
        batch.save!
      rescue StandardError => e
        Rails.logger.error "[Literacy::ScoringJob] Failed to update batch with error: #{e.message}"
      end
      
      raise error if @options[:raise_on_error]
    end
    
    def log_coverage_summary(coverage)
      Rails.logger.info "[Literacy::ScoringJob] Coverage Summary:"
      Rails.logger.info "  - Idea Coverage: #{coverage[:idea_coverage][:coverage_percentage]}%"
      Rails.logger.info "  - Relationship Density: #{coverage[:relationship_density][:average_edges_per_node]} edges/node"
      Rails.logger.info "  - Temporal Coverage: #{coverage[:temporal_coverage][:temporal_coverage_percentage]}%"
      Rails.logger.info "  - Spatial Coverage: #{coverage[:spatial_coverage][:spatial_coverage_percentage]}%"
    end
    
    def log_gap_summary(gaps)
      return unless gaps[:summary]
      
      Rails.logger.info "[Literacy::ScoringJob] Gap Summary:"
      Rails.logger.info "  - Total Issues: #{gaps[:summary][:total_issues]}"
      Rails.logger.info "  - Critical Gaps: #{gaps[:summary][:critical_gaps]}"
      Rails.logger.info "  - High Priority Gaps: #{gaps[:summary][:high_priority_gaps]}"
      
      if gaps[:prioritized_actions]&.any?
        Rails.logger.info "  - Top Priority Action: #{gaps[:prioritized_actions].first[:action]}"
      end
    end
  end
end