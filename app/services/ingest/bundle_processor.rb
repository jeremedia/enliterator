# frozen_string_literal: true

module Ingest
  # Process a dropped bundle (folder/ZIP/URI) and discover files
  class BundleProcessor < ApplicationService
    attr_reader :bundle_path, :pipeline_run, :options

    def initialize(bundle_path, pipeline_run: nil, options: {})
      @bundle_path = bundle_path
      @pipeline_run = pipeline_run
      @options = options
    end

    def call
      validate_bundle!
      
      result = OpenStruct.new(
        files: [],
        metrics: {
          total_size: 0,
          file_types: Hash.new(0),
          discovered_at: Time.current
        }
      )
      
      if File.directory?(bundle_path)
        process_directory(bundle_path, result)
      elsif File.file?(bundle_path) && bundle_path.match?(/\.(zip|tar|gz)$/i)
        process_archive(bundle_path, result)
      elsif bundle_path.match?(/^https?:\/\//)
        process_uri(bundle_path, result)
      else
        raise InvalidBundleError, "Unknown bundle type: #{bundle_path}"
      end
      
      # Deduplicate files by hash
      result.files = deduplicate_files(result.files)
      
      # Record in pipeline run
      pipeline_run&.set_metric("intake.total_files", result.files.count)
      pipeline_run&.set_metric("intake.total_size_bytes", result.metrics[:total_size])
      
      result
    end

    private

    def validate_bundle!
      return if bundle_path.match?(/^https?:\/\//)
      
      unless File.exist?(bundle_path)
        raise InvalidBundleError, "Bundle not found: #{bundle_path}"
      end
    end

    def process_directory(dir_path, result)
      Dir.glob(File.join(dir_path, "**", "*")).each do |file_path|
        next unless File.file?(file_path)
        next if should_skip_file?(file_path)
        
        file_info = extract_file_info(file_path)
        result.files << file_info
        result.metrics[:total_size] += file_info[:size]
        result.metrics[:file_types][file_info[:mime_type]] += 1
      end
    end

    def process_archive(archive_path, result)
      # TODO: Implement archive extraction
      # For now, just treat as single file
      file_info = extract_file_info(archive_path)
      result.files << file_info
      result.metrics[:total_size] += file_info[:size]
      result.metrics[:file_types][file_info[:mime_type]] += 1
    end

    def process_uri(uri, result)
      # TODO: Implement URI fetching
      raise NotImplementedError, "URI processing not yet implemented"
    end

    def extract_file_info(file_path)
      stat = File.stat(file_path)
      content_hash = calculate_file_hash(file_path)
      
      {
        path: file_path,
        relative_path: file_path.sub(/^#{Regexp.escape(bundle_path)}\/?/, ""),
        size: stat.size,
        mime_type: detect_mime_type(file_path),
        content_hash: content_hash,
        modified_at: stat.mtime,
        metadata: {
          extension: File.extname(file_path),
          directory: File.dirname(file_path)
        }
      }
    end

    def calculate_file_hash(file_path)
      Digest::SHA256.file(file_path).hexdigest
    rescue StandardError => e
      Rails.logger.error "Failed to hash file #{file_path}: #{e.message}"
      nil
    end

    def detect_mime_type(file_path)
      # Simple MIME type detection by extension
      # In production, use a proper MIME detection library
      extension = File.extname(file_path).downcase
      
      case extension
      when ".txt", ".md"
        "text/plain"
      when ".json"
        "application/json"
      when ".xml"
        "application/xml"
      when ".pdf"
        "application/pdf"
      when ".jpg", ".jpeg"
        "image/jpeg"
      when ".png"
        "image/png"
      when ".csv"
        "text/csv"
      when ".html", ".htm"
        "text/html"
      else
        "application/octet-stream"
      end
    end

    def should_skip_file?(file_path)
      # Skip hidden files and common system files
      basename = File.basename(file_path)
      
      return true if basename.start_with?(".")
      return true if basename.match?(/^(thumbs\.db|desktop\.ini|\.ds_store)$/i)
      return true if file_path.include?("__MACOSX")
      
      false
    end

    def deduplicate_files(files)
      seen_hashes = Set.new
      
      files.reject do |file_info|
        hash = file_info[:content_hash]
        next false if hash.nil?
        
        if seen_hashes.include?(hash)
          Rails.logger.info "Skipping duplicate file: #{file_info[:path]}"
          true
        else
          seen_hashes.add(hash)
          false
        end
      end
    end
  end

  class InvalidBundleError < StandardError; end
end