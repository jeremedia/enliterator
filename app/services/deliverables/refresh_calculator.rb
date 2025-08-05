# app/services/deliverables/refresh_calculator.rb
module Deliverables
  class RefreshCalculator < ApplicationService
    attr_reader :batch_id, :output_dir

    OPENAI_COSTS = {
      'gpt-4o-2024-08-06' => { input: 0.0025, output: 0.01 },  # per 1K tokens
      'gpt-4o-mini-2024-07-18' => { input: 0.00015, output: 0.0006 },
      'text-embedding-3-small' => { input: 0.00002, output: 0 },
      'text-embedding-3-large' => { input: 0.00013, output: 0 }
    }.freeze

    def initialize(batch_id, output_dir: nil)
      @batch_id = batch_id
      @output_dir = output_dir || Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}")
      FileUtils.mkdir_p(@output_dir)
    end

    def call
      validate_batch!
      
      analysis = {
        data_volatility: analyze_data_volatility,
        temporal_density: calculate_temporal_density,
        relationship_growth: analyze_relationship_growth,
        gap_closure_velocity: calculate_gap_closure_velocity,
        cost_analysis: estimate_costs,
        recommended_cadence: determine_optimal_cadence,
        refresh_schedule: generate_refresh_schedule
      }
      
      save_analysis(analysis)
      analysis
    end

    private

    def validate_batch!
      batch = IngestBatch.find(batch_id)
      raise "Batch not found" unless batch
      raise "Batch not ready for deliverables" unless batch.literacy_score.to_f >= 70
    end

    def analyze_data_volatility
      # Measure how often entities and relationships change
      volatility = {
        entity_changes: {},
        relationship_changes: {},
        overall_score: 0
      }
      
      # Check entity update patterns
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        model = pool.constantize
        entities = model.where(ingest_batch_id: batch_id)
        
        if entities.any?
          recent_updates = entities.where('updated_at > ?', 7.days.ago).count
          total = entities.count
          change_rate = recent_updates.to_f / total
          
          volatility[:entity_changes][pool.downcase] = {
            total: total,
            recent_changes: recent_updates,
            change_rate: (change_rate * 100).round(2),
            volatility_level: categorize_volatility(change_rate)
          }
        end
      end
      
      # Check relationship changes in Neo4j
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        WHERE r.updated_at > datetime() - duration('P7D')
        RETURN count(r) as recent_changes
      CYPHER
      
      total_relationships = neo4j_query("MATCH ()-[r]->() RETURN count(r) as count").first['count']
      recent_relationship_changes = result.first['recent_changes'] || 0
      
      relationship_change_rate = total_relationships > 0 ? 
        recent_relationship_changes.to_f / total_relationships : 0
      
      volatility[:relationship_changes] = {
        total: total_relationships,
        recent_changes: recent_relationship_changes,
        change_rate: (relationship_change_rate * 100).round(2),
        volatility_level: categorize_volatility(relationship_change_rate)
      }
      
      # Calculate overall volatility score (0-1)
      entity_avg = volatility[:entity_changes].values.map { |v| v[:change_rate] }.sum.to_f / 
                   volatility[:entity_changes].count.to_f
      
      volatility[:overall_score] = ((entity_avg + volatility[:relationship_changes][:change_rate]) / 200).round(3)
      volatility[:interpretation] = interpret_volatility(volatility[:overall_score])
      
      volatility
    end

    def calculate_temporal_density
      # Measure events per time period
      density = {
        events_by_period: {},
        average_events_per_day: 0,
        peak_periods: [],
        density_score: 0
      }
      
      experiences = Experience.where(ingest_batch_id: batch_id).where.not(occurred_at: nil)
      
      if experiences.any?
        min_date = experiences.minimum(:occurred_at)
        max_date = experiences.maximum(:occurred_at)
        date_range = (max_date - min_date).to_i
        
        # Daily density
        density[:average_events_per_day] = (experiences.count.to_f / [date_range, 1].max).round(2)
        
        # Monthly density
        experiences.group_by { |e| e.occurred_at.strftime('%Y-%m') }.each do |month, events|
          density[:events_by_period][month] = events.count
        end
        
        # Find peak periods
        sorted_periods = density[:events_by_period].sort_by { |_, count| -count }
        density[:peak_periods] = sorted_periods.first(3).map { |period, count|
          { period: period, event_count: count }
        }
        
        # Calculate density score (normalized 0-1)
        if density[:average_events_per_day] > 10
          density[:density_score] = 1.0
        elsif density[:average_events_per_day] > 1
          density[:density_score] = 0.5
        else
          density[:density_score] = 0.1
        end
        
        density[:interpretation] = interpret_density(density[:density_score])
      end
      
      density
    end

    def analyze_relationship_growth
      # Analyze how relationships grow over time
      growth = {
        current_relationships: 0,
        growth_rate: 0,
        projected_growth: {},
        saturation_level: 0
      }
      
      # Get current relationship count
      result = neo4j_query("MATCH ()-[r]->() RETURN count(r) as count")
      growth[:current_relationships] = result.first['count'] || 0
      
      # Estimate growth rate (simplified - would need historical data in production)
      # Assume 10% monthly growth as baseline
      monthly_growth_rate = 0.10
      growth[:growth_rate] = monthly_growth_rate
      
      # Project growth
      current = growth[:current_relationships]
      [1, 3, 6, 12].each do |months|
        growth[:projected_growth]["#{months}_months"] = (current * (1 + monthly_growth_rate) ** months).round
      end
      
      # Calculate saturation (how close to fully connected)
      entity_count = count_all_entities
      max_possible = entity_count * (entity_count - 1)
      growth[:saturation_level] = max_possible > 0 ? 
        (growth[:current_relationships].to_f / max_possible).round(3) : 0
      
      growth[:interpretation] = interpret_growth(growth[:growth_rate], growth[:saturation_level])
      
      growth
    end

    def calculate_gap_closure_velocity
      # Analyze how quickly gaps are being filled
      velocity = {
        current_gaps: [],
        closure_rate: 0,
        priority_gaps: [],
        estimated_closure_time: {}
      }
      
      # Get gap analysis from literacy scorer
      gap_identifier = Literacy::GapIdentifier.new(batch_id)
      gaps = gap_identifier.identify_gaps
      
      velocity[:current_gaps] = gaps[:gaps].map { |g|
        {
          type: g[:type],
          severity: g[:severity],
          count: g[:affected_entities].count
        }
      }
      
      # Priority gaps (high severity)
      velocity[:priority_gaps] = gaps[:gaps].select { |g| g[:severity] == 'high' }.map { |g|
        { type: g[:type], recommendation: g[:recommendation] }
      }
      
      # Estimate closure rate (simplified)
      total_gaps = velocity[:current_gaps].sum { |g| g[:count] }
      
      # Assume different closure rates by gap type
      closure_rates = {
        'high' => 5,  # 5 gaps per week
        'medium' => 10,  # 10 gaps per week
        'low' => 20  # 20 gaps per week
      }
      
      velocity[:current_gaps].each do |gap|
        weeks_to_close = gap[:count].to_f / closure_rates[gap[:severity]]
        velocity[:estimated_closure_time]["#{gap[:type]}_#{gap[:severity]}"] = "#{weeks_to_close.round(1)} weeks"
      end
      
      # Overall closure velocity
      if total_gaps > 0
        avg_closure_rate = closure_rates.values.sum / closure_rates.count.to_f
        velocity[:closure_rate] = avg_closure_rate
        velocity[:weeks_to_full_closure] = (total_gaps / avg_closure_rate).round(1)
      end
      
      velocity
    end

    def estimate_costs
      # Estimate API costs for different refresh frequencies
      costs = {
        per_refresh: {},
        monthly_costs: {},
        annual_costs: {},
        cost_breakdown: {},
        recommendations: []
      }
      
      # Calculate tokens needed per refresh
      entity_count = count_all_entities
      relationship_count = count_all_relationships
      
      # Estimate tokens
      extraction_tokens = entity_count * 100  # ~100 tokens per entity extraction
      embedding_tokens = entity_count * 50    # ~50 tokens per embedding
      qa_tokens = 1000 * 20                   # ~1000 Q&A pairs, 20 tokens each
      
      total_tokens = extraction_tokens + embedding_tokens + qa_tokens
      
      # Calculate costs per refresh
      model = ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini-2024-07-18')
      embedding_model = 'text-embedding-3-small'
      
      extraction_cost = (extraction_tokens / 1000.0) * OPENAI_COSTS[model][:input]
      embedding_cost = (embedding_tokens / 1000.0) * OPENAI_COSTS[embedding_model][:input]
      qa_cost = (qa_tokens / 1000.0) * OPENAI_COSTS[model][:output]
      
      costs[:per_refresh] = {
        extraction: extraction_cost.round(2),
        embedding: embedding_cost.round(2),
        qa_generation: qa_cost.round(2),
        total: (extraction_cost + embedding_cost + qa_cost).round(2)
      }
      
      # Calculate monthly costs for different cadences
      cadences = {
        'daily' => 30,
        'weekly' => 4,
        'bi-weekly' => 2,
        'monthly' => 1,
        'quarterly' => 0.33
      }
      
      cadences.each do |cadence, refreshes_per_month|
        monthly_cost = costs[:per_refresh][:total] * refreshes_per_month
        costs[:monthly_costs][cadence] = monthly_cost.round(2)
        costs[:annual_costs][cadence] = (monthly_cost * 12).round(2)
      end
      
      # Cost breakdown by component
      total_cost = costs[:per_refresh][:total]
      costs[:cost_breakdown] = {
        extraction: "#{((extraction_cost / total_cost) * 100).round(1)}%",
        embedding: "#{((embedding_cost / total_cost) * 100).round(1)}%",
        qa_generation: "#{((qa_cost / total_cost) * 100).round(1)}%"
      }
      
      # Recommendations based on cost
      if costs[:per_refresh][:total] < 10
        costs[:recommendations] << "Low cost per refresh - daily updates feasible"
      elsif costs[:per_refresh][:total] < 50
        costs[:recommendations] << "Moderate cost - weekly updates recommended"
      else
        costs[:recommendations] << "High cost - consider monthly or quarterly updates"
      end
      
      # Batch API savings
      costs[:batch_api_savings] = {
        enabled: true,
        discount: "50%",
        monthly_savings: costs[:monthly_costs].transform_values { |v| (v * 0.5).round(2) }
      }
      
      costs
    end

    def determine_optimal_cadence
      volatility = analyze_data_volatility[:overall_score]
      density = calculate_temporal_density[:density_score]
      growth = analyze_relationship_growth[:growth_rate]
      costs = estimate_costs
      
      # Decision matrix
      score = 0
      factors = []
      
      # High volatility needs frequent updates
      if volatility > 0.5
        score += 3
        factors << "High data volatility (#{(volatility * 100).round}%)"
      elsif volatility > 0.2
        score += 2
        factors << "Moderate data volatility (#{(volatility * 100).round}%)"
      else
        score += 1
        factors << "Low data volatility (#{(volatility * 100).round}%)"
      end
      
      # High density needs frequent updates
      if density > 0.7
        score += 3
        factors << "High temporal density"
      elsif density > 0.3
        score += 2
        factors << "Moderate temporal density"
      else
        score += 1
        factors << "Low temporal density"
      end
      
      # Growth rate factor
      if growth > 0.2
        score += 2
        factors << "Rapid relationship growth (#{(growth * 100).round}%/month)"
      else
        score += 1
        factors << "Steady relationship growth (#{(growth * 100).round}%/month)"
      end
      
      # Cost constraints
      monthly_budget = ENV.fetch('MONTHLY_REFRESH_BUDGET', '100').to_f
      
      # Determine cadence based on score and budget
      cadence = if score >= 7 && costs[:monthly_costs]['daily'] <= monthly_budget
                  'daily'
                elsif score >= 5 && costs[:monthly_costs]['weekly'] <= monthly_budget
                  'weekly'
                elsif score >= 3 && costs[:monthly_costs]['bi-weekly'] <= monthly_budget
                  'bi-weekly'
                elsif costs[:monthly_costs]['monthly'] <= monthly_budget
                  'monthly'
                else
                  'quarterly'
                end
      
      {
        recommended_cadence: cadence,
        confidence_score: calculate_confidence(score),
        decision_factors: factors,
        score: score,
        monthly_cost: costs[:monthly_costs][cadence],
        annual_cost: costs[:annual_costs][cadence]
      }
    end

    def generate_refresh_schedule
      cadence = determine_optimal_cadence[:recommended_cadence]
      
      schedule = {
        cadence: cadence,
        next_refresh: calculate_next_refresh(cadence),
        schedule_pattern: generate_pattern(cadence),
        automation_config: generate_automation_config(cadence),
        monitoring: generate_monitoring_config(cadence)
      }
      
      schedule
    end

    def save_analysis(analysis)
      filename = 'refresh_schedule.json'
      filepath = File.join(output_dir, filename)
      
      output = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        analysis: analysis,
        implementation_guide: generate_implementation_guide(analysis[:recommended_cadence])
      }
      
      File.write(filepath, JSON.pretty_generate(output))
      
      {
        filename: filename,
        path: filepath
      }
    end

    # Helper methods
    def categorize_volatility(rate)
      if rate > 0.5
        'high'
      elsif rate > 0.1
        'medium'
      else
        'low'
      end
    end

    def interpret_volatility(score)
      if score > 0.5
        "Very high volatility - data changes frequently, requiring frequent updates"
      elsif score > 0.2
        "Moderate volatility - data changes regularly, weekly updates recommended"
      elsif score > 0.05
        "Low volatility - data relatively stable, monthly updates sufficient"
      else
        "Very low volatility - data very stable, quarterly updates sufficient"
      end
    end

    def interpret_density(score)
      if score > 0.7
        "High event density - many events per time period"
      elsif score > 0.3
        "Moderate event density - regular event occurrence"
      else
        "Low event density - sparse events over time"
      end
    end

    def interpret_growth(rate, saturation)
      if saturation > 0.8
        "Near saturation - limited growth potential"
      elsif rate > 0.2
        "Rapid growth phase - frequent updates needed"
      elsif rate > 0.05
        "Steady growth - regular updates recommended"
      else
        "Slow growth - infrequent updates sufficient"
      end
    end

    def calculate_confidence(score)
      # Map score to confidence percentage
      case score
      when 8..10
        95
      when 6..7
        85
      when 4..5
        75
      when 2..3
        65
      else
        50
      end
    end

    def calculate_next_refresh(cadence)
      case cadence
      when 'daily'
        Time.current.tomorrow.beginning_of_day.iso8601
      when 'weekly'
        Time.current.next_week.beginning_of_week.iso8601
      when 'bi-weekly'
        (Time.current + 2.weeks).beginning_of_week.iso8601
      when 'monthly'
        Time.current.next_month.beginning_of_month.iso8601
      when 'quarterly'
        Time.current.beginning_of_quarter.next_quarter.iso8601
      else
        Time.current.next_week.iso8601
      end
    end

    def generate_pattern(cadence)
      case cadence
      when 'daily'
        "Every day at 2:00 AM UTC"
      when 'weekly'
        "Every Monday at 2:00 AM UTC"
      when 'bi-weekly'
        "Every other Monday at 2:00 AM UTC"
      when 'monthly'
        "First Monday of each month at 2:00 AM UTC"
      when 'quarterly'
        "First Monday of each quarter at 2:00 AM UTC"
      else
        "Custom schedule required"
      end
    end

    def generate_automation_config(cadence)
      {
        job_class: 'Deliverables::GenerationJob',
        queue: 'default',
        cron_expression: cadence_to_cron(cadence),
        retry_on_failure: true,
        max_retries: 3,
        notification_on_failure: true
      }
    end

    def generate_monitoring_config(cadence)
      {
        metrics_to_track: [
          'literacy_score',
          'entity_count',
          'relationship_count',
          'gap_count',
          'processing_time',
          'api_costs'
        ],
        alerting_thresholds: {
          literacy_score_drop: 5,
          processing_time_increase: '50%',
          cost_overrun: '20%'
        },
        reporting_frequency: cadence
      }
    end

    def generate_implementation_guide(cadence)
      {
        setup_steps: [
          "Configure Solid Queue recurring job with cadence: #{cadence}",
          "Set up monitoring alerts for refresh failures",
          "Configure cost tracking for API usage",
          "Set up notification channels for completion/failure"
        ],
        rake_command: "rails enliterator:deliverables:schedule[#{batch_id},#{cadence}]",
        manual_refresh: "rails enliterator:deliverables:generate[#{batch_id}]",
        monitoring_dashboard: "/admin/refresh_schedule/#{batch_id}"
      }
    end

    def cadence_to_cron(cadence)
      case cadence
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
        '0 2 * * 1'  # Default to weekly
      end
    end

    def count_all_entities
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].sum do |pool|
        pool.constantize.where(ingest_batch_id: batch_id).count
      end
    end

    def count_all_relationships
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        RETURN count(r) as count
      CYPHER
      
      result.first['count'] || 0
    end

    def neo4j_query(cypher)
      Rails.configuration.neo4j_driver.session do |session|
        session.run(cypher).to_a
      end
    rescue => e
      Rails.logger.error "Neo4j query failed: #{e.message}"
      []
    end
  end
end