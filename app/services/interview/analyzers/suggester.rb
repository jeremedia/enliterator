# app/services/interview/analyzers/suggester.rb
module Interview
  module Analyzers
    class Suggester
      def initialize(dataset, metadata)
        @dataset = dataset
        @metadata = metadata
      end

      def suggest
        suggestions = []
        
        # Suggest based on dataset type
        case @metadata[:dataset_type]
        when :event_data
          suggestions << "Consider adding participant counts for scale analysis" unless has_counts?
          suggestions << "Include event categories for thematic grouping" unless has_categories?
        when :organization
          suggestions << "Add founding dates for evolution analysis" unless @dataset.has_temporal?
          suggestions << "Include member/staff data for network analysis" unless has_people?
        when :creative_works
          suggestions << "Add creation dates for chronological analysis" unless @dataset.has_temporal?
          suggestions << "Include creator information for attribution" unless has_creators?
        end
        
        # General suggestions
        if @dataset.entity_count < 20
          suggestions << "Consider adding more entities for richer analysis"
        end
        
        if !@dataset.has_descriptions? && @dataset.entity_count > 0
          suggestions << "Add descriptions to improve search and discovery"
        end
        
        suggestions
      end

      private

      def has_counts?
        @dataset.entities.values.flatten.any? do |entity|
          entity.is_a?(Hash) && entity.keys.any? { |k| k.to_s.match?(/count|size|participants/i) }
        end
      end

      def has_categories?
        @dataset.entities.values.flatten.any? do |entity|
          entity.is_a?(Hash) && entity.keys.any? { |k| k.to_s.match?(/category|type|genre/i) }
        end
      end

      def has_people?
        @dataset.entities.keys.any? { |k| k.to_s.match?(/people|member|staff|participant/i) }
      end

      def has_creators?
        @dataset.entities.values.flatten.any? do |entity|
          entity.is_a?(Hash) && entity.keys.any? { |k| k.to_s.match?(/creator|author|artist/i) }
        end
      end
    end
  end
end