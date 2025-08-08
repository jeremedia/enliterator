# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @settings_count = OpenaiSetting.count
      @active_settings = OpenaiSetting.active.count
      @prompt_templates_count = PromptTemplate.count
      @active_templates = PromptTemplate.active.count
      @fine_tune_jobs = FineTuneJob.order(created_at: :desc).limit(5)
      @current_model = FineTuneJob.current_model
      
      # Calculate usage stats (placeholder for now)
      @usage_stats = calculate_usage_stats

      # Neo4j GenAI health snapshot
      @genai_status = genai_health
    end
    
    private
    
    def calculate_usage_stats
      today_calls = ApiCall.today
      month_calls = ApiCall.this_month
      
      # Calculate batch savings (estimate based on typical 50% savings)
      batch_cost = today_calls.where("endpoint LIKE ?", '%batch%').sum(:total_cost).to_f
      estimated_non_batch_cost = batch_cost * 2 # Batch API typically saves 50%
      
      {
        today_cost: today_calls.sum(:total_cost).to_f,
        month_cost: month_calls.sum(:total_cost).to_f,
        batch_savings: estimated_non_batch_cost - batch_cost,
        total_requests: month_calls.count,
        extraction_requests: month_calls.where("service_name LIKE ?", '%Extraction%').count,
        routing_requests: month_calls.where("service_name LIKE ?", '%Routing%').count,
        # Additional useful stats
        today_requests: today_calls.count,
        failed_requests: today_calls.failed.count,
        avg_response_time: today_calls.average(:response_time_ms).to_f.round(2)
      }
    rescue => e
      Rails.logger.error "Error calculating usage stats: #{e.message}"
      # Return defaults if there's an error
      {
        today_cost: 0.0,
        month_cost: 0.0,
        batch_savings: 0.0,
        total_requests: 0,
        extraction_requests: 0,
        routing_requests: 0,
        today_requests: 0,
        failed_requests: 0,
        avg_response_time: 0.0
      }
    end

    def genai_health
      status = {
        apoc: false,
        apoc_merge_relationship: false,
        procedures: [],
        providers: [],
        has_encode_batch: false,
        has_config: false,
        ekn_name: nil,
        ekn_db: nil,
        embedded_nodes: 0,
        avg_dims: 0
      }

      driver = Graph::Connection.instance.driver
      session = driver.session(database: 'neo4j')
      procs = session.run("SHOW PROCEDURES YIELD name RETURN collect(name) AS names").single&.[]( :names ) || []
      status[:procedures] = procs
      status[:has_config] = procs.include?('genai.config.init')
      status[:has_encode_batch] = procs.include?('genai.vector.encodeBatch')
      status[:apoc] = procs.any? { |n| n.start_with?('apoc.') }
      status[:apoc_merge_relationship] = procs.include?('apoc.merge.relationship')
      begin
        providers = session.run("CALL genai.vector.listEncodingProviders() YIELD name RETURN collect(name) AS providers").single&.[]( :providers ) || []
        status[:providers] = providers
      rescue
        status[:providers] = []
      ensure
        session.close
      end

      if (ekn = Ekn.find_by(name: 'Meta-Enliterator') || Ekn.first)
        status[:ekn_name] = ekn.name
        status[:ekn_db] = ekn.neo4j_database_name
        s2 = driver.session(database: status[:ekn_db])
        row = s2.run("MATCH (n) WHERE n.embedding IS NOT NULL RETURN count(n) AS c, coalesce(avg(size(n.embedding)),0) AS dims").single
        status[:embedded_nodes] = row && row[:c] || 0
        status[:avg_dims] = row && row[:dims] || 0
        s2.close
      end

      status
    rescue => e
      Rails.logger.warn "GenAI health check failed: #{e.message}"
      status
    end
  end
end
