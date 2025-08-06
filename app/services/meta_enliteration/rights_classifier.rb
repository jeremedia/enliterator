# app/services/meta_enliteration/rights_classifier.rb
# Classifies rights and eligibility for different types of content in the codebase
# Critical for Stage 2: Rights & Provenance

module MetaEnliteration
  class RightsClassifier < ApplicationService
    
    # Content type detection patterns
    CODE_PATTERNS = /\.(rb|rake|yml|yaml|json|xml|erb|haml|slim)$/i
    DOC_PATTERNS = /\.(md|markdown|rdoc|txt|README)$/i
    TEST_PATTERNS = /(spec|test).*\.rb$|test_.*\.rb$/i
    CONFIG_PATTERNS = /\.(env|secrets|key|pem|crt)$|private|password|token/i
    
    def initialize(file_path, content = nil)
      @file_path = file_path
      @content = content
      @content_type = detect_content_type
    end
    
    def call
      classification = base_classification
      
      # Apply redaction if needed
      if requires_redaction?
        classification[:content] = redact_sensitive_data
        classification[:redacted] = true
      end
      
      # Check for quarantine conditions
      if should_quarantine?
        classification[:quarantine] = true
        classification[:quarantine_reason] = quarantine_reason
        classification[:publishability] = false
        classification[:training_eligibility] = false
      end
      
      classification
    end
    
    private
    
    def detect_content_type
      return :config if @file_path.match?(CONFIG_PATTERNS)
      return :test if @file_path.match?(TEST_PATTERNS)
      return :documentation if @file_path.match?(DOC_PATTERNS)
      return :code if @file_path.match?(CODE_PATTERNS)
      
      # Special cases
      return :commit if @file_path.include?('git_log')
      return :issue if @file_path.include?('issues')
      return :pr if @file_path.include?('pull_requests')
      
      :unknown
    end
    
    def base_classification
      case @content_type
      when :code
        {
          content_type: :code,
          publishability: true,
          training_eligibility: true,
          license: 'MIT',
          rights_notes: 'Open source code under MIT license'
        }
        
      when :documentation
        {
          content_type: :documentation,
          publishability: true,
          training_eligibility: true,
          license: 'MIT',
          rights_notes: 'Project documentation under MIT license'
        }
        
      when :test
        {
          content_type: :test,
          publishability: true,
          training_eligibility: true,
          license: 'MIT',
          rights_notes: 'Test code under MIT license'
        }
        
      when :commit, :issue, :pr
        {
          content_type: @content_type,
          publishability: :internal,
          training_eligibility: false,
          license: 'mixed',
          rights_notes: 'May contain third-party content and personal information'
        }
        
      when :config
        {
          content_type: :config,
          publishability: false,
          training_eligibility: false,
          license: 'proprietary',
          rights_notes: 'Configuration may contain sensitive data'
        }
        
      else
        {
          content_type: :unknown,
          publishability: :review_required,
          training_eligibility: false,
          license: 'unknown',
          rights_notes: 'Requires manual review'
        }
      end
    end
    
    def requires_redaction?
      return false unless @content
      
      # Check for patterns that need redaction
      contains_email? || contains_api_key? || contains_ip_address?
    end
    
    def redact_sensitive_data
      return nil unless @content
      
      redacted = @content.dup
      
      # Redact email addresses
      redacted.gsub!(/[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+/i, '[REDACTED_EMAIL]')
      
      # Redact API keys (long alphanumeric strings)
      redacted.gsub!(/(?<![a-z0-9])[A-Z0-9_\-]{32,}(?![a-z0-9])/i, '[REDACTED_KEY]')
      
      # Redact IP addresses
      redacted.gsub!(/\b(?:\d{1,3}\.){3}\d{1,3}\b/, '[REDACTED_IP]')
      
      # Redact AWS-style keys
      redacted.gsub!(/AKIA[0-9A-Z]{16}/, '[REDACTED_AWS_KEY]')
      
      # Redact bearer tokens
      redacted.gsub!(/bearer\s+[a-z0-9\-._~+\/]+=*/i, 'bearer [REDACTED_TOKEN]')
      
      redacted
    end
    
    def should_quarantine?
      return true if @content_type == :config
      return true if @file_path.match?(/\.(env|key|pem|crt)$/i)
      return true if @content&.match?(/BEGIN (RSA |DSA |EC )?PRIVATE KEY/)
      
      false
    end
    
    def quarantine_reason
      return 'Configuration file with potential secrets' if @content_type == :config
      return 'Private key file' if @file_path.match?(/\.(key|pem)$/i)
      return 'Environment file' if @file_path.match?(/\.env/i)
      return 'Contains private key' if @content&.match?(/PRIVATE KEY/)
      
      'Security precaution'
    end
    
    def contains_email?
      return false unless @content
      @content.match?(/[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+/i)
    end
    
    def contains_api_key?
      return false unless @content
      
      # Various API key patterns
      @content.match?(/(?<![a-z0-9])[A-Z0-9_\-]{32,}(?![a-z0-9])/i) ||
        @content.match?(/AKIA[0-9A-Z]{16}/) ||  # AWS
        @content.match?(/sk_live_[0-9a-zA-Z]{24,}/) ||  # Stripe
        @content.match?(/xox[baprs]-[0-9a-zA-Z\-]+/)  # Slack
    end
    
    def contains_ip_address?
      return false unless @content
      @content.match?(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)
    end
  end
end