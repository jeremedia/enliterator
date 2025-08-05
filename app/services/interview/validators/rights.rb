# app/services/interview/validators/rights.rb
module Interview
  module Validators
    class Rights
      def initialize(rights_hash)
        @rights = rights_hash || {}
      end

      def validate
        issues = []
        
        issues << "License not specified" unless @rights[:license].present?
        issues << "Training eligibility not specified" if @rights[:training_eligible].nil?
        issues << "Publishability not specified" if @rights[:publishable].nil?
        
        # Check for conflicting settings
        if @rights[:license] == 'Internal Use Only' && @rights[:publishable] == true
          issues << "Internal use license conflicts with publishable flag"
        end
        
        if @rights[:license]&.match?(/NC/i) && @rights[:training_eligible] == true
          issues << "Non-commercial license may conflict with training eligibility"
        end
        
        {
          passed: issues.empty?,
          issues: issues,
          message: issues.empty? ? "Rights properly configured" : issues.first
        }
      end
    end
  end
end