# Analyzes user requests to determine appropriate UI components
# Part of Stage 9 - Dynamic UI Generation for Knowledge Navigator
module Ui
  class PatternRecognizer
    # Analyze user request to determine UI needs
    def analyze(user_request, context = {})
      request_lower = user_request.downcase
      
      {
        intent: extract_intent(request_lower),
        data_patterns: identify_data_patterns(request_lower),
        suggested_components: suggest_components(request_lower),
        interaction_needs: determine_interactions(request_lower, context),
        temporal_scope: extract_temporal_scope(request_lower),
        spatial_scope: extract_spatial_scope(request_lower),
        comparison_type: identify_comparison_type(request_lower)
      }
    end
    
    private
    
    def extract_intent(request)
      case request
      when /evolv|chang|transform|progress|timeline|histor/
        :temporal_evolution
      when /connect|relat|network|influenc|link|associat/
        :relationship_exploration  
      when /where|locat|map|geographic|spatial|place/
        :spatial_analysis
      when /compar|versus|different|contrast|before.*after/
        :comparative_analysis
      when /explore|browse|investigate|look|show\s+me/
        :open_exploration
      when /pattern|trend|insight|anomal/
        :pattern_discovery
      when /summar|overview|report|key.*point/
        :summarization
      when /distribut|spread|densit|cluster/
        :distribution_analysis
      else
        :general_query
      end
    end
    
    def identify_data_patterns(request)
      patterns = []
      
      # Temporal patterns
      patterns << :temporal if request.match?(/\d{4}|year|month|day|time|when|date|period|era/)
      patterns << :evolution if request.match?(/evolv|chang|grow|progress|transform/)
      
      # Spatial patterns
      patterns << :spatial if request.match?(/where|location|place|map|geographic|coordinate/)
      patterns << :proximity if request.match?(/near|adjacent|neighbor|close|distant/)
      
      # Categorical patterns
      patterns << :categorical if request.match?(/type|category|kind|class|group/)
      patterns << :hierarchical if request.match?(/parent|child|tree|nested|level/)
      
      # Quantitative patterns
      patterns << :quantitative if request.match?(/how many|count|amount|number|quantity|size/)
      patterns << :statistical if request.match?(/average|mean|median|distribution|variance/)
      
      # Relational patterns
      patterns << :relational if request.match?(/connect|link|relate|associate|influence/)
      patterns << :network if request.match?(/network|graph|node|edge|path/)
      
      patterns
    end
    
    def suggest_components(request)
      components = []
      
      # Primary component based on intent
      primary = case extract_intent(request)
      when :temporal_evolution
        request.match?(/split|before.*after/) ? 'split-timeline' : 'timeline'
      when :relationship_exploration
        'network-graph'
      when :spatial_analysis
        case request
        when /heat|densit|cluster/
          'heat-map'
        when /route|path|journey/
          'route-map'
        else
          'point-map'
        end
      when :comparative_analysis
        case request
        when /radar|multi.*dimension/
          'radar-chart'
        when /scatter|correlat/
          'scatter-plot'
        else
          'comparison-chart'
        end
      when :distribution_analysis
        case request
        when /histogram|frequenc/
          'histogram'
        when /pie|proportion/
          'pie-chart'
        else
          'bar-chart'
        end
      when :summarization
        'summary-card'
      when :pattern_discovery
        'pattern-visualization'
      else
        'data-table'
      end
      
      components << primary
      
      # Additional supporting components
      components << 'filter-panel' if request.match?(/filter|only|specific|exclude/)
      components << 'statistics-panel' if request.match?(/stats|metrics|numbers|measure/)
      components << 'legend' if suggest_legend_needed?(primary)
      components << 'zoom-controls' if zoomable_component?(primary)
      
      components
    end
    
    def determine_interactions(request, context)
      interactions = []
      
      # Basic interactions
      interactions << :zoom if request.match?(/zoom|magnif|close.*look/)
      interactions << :pan if request.match?(/pan|move|navigate/)
      interactions << :filter if request.match?(/filter|only|exclude|focus/)
      interactions << :search if request.match?(/search|find|locate/)
      
      # Data interactions
      interactions << :select if request.match?(/select|choose|pick/)
      interactions << :drill_down if request.match?(/detail|more|deep|drill/)
      interactions << :expand if request.match?(/expand|show.*more|unfold/)
      interactions << :compare if request.match?(/compare|contrast|versus/)
      
      # Temporal interactions
      interactions << :play if request.match?(/play|animate|watch.*evolv/)
      interactions << :scrub if request.match?(/scrub|slide|adjust.*time/)
      
      # Export interactions
      interactions << :export if request.match?(/export|download|save/)
      interactions << :share if request.match?(/share|send|collaborat/)
      
      # Context-based interactions
      if context[:previous_interaction] == :select
        interactions << :details_on_demand
      end
      
      interactions.uniq
    end
    
    def extract_temporal_scope(request)
      scope = {}
      
      # Extract years
      years = request.scan(/\b(19|20)\d{2}\b/).flatten.map(&:to_i)
      if years.any?
        scope[:start_year] = years.min
        scope[:end_year] = years.max
      end
      
      # Extract relative time
      case request
      when /last\s+(\d+)\s+(year|month|week|day)/
        amount = $1.to_i
        unit = $2
        scope[:relative] = { amount: amount, unit: unit }
      when /past\s+(year|month|week|day)/
        scope[:relative] = { amount: 1, unit: $1 }
      when /recent|lately/
        scope[:relative] = { amount: 3, unit: 'month' }
      when /all\s+time|entire|whole|complete/
        scope[:all_time] = true
      end
      
      # Extract specific periods
      scope[:period] = case request
      when /covid|pandemic/
        { name: 'pandemic', start: '2020-03', end: '2023-05' }
      when /pre.*covid|before.*pandemic/
        { name: 'pre_pandemic', end: '2020-02' }
      when /post.*covid|after.*pandemic/
        { name: 'post_pandemic', start: '2023-06' }
      else
        nil
      end
      
      scope
    end
    
    def extract_spatial_scope(request)
      scope = {}
      
      # Extract radius/distance
      if request.match?(/within\s+(\d+)\s*(km|mile|meter|m)/)
        scope[:radius] = { value: $1.to_i, unit: $2 }
      end
      
      # Extract spatial relationships
      scope[:relationship] = case request
      when /adjacent|neighbor|next\s+to/
        :adjacent
      when /near|close|proxim/
        :nearby
      when /far|distant|remote/
        :distant
      when /cluster|group|concentrat/
        :clustered
      else
        nil
      end
      
      # Extract spatial granularity
      scope[:granularity] = case request
      when /country|nation/
        :country
      when /state|province|region/
        :state
      when /city|town|metro/
        :city
      when /neighborhood|district|block/
        :neighborhood
      when /exact|precise|specific/
        :point
      else
        :auto
      end
      
      scope
    end
    
    def identify_comparison_type(request)
      case request
      when /before.*after|pre.*post/
        :before_after
      when /a\s+vs\s+b|versus|against/
        :side_by_side
      when /trend|over\s+time/
        :temporal_trend
      when /across|between.*group/
        :cross_group
      when /benchmark|baseline|standard/
        :against_baseline
      else
        nil
      end
    end
    
    def suggest_legend_needed?(component)
      legend_requiring_components = [
        'network-graph',
        'heat-map', 
        'scatter-plot',
        'multi-series-chart'
      ]
      
      legend_requiring_components.include?(component)
    end
    
    def zoomable_component?(component)
      zoomable_components = [
        'network-graph',
        'timeline',
        'map',
        'scatter-plot'
      ]
      
      component.match?(Regexp.union(zoomable_components.map { |c| Regexp.new(c) }))
    end
  end
end