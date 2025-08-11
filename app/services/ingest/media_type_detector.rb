# frozen_string_literal: true

module Ingest
  # Service for detecting media types and format compatibility 
  # Integrates with TokenAwareMarkitdownService for format support detection
  class MediaTypeDetector < ApplicationService
    
    attr_reader :file_path
    
    def initialize(file_path)
      @file_path = file_path
    end
    
    def call
      {
        media_type: detect_media_type,
        markitdown_supported: markitdown_supported?,
        mime_type: detect_mime_type,
        file_extension: File.extname(file_path).downcase
      }
    end
    
    # Check if file format is supported by MarkItDown
    def markitdown_supported?
      extension = File.extname(file_path).downcase
      TokenAwareMarkitdownService.supported_formats.include?(extension)
    end
    
    private
    
    def detect_media_type
      extension = File.extname(file_path).downcase
      basename = File.basename(file_path).downcase
      
      # First check for specific config file patterns
      if basename.match?(/^(gemfile|rakefile|dockerfile|makefile|procfile|guardfile|capfile|brewfile)/)
        return 'config'
      elsif basename.match?(/\.(yml|yaml)$/) && basename.match?(/(config|settings|database|credentials|secrets)/)
        return 'config'
      elsif basename == 'package.json' || basename == 'composer.json' || basename == 'cargo.toml'
        return 'config'
      end
      
      # Then check by extension
      case extension
      # Source code files
      when '.rb', '.py', '.js', '.ts', '.jsx', '.tsx', '.java', '.go', '.rs', '.cpp', '.c', '.h', 
           '.php', '.swift', '.kt', '.scala', '.clj', '.ex', '.exs', '.erl', '.hs', '.ml', '.fs'
        'code'
      
      # Documentation and text files  
      when '.md', '.txt', '.rst', '.adoc', '.org', '.textile', '.rdoc', '.pod', '.man'
        'text'
      
      # Configuration files
      when '.yml', '.yaml', '.toml', '.ini', '.cfg', '.conf', '.properties', '.env'
        'config'
      
      # Data files
      when '.json', '.xml', '.csv', '.tsv', '.jsonl', '.ndjson'
        # Try to distinguish between config and data based on path/name
        if file_path.include?('/config/') || file_path.include?('/settings/') || 
           basename.match?(/config|settings|manifest/)
          'config'
        else
          'data'
        end
      
      # Document files - Enhanced for MarkItDown support
      when '.pdf', '.doc', '.docx', '.odt', '.rtf', '.tex', '.epub', '.pptx', '.xlsx'
        'document'
      
      # Image files - Enhanced for MarkItDown support  
      when '.jpg', '.jpeg', '.png', '.gif', '.svg', '.ico', '.bmp', '.tiff', '.webp'
        'image'
      
      # Audio files
      when '.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac', '.wma'
        'audio'
      
      # Video files
      when '.mp4', '.mov', '.avi', '.wmv', '.flv', '.mkv', '.webm', '.m4v', '.mpg', '.mpeg'
        'video'
      
      # Binary files
      when '.exe', '.dll', '.so', '.dylib', '.bin', '.dat', '.db', '.sqlite', '.zip', '.tar', '.gz', '.rar'
        'binary'
      
      else
        'unknown'
      end
    end
    
    def detect_mime_type
      extension = File.extname(file_path).downcase
      
      case extension
      when '.txt', '.md', '.rst'
        'text/plain'
      when '.json'
        'application/json'
      when '.xml'
        'application/xml'
      when '.pdf'
        'application/pdf'
      when '.doc'
        'application/msword'
      when '.docx'
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      when '.pptx'
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
      when '.xlsx'
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      when '.odt'
        'application/vnd.oasis.opendocument.text'
      when '.rtf'
        'application/rtf'
      when '.jpg', '.jpeg'
        'image/jpeg'
      when '.png'
        'image/png'
      when '.gif'
        'image/gif'
      when '.svg'
        'image/svg+xml'
      when '.bmp'
        'image/bmp'
      when '.html', '.htm'
        'text/html'
      when '.csv'
        'text/csv'
      when '.yml', '.yaml'
        'application/yaml'
      else
        'application/octet-stream'
      end
    end
  end
end