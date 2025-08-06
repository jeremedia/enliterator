# Recognizes when a visualization would be helpful and what type
# This is what makes the Navigator anticipatory - it knows when to show, not just tell

module Navigator
  class VisualizationIntentRecognizer
    VISUALIZATION_PATTERNS = {
      relationship: {
        patterns: [
          /how .* connect/i,
          /relationship/i,
          /connect/i,
          /relate/i,
          /link/i,
          /network/i,
          /graph/i,
          /show .* connection/i,
          /what.*between/i
        ],
        type: 'relationship_graph',
        description: 'network visualization'
      },
      temporal: {
        patterns: [
          /timeline/i,
          /over time/i,
          /evolve/i,
          /history/i,
          /progression/i,
          /when did/i,
          /chronolog/i,
          /sequence/i
        ],
        type: 'timeline',
        description: 'temporal visualization'
      },
      comparison: {
        patterns: [
          /compare/i,
          /difference/i,
          /versus/i,
          /vs\./i,
          /contrast/i,
          /similar/i,
          /which is/i
        ],
        type: 'comparison_chart',
        description: 'comparison visualization'
      },
      spatial: {
        patterns: [
          /where/i,
          /location/i,
          /map/i,
          /place/i,
          /position/i,
          /geographic/i,
          /spatial/i
        ],
        type: 'map',
        description: 'spatial visualization'
      },
      distribution: {
        patterns: [
          /how many/i,
          /count/i,
          /distribution/i,
          /breakdown/i,
          /composition/i,
          /percentage/i,
          /proportion/i
        ],
        type: 'chart',
        description: 'statistical visualization'
      }
    }
    
    def recognize(user_input)
      return nil if user_input.blank?
      
      # Check each visualization type
      VISUALIZATION_PATTERNS.each do |category, config|
        if config[:patterns].any? { |pattern| user_input.match?(pattern) }
          return {
            category: category,
            type: config[:type],
            description: config[:description],
            confidence: calculate_confidence(user_input, config[:patterns])
          }
        end
      end
      
      # No explicit visualization intent found
      nil
    end
    
    def should_visualize?(user_input, context = {})
      # Determine if we should proactively create a visualization
      # even if not explicitly requested
      
      # Always visualize if explicit intent detected
      return true if recognize(user_input).present?
      
      # Check for implicit visualization needs
      if discussing_complexity?(user_input, context)
        return true
      end
      
      if multiple_entities_mentioned?(user_input, context)
        return true
      end
      
      false
    end
    
    private
    
    def calculate_confidence(text, patterns)
      # Calculate how strongly the text matches the patterns
      matches = patterns.count { |p| text.match?(p) }
      (matches.to_f / patterns.length * 100).round
    end
    
    def discussing_complexity?(text, context)
      # Detect when the conversation would benefit from visualization
      complexity_indicators = [
        /multiple/i,
        /complex/i,
        /interconnect/i,
        /various/i,
        /several/i,
        /network/i
      ]
      
      complexity_indicators.any? { |indicator| text.match?(indicator) }
    end
    
    def multiple_entities_mentioned?(text, context)
      # Check if multiple entities are being discussed
      # This would benefit from a visualization
      entities = context[:entities] || []
      entities.count > 3
    end
  end
end