# Maps natural language requests to UI specifications
# This is how the Knowledge Navigator generates dynamic interfaces from conversation
module UI
  class NaturalLanguageMapper
    def initialize(ekn = nil)
      @ekn = ekn
      @pattern_recognizer = PatternRecognizer.new
    end
    
    def process(intent:, results:, context:)
      # Don't generate UI for non-visual intents
      return nil unless should_generate_ui?(intent)
      
      # Analyze the intent to determine UI needs
      analysis = @pattern_recognizer.analyze(
        context[:history].last&.dig(:content) || "",
        context
      )
      
      # Build the UI specification
      build_ui_specification(analysis, results, intent)
    end
    
    private
    
    def should_generate_ui?(intent)
      visual_intents = [
        :temporal_evolution,
        :relationship_exploration,
        :spatial_analysis,
        :comparative_analysis,
        :open_exploration,
        :pattern_discovery,
        :distribution_analysis
      ]
      
      visual_intents.include?(intent[:type])
    end
    
    def build_ui_specification(analysis, results, intent)
      components = analysis[:suggested_components]
      primary_component = components.first
      
      return nil unless primary_component
      
      {
        component: primary_component,
        data_query: build_data_query(analysis, intent),
        config: build_component_config(primary_component, analysis),
        interactions: analysis[:interaction_needs],
        layout: determine_layout(components),
        data: extract_relevant_data(results),
        metadata: {
          intent: intent[:type],
          confidence: intent[:confidence],
          generated_at: Time.current.iso8601
        }
      }
    end
    
    def build_data_query(analysis, intent)
      return nil unless @ekn
      
      case intent[:type]
      when :temporal_evolution
        build_temporal_query(analysis[:temporal_scope])
      when :relationship_exploration
        build_relationship_query(intent[:entities])
      when :spatial_analysis
        build_spatial_query(analysis[:spatial_scope])
      when :comparative_analysis
        build_comparison_query(analysis[:comparison_type])
      else
        build_default_query
      end
    end
    
    def build_temporal_query(temporal_scope)
      query = "MATCH (e:Evolutionary)-[:VERSION_OF]->(m:Manifest)"
      
      if temporal_scope[:start_year] && temporal_scope[:end_year]
        query += " WHERE e.observed_at >= '#{temporal_scope[:start_year]}-01-01'"
        query += " AND e.observed_at <= '#{temporal_scope[:end_year]}-12-31'"
      elsif temporal_scope[:relative]
        # Calculate relative date range
        amount = temporal_scope[:relative][:amount]
        unit = temporal_scope[:relative][:unit]
        query += " WHERE e.observed_at >= date('now', '-#{amount} #{unit}')"
      end
      
      query + " RETURN e, m ORDER BY e.observed_at"
    end
    
    def build_relationship_query(entities)
      if entities&.any?
        entity_ids = entities.map { |e| "'#{e[:id]}'" }.join(", ")
        "MATCH p=(n)-[r]-(m) WHERE n.id IN [#{entity_ids}] OR m.id IN [#{entity_ids}] RETURN p"
      else
        "MATCH (n1)-[r]->(n2) RETURN n1, r, n2 LIMIT 100"
      end
    end
    
    def build_spatial_query(spatial_scope)
      query = "MATCH (m:Manifest)-[:LOCATED_AT]->(s:Spatial)"
      
      if spatial_scope[:radius]
        # Add radius constraint
        query += " WHERE distance(s.coordinates, point({latitude: $lat, longitude: $lon})) < #{spatial_scope[:radius][:value]}"
      end
      
      query + " RETURN m, s"
    end
    
    def build_comparison_query(comparison_type)
      case comparison_type
      when :before_after
        <<~CYPHER
          MATCH (before:Experience) WHERE before.observed_at < '2020-03-01'
          WITH collect(before) as before_data
          MATCH (after:Experience) WHERE after.observed_at >= '2020-03-01'
          RETURN before_data, collect(after) as after_data
        CYPHER
      else
        "MATCH (n) RETURN n LIMIT 100"
      end
    end
    
    def build_default_query
      "MATCH (n) RETURN n LIMIT 50"
    end
    
    def build_component_config(component, analysis)
      config = {
        title: generate_title(component, analysis),
        description: generate_description(component, analysis)
      }
      
      case component
      when 'timeline', 'split-timeline'
        config.merge!(
          start_date: analysis[:temporal_scope][:start_year] ? "#{analysis[:temporal_scope][:start_year]}-01-01" : nil,
          end_date: analysis[:temporal_scope][:end_year] ? "#{analysis[:temporal_scope][:end_year]}-12-31" : nil,
          group_by: determine_grouping(analysis),
          show_milestones: true
        )
        
        if component == 'split-timeline'
          config[:split_point] = determine_split_point(analysis)
        end
        
      when 'network-graph'
        config.merge!(
          layout: determine_network_layout(analysis),
          node_size_by: 'degree',
          edge_weight_by: 'strength',
          physics_enabled: true,
          max_nodes: 150
        )
        
      when /map/
        config.merge!(
          map_type: component.split('-').first, # heat, point, route
          zoom_level: determine_zoom_level(analysis[:spatial_scope]),
          center: determine_map_center(analysis),
          clustering: component == 'point-map'
        )
        
      when /chart/
        config.merge!(
          chart_type: determine_chart_type(component),
          axes: determine_axes(analysis),
          colors: determine_color_scheme(analysis),
          show_legend: true
        )
      end
      
      config
    end
    
    def generate_title(component, analysis)
      intent = analysis[:intent]
      
      case intent
      when :temporal_evolution
        "Evolution Over Time"
      when :relationship_exploration
        "Knowledge Network"
      when :spatial_analysis
        "Spatial Distribution"
      when :comparative_analysis
        "Comparative View"
      else
        component.split('-').map(&:capitalize).join(' ')
      end
    end
    
    def generate_description(component, analysis)
      patterns = analysis[:data_patterns]
      
      descriptions = []
      descriptions << "Temporal data" if patterns.include?(:temporal)
      descriptions << "Spatial information" if patterns.include?(:spatial)
      descriptions << "Relationships" if patterns.include?(:relational)
      descriptions << "Categories" if patterns.include?(:categorical)
      
      descriptions.any? ? "Showing #{descriptions.join(', ')}" : "Data visualization"
    end
    
    def determine_grouping(analysis)
      if analysis[:data_patterns].include?(:categorical)
        'category'
      elsif analysis[:data_patterns].include?(:hierarchical)
        'level'
      else
        'pool'
      end
    end
    
    def determine_split_point(analysis)
      if analysis[:temporal_scope][:period]
        analysis[:temporal_scope][:period][:start] || '2020-03-01'
      else
        '2020-03-01' # Default to pandemic split
      end
    end
    
    def determine_network_layout(analysis)
      case analysis[:data_patterns]
      when -> (p) { p.include?(:hierarchical) }
        'hierarchical'
      when -> (p) { p.include?(:spatial) }
        'geographic'
      else
        'force-directed'
      end
    end
    
    def determine_zoom_level(spatial_scope)
      case spatial_scope[:granularity]
      when :country then 4
      when :state then 6
      when :city then 10
      when :neighborhood then 14
      when :point then 16
      else 8
      end
    end
    
    def determine_map_center(_analysis)
      # In production, this would calculate from actual data
      { lat: 40.7128, lng: -74.0060 } # Default to NYC
    end
    
    def determine_chart_type(component)
      case component
      when 'comparison-chart' then 'bar'
      when 'scatter-plot' then 'scatter'
      when 'radar-chart' then 'radar'
      when 'pie-chart' then 'pie'
      else 'line'
      end
    end
    
    def determine_axes(analysis)
      x_axis = if analysis[:data_patterns].include?(:temporal)
        { field: 'time', label: 'Time' }
      elsif analysis[:data_patterns].include?(:categorical)
        { field: 'category', label: 'Category' }
      else
        { field: 'x', label: 'X Axis' }
      end
      
      y_axis = if analysis[:data_patterns].include?(:quantitative)
        { field: 'value', label: 'Value' }
      else
        { field: 'y', label: 'Y Axis' }
      end
      
      { x: x_axis, y: y_axis }
    end
    
    def determine_color_scheme(analysis)
      case analysis[:intent]
      when :comparative_analysis
        'diverging' # Red to blue
      when :temporal_evolution
        'sequential' # Light to dark
      when :categorical
        'categorical' # Distinct colors
      else
        'default'
      end
    end
    
    def determine_layout(components)
      case components.size
      when 1
        :single
      when 2
        :split
      when 3..4
        :grid
      else
        :tabs
      end
    end
    
    def extract_relevant_data(results)
      # Extract data from operation results to pass to UI
      # This would be the actual data from Neo4j queries, etc.
      data = {}
      
      results.each do |operation, result|
        case operation
        when /Evolution/
          data[:timeline] = result[:timeline_data]
        when /Connection/
          data[:network] = result[:connections]
        when /Spatial/
          data[:spatial] = result[:spatial_data]
        end
      end
      
      data
    end
  end
end