# app/services/interview/analyzers/gap_detector.rb
module Interview
  module Analyzers
    class GapDetector
      def initialize(dataset, metadata)
        @dataset = dataset
        @metadata = metadata
      end

      def detect
        gaps = []
        
        # Check for missing temporal data
        unless @dataset.has_temporal?
          gaps << {
            name: "Temporal information",
            impact: "HIGH",
            description: "Adding dates/years enables timeline analysis"
          }
        end
        
        # Check for missing descriptions
        unless @dataset.has_descriptions?
          gaps << {
            name: "Descriptions",
            impact: "MEDIUM",
            description: "Text descriptions improve semantic search"
          }
        end
        
        # Check for missing spatial data
        unless @dataset.has_spatial?
          if @metadata[:dataset_type] == :event_data
            gaps << {
              name: "Location data",
              impact: "MEDIUM",
              description: "Spatial data enables neighborhood analysis"
            }
          end
        end
        
        # Check for sparse relationships
        if @dataset.relationship_count < @dataset.entity_count / 2
          gaps << {
            name: "Relationship data",
            impact: "LOW",
            description: "More connections improve graph traversal"
          }
        end
        
        gaps
      end
    end
  end
end