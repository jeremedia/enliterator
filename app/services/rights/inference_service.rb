# frozen_string_literal: true

module Rights
  # Service to infer rights and provenance from data items
  # Uses multiple signals including:
  # - File metadata
  # - Content analysis
  # - Source patterns
  # - License indicators
  class InferenceService
    LICENSE_PATTERNS = {
      'cc0' => /(?:CC0|Creative Commons Zero|Public Domain)/i,
      'cc_by' => /CC[\s-]?BY(?!-)/i,
      'cc_by_sa' => /CC[\s-]?BY[\s-]?SA/i,
      'cc_by_nc' => /CC[\s-]?BY[\s-]?NC(?!-SA)/i,
      'cc_by_nc_sa' => /CC[\s-]?BY[\s-]?NC[\s-]?SA/i,
      'cc_by_nd' => /CC[\s-]?BY[\s-]?ND/i,
      'cc_by_nc_nd' => /CC[\s-]?BY[\s-]?NC[\s-]?ND/i,
      'public_domain' => /public domain|no rights reserved/i,
      'proprietary' => /(?:copyright|©|\(c\)|all rights reserved)/i
    }.freeze

    CONSENT_PATTERNS = {
      'explicit_consent' => /I (?:consent|agree|authorize|permit)/i,
      'implicit_consent' => /by (?:submitting|posting|uploading)/i,
      'no_consent' => /(?:do not|don't) (?:consent|agree|authorize)/i
    }.freeze

    def initialize(ingest_item)
      @item = ingest_item
      @signals = {}
      @confidence_scores = []
    end

    def infer
      collect_signals
      analyze_signals
      
      {
        license: inferred_license,
        consent: inferred_consent,
        method: collection_method,
        collectors: inferred_collectors,
        owner: inferred_owner,
        embargo_until: inferred_embargo,
        custom_terms: custom_terms,
        confidence: overall_confidence,
        inference_method: @signals.keys.join(',')
      }
    end

    private

    def collect_signals
      collect_metadata_signals
      collect_content_signals if @item.content_sample.present?
      collect_path_signals
      collect_source_signals
    end

    def collect_metadata_signals
      return unless @item.metadata.present?

      # Check for explicit license in metadata
      if @item.metadata['license'].present?
        @signals[:metadata_license] = detect_license(@item.metadata['license'])
        @confidence_scores << 0.9
      end

      # Check for author/creator info
      if @item.metadata['author'].present? || @item.metadata['creator'].present?
        @signals[:metadata_owner] = @item.metadata['author'] || @item.metadata['creator']
        @confidence_scores << 0.8
      end

      # Check for rights statement
      if @item.metadata['rights'].present?
        @signals[:metadata_rights] = @item.metadata['rights']
        @confidence_scores << 0.85
      end
    end

    def collect_content_signals
      content = @item.content_sample

      # Scan for license indicators
      LICENSE_PATTERNS.each do |license, pattern|
        if content.match?(pattern)
          @signals[:content_license] = license
          @confidence_scores << 0.7
          break
        end
      end

      # Scan for consent indicators  
      CONSENT_PATTERNS.each do |consent, pattern|
        if content.match?(pattern)
          @signals[:content_consent] = consent
          @confidence_scores << 0.6
          break
        end
      end

      # Check for copyright notices
      if match = content.match(/(?:Copyright|©|\(c\))\s*(\d{4})?\s*(.+?)(?:\.|$)/i)
        @signals[:copyright_notice] = {
          year: match[1],
          owner: match[2]&.strip
        }
        @confidence_scores << 0.75
      end
    end

    def collect_path_signals
      path = @item.file_path
      return unless path.present?

      # Check for license files in path
      if path.match?(/LICENSE|COPYING|COPYRIGHT/i)
        @signals[:path_license_file] = true
        @confidence_scores << 0.8
      end

      # Check for public/open directories
      if path.match?(/(?:public|open|shared|commons)/i)
        @signals[:path_public] = true
        @confidence_scores << 0.5
      end

      # Check for private/restricted directories
      if path.match?(/(?:private|restricted|confidential)/i)
        @signals[:path_restricted] = true
        @confidence_scores << 0.6
      end
    end

    def collect_source_signals
      # Source-specific inference rules
      case @item.source_type
      when 'upload'
        @signals[:source_upload] = true
        @signals[:implicit_consent] = true
        @confidence_scores << 0.7
      when 'api'
        @signals[:source_api] = true
        @signals[:method] = 'api_collection'
        @confidence_scores << 0.8
      when 'scrape'
        @signals[:source_scrape] = true
        @signals[:method] = 'web_scraping'
        @confidence_scores << 0.4
      end
    end

    def analyze_signals
      # Reconcile conflicting signals
      if @signals[:path_restricted] && @signals[:path_public]
        @confidence_scores.map! { |score| score * 0.7 }
      end

      # Boost confidence for multiple consistent signals
      license_signals = @signals.keys.count { |k| k.to_s.include?('license') }
      if license_signals > 1
        @confidence_scores << 0.85
      end
    end

    def inferred_license
      # Priority order for license inference
      @signals[:metadata_license] ||
        @signals[:content_license] ||
        (@signals[:copyright_notice] ? 'proprietary' : nil) ||
        (@signals[:path_public] ? 'unspecified' : nil) ||
        'unspecified'
    end

    def inferred_consent
      # Priority order for consent inference
      return @signals[:content_consent] if @signals[:content_consent]
      return 'implicit_consent' if @signals[:implicit_consent]
      return 'no_consent' if @signals[:path_restricted]
      'unknown'
    end

    def collection_method
      @signals[:method] || 
        (@signals[:source_upload] ? 'user_upload' : nil) ||
        'automated_ingestion'
    end

    def inferred_collectors
      collectors = []
      collectors << 'system' if @signals[:source_api]
      collectors << 'user' if @signals[:source_upload]
      collectors << @item.source_hash if collectors.empty?
      collectors
    end

    def inferred_owner
      @signals[:metadata_owner] ||
        @signals[:copyright_notice]&.dig(:owner) ||
        (@signals[:metadata_rights]&.match(/by (.+?)(?:\.|,|;|$)/i)&.captures&.first)
    end

    def inferred_embargo
      return nil unless @signals[:copyright_notice]&.dig(:year)
      
      year = @signals[:copyright_notice][:year].to_i
      current_year = Time.current.year
      
      # Simple embargo logic: recent works may have embargo
      if year >= current_year - 2
        Time.current + 6.months
      end
    end

    def custom_terms
      terms = {}
      
      if @signals[:metadata_rights]
        terms['rights_statement'] = @signals[:metadata_rights]
      end
      
      if @signals[:copyright_notice]
        terms['copyright'] = @signals[:copyright_notice]
      end
      
      terms
    end

    def overall_confidence
      return 0.0 if @confidence_scores.empty?
      
      # Weighted average with penalty for few signals
      avg = @confidence_scores.sum / @confidence_scores.size.to_f
      signal_count_factor = [1.0, @confidence_scores.size / 5.0].min
      
      (avg * signal_count_factor).round(2)
    end

    def detect_license(text)
      LICENSE_PATTERNS.each do |license, pattern|
        return license if text.match?(pattern)
      end
      'custom'
    end
  end
end