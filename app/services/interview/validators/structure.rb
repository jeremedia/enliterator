# app/services/interview/validators/structure.rb
module Interview
  module Validators
    class Structure
      def initialize(dataset)
        @dataset = dataset
      end

      def validate
        issues = []
        
        # Check for consistent structure across entities
        @dataset.entities.each do |type, entities|
          next if entities.empty?
          
          # Check if all entities of same type have similar keys
          if entities.is_a?(Array) && entities.first.is_a?(Hash)
            keys_variations = entities.map { |e| e.keys.sort }.uniq
            if keys_variations.count > 3
              issues << "Inconsistent structure in #{type} entities"
            end
          end
        end
        
        # Check for required fields
        has_identifiers = check_for_identifiers
        issues << "No clear identifiers found in entities" unless has_identifiers
        
        {
          passed: issues.empty?,
          issues: issues,
          message: issues.empty? ? "Structure validated" : issues.first
        }
      end

      private

      def check_for_identifiers
        @dataset.entities.values.flatten.any? do |entity|
          next unless entity.is_a?(Hash)
          entity.keys.any? { |k| k.to_s.match?(/^(id|name|title|identifier)$/i) }
        end
      end
    end
  end
end