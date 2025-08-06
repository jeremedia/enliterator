# frozen_string_literal: true

module Pipeline
  # High-level orchestrator for managing pipeline runs
  # This is the main entry point for processing data through the 9-stage pipeline
  class Orchestrator
    class << self
      # Process an EKN with source files through the complete pipeline
      def process_ekn(ekn, source_files, options = {})
        Rails.logger.info "Starting pipeline for EKN: #{ekn.name}"
        
        # Create IngestBatch under the EKN
        batch = create_ingest_batch(ekn, source_files, options)
        
        # Create pipeline run
        pipeline_run = EknPipelineRun.create!(
          ekn: ekn,
          ingest_batch: batch,
          options: {
            source_files: source_files.count,
            accumulate: ekn.ingest_batches.count > 1,
            started_by: options[:started_by] || 'manual',
            auto_advance: options.fetch(:auto_advance, true),
            skip_failed_items: options.fetch(:skip_failed_items, false)
          },
          auto_advance: options.fetch(:auto_advance, true),
          skip_failed_items: options.fetch(:skip_failed_items, false)
        )
        
        Rails.logger.info "Created pipeline run ##{pipeline_run.id} for batch ##{batch.id}"
        
        # Start the pipeline!
        pipeline_run.start!
        
        # Return for monitoring
        pipeline_run
      end
      
      # Process the Meta-Enliterator (special case for self-understanding)
      def process_meta_enliterator(options = {})
        # Find or create Meta-Enliterator EKN
        ekn = find_or_create_meta_enliterator
        
        # Gather source files
        source_files = gather_enliterator_source_files
        
        Rails.logger.info "Processing Meta-Enliterator with #{source_files.count} files"
        
        # Process through pipeline
        process_ekn(ekn, source_files, options.merge(started_by: 'meta_enliterator'))
      end
      
      # Monitor a running pipeline
      def monitor(pipeline_run_id)
        run = EknPipelineRun.find(pipeline_run_id)
        run.detailed_status
      end
      
      # Get agent-friendly status
      def agent_status(pipeline_run_id)
        run = EknPipelineRun.find(pipeline_run_id)
        run.agent_status
      end
      
      # Resume a failed or paused pipeline
      def resume(pipeline_run_id)
        run = EknPipelineRun.find(pipeline_run_id)
        
        case run.status
        when 'failed'
          if run.can_retry?
            Rails.logger.info "Retrying pipeline run ##{run.id} from stage #{run.current_stage}"
            run.retry_pipeline!
          else
            raise "Cannot resume - max retries (#{run.retry_count}) reached"
          end
        when 'paused'
          Rails.logger.info "Resuming paused pipeline run ##{run.id}"
          run.start!
        else
          raise "Cannot resume - status is #{run.status}"
        end
        
        run
      end
      
      # Pause a running pipeline
      def pause(pipeline_run_id)
        run = EknPipelineRun.find(pipeline_run_id)
        
        if run.running?
          run.pause!
          Rails.logger.info "Paused pipeline run ##{run.id}"
        else
          raise "Cannot pause - status is #{run.status}"
        end
        
        run
      end
      
      # Get all runs for an EKN
      def runs_for_ekn(ekn_id)
        EknPipelineRun.where(ekn_id: ekn_id)
                      .order(created_at: :desc)
                      .map(&:detailed_status)
      end
      
      # Get currently running pipelines
      def active_runs
        EknPipelineRun.where(status: ['running', 'retrying'])
                      .map(&:detailed_status)
      end
      
      private
      
      def create_ingest_batch(ekn, source_files, options)
        batch = ekn.ingest_batches.create!(
          name: options[:batch_name] || "Batch #{ekn.ingest_batches.count + 1}",
          source_type: options[:source_type] || detect_source_type(source_files),
          status: 'pending',
          metadata: {
            file_count: source_files.count,
            source_paths: source_files.first(10), # Sample for reference
            processing_options: options
          }
        )
        
        # Add files to batch as IngestItems
        source_files.each do |file_path|
          batch.ingest_items.create!(
            file_path: file_path,
            media_type: detect_media_type(file_path),
            triage_status: 'pending'
          )
        end
        
        Rails.logger.info "Created batch ##{batch.id} with #{source_files.count} items"
        
        batch
      end
      
      def find_or_create_meta_enliterator
        Ekn.find_or_create_by!(slug: 'meta-enliterator') do |ekn|
          ekn.name = 'Meta-Enliterator'
          ekn.description = "The Enliterator system's knowledge of itself"
          ekn.status = 'active'
          ekn.domain_type = 'technical'
          ekn.personality = 'helpful_guide'
          ekn.metadata = {
            is_meta: true,
            capabilities: ['explain_ekns', 'guide_creation', 'understand_self']
          }
        end
      end
      
      def gather_enliterator_source_files
        files = []
        
        # Gather all relevant source files
        files += Dir.glob(Rails.root.join('app', '**', '*.rb'))
        files += Dir.glob(Rails.root.join('docs', '**', '*.md'))
        files += Dir.glob(Rails.root.join('lib', '**', '*.rb'))
        files += Dir.glob(Rails.root.join('config', '**', '*.yml'))
        
        # Add key documentation files
        %w[README.md CLAUDE.md Gemfile].each do |file|
          path = Rails.root.join(file)
          files << path.to_s if File.exist?(path)
        end
        
        # Filter out unwanted files
        files.reject! do |f|
          f.include?('/tmp/') || 
          f.include?('/log/') || 
          f.include?('/node_modules/') ||
          f.include?('.git/')
        end
        
        files.uniq
      end
      
      def detect_source_type(files)
        extensions = files.map { |f| File.extname(f).downcase }.uniq
        
        if extensions.all? { |ext| %w[.rb .py .js .java].include?(ext) }
          'codebase'
        elsif extensions.all? { |ext| %w[.md .txt .rst].include?(ext) }
          'documentation'
        elsif extensions.all? { |ext| %w[.yml .yaml .json .xml].include?(ext) }
          'configuration'
        else
          'mixed'
        end
      end
      
      def detect_media_type(file_path)
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
        
        # Document files
        when '.pdf', '.doc', '.docx', '.odt', '.rtf', '.tex', '.epub'
          'document'
        
        # Image files
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
    end
  end
end