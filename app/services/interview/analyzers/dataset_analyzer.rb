# app/services/interview/analyzers/dataset_analyzer.rb
module Interview
  module Analyzers
    class DatasetAnalyzer
      def initialize(dataset)
        @dataset = dataset
      end

      def analyze
        {
          sufficient_data: sufficient_data?,
          summary: generate_summary,
          entity_types: @dataset.entities.keys,
          temporal_coverage: analyze_temporal,
          spatial_coverage: analyze_spatial,
          relationship_density: analyze_relationships,
          quality_score: calculate_quality_score
        }
      end

      private

      def sufficient_data?
        @dataset.entity_count >= 5
      end

      def generate_summary
        parts = []
        parts << "#{@dataset.entity_count} entities" if @dataset.entity_count > 0
        parts << "#{@dataset.entities.keys.count} types" if @dataset.entities.any?
        parts << "temporal data" if @dataset.has_temporal?
        parts << "spatial data" if @dataset.has_spatial?
        parts << "descriptions" if @dataset.has_descriptions?
        
        parts.empty? ? "No data analyzed yet" : "Found: #{parts.join(', ')}"
      end

      def analyze_temporal
        return nil unless @dataset.has_temporal?
        @dataset.temporal_range
      end

      def analyze_spatial
        return nil unless @dataset.has_spatial?
        @dataset.spatial_coverage
      end

      def analyze_relationships
        count = @dataset.relationship_count
        entities = @dataset.entity_count
        
        return :none if count == 0
        return :sparse if count < entities / 2
        return :moderate if count < entities * 2
        :dense
      end

      def calculate_quality_score
        score = 0
        score += 25 if @dataset.entity_count > 10
        score += 25 if @dataset.has_temporal?
        score += 25 if @dataset.has_spatial?
        score += 25 if @dataset.has_descriptions?
        score
      end
    end
  end
end