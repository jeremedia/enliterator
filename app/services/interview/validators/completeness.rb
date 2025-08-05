# app/services/interview/validators/completeness.rb
module Interview
  module Validators
    class Completeness
      def initialize(dataset, metadata)
        @dataset = dataset
        @metadata = metadata
      end

      def validate
        issues = []
        
        issues << "No entities found" if @dataset.entity_count == 0
        issues << "No data sources added" if @dataset.sources.empty?
        issues << "Dataset type not identified" unless @metadata[:dataset_type]
        
        # Check for minimum viable dataset
        if @dataset.entity_count < 5
          issues << "Too few entities (minimum 5 required)"
        end
        
        # Warn about missing enhancements
        warnings = []
        warnings << "No temporal data detected" unless @dataset.has_temporal?
        warnings << "No descriptions found" unless @dataset.has_descriptions?
        
        {
          passed: issues.empty?,
          issues: issues,
          warnings: warnings,
          message: issues.empty? ? "Dataset complete" : issues.first
        }
      end
    end
  end
end