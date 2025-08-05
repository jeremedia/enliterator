# app/jobs/deliverables/generation_job.rb
module Deliverables
  class GenerationJob < ApplicationJob
    queue_as :default

    def perform(batch_id, options = {})
      @batch_id = batch_id
      @options = default_options.merge(options.symbolize_keys)
      @output_dir = Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}")
      @errors = []
      @results = {}
      
      Rails.logger.info "Starting deliverables generation for batch #{batch_id}"
      
      # Validate batch is ready
      unless validate_batch_ready?
        Rails.logger.error "Batch #{batch_id} not ready for deliverables generation"
        return { success: false, error: "Batch not ready", batch_id: batch_id }
      end
      
      # Create output directory structure
      setup_output_directories
      
      # Generate all deliverables
      generate_graph_exports if @options[:include_graph]
      generate_prompt_packs if @options[:include_prompts]
      generate_evaluation_bundle if @options[:include_evaluation]
      calculate_refresh_schedule if @options[:include_refresh]
      export_formats if @options[:include_formats]
      
      # Generate manifest and README
      generate_manifest
      generate_readme
      
      # Package deliverables if requested
      package_deliverables if @options[:create_archive]
      
      # Update batch status
      update_batch_status
      
      # Return results
      {
        success: @errors.empty?,
        batch_id: batch_id,
        output_dir: @output_dir.to_s,
        results: @results,
        errors: @errors,
        generated_at: Time.current.iso8601
      }
    rescue => e
      Rails.logger.error "Deliverables generation failed for batch #{batch_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      {
        success: false,
        batch_id: batch_id,
        error: e.message,
        backtrace: e.backtrace.first(5)
      }
    end

    private

    def default_options
      {
        include_graph: true,
        include_prompts: true,
        include_evaluation: true,
        include_refresh: true,
        include_formats: true,
        formats: ['json_ld', 'graphml', 'markdown'],
        rights_filter: 'public',
        create_archive: true
      }
    end

    def validate_batch_ready?
      batch = IngestBatch.find(@batch_id)
      return false unless batch
      
      # Check literacy score
      unless batch.literacy_score && batch.literacy_score >= 70
        @errors << "Literacy score (#{batch.literacy_score || 0}) below threshold (70)"
        return false
      end
      
      # Check graph is populated
      entity_count = %w[Idea Manifest Experience].sum do |pool|
        pool.constantize.where(ingest_batch_id: @batch_id).count
      end
      
      if entity_count == 0
        @errors << "No entities found in batch"
        return false
      end
      
      true
    rescue => e
      @errors << "Validation failed: #{e.message}"
      false
    end

    def setup_output_directories
      FileUtils.mkdir_p(@output_dir)
      
      %w[graph_exports prompt_packs evaluation_bundles exports].each do |subdir|
        FileUtils.mkdir_p(File.join(@output_dir, subdir))
      end
      
      Rails.logger.info "Created output directories at #{@output_dir}"
    end

    def generate_graph_exports
      Rails.logger.info "Generating graph exports..."
      
      begin
        exporter = GraphExporter.new(@batch_id, 
                                    rights_filter: @options[:rights_filter],
                                    output_dir: File.join(@output_dir, 'graph_exports'))
        
        result = exporter.call
        @results[:graph_exports] = result
        
        Rails.logger.info "Graph exports completed: #{result.keys.count} files generated"
      rescue => e
        @errors << "Graph export failed: #{e.message}"
        Rails.logger.error "Graph export error: #{e.message}"
      end
    end

    def generate_prompt_packs
      Rails.logger.info "Generating prompt packs..."
      
      begin
        generator = PromptPackGenerator.new(@batch_id,
                                           output_dir: File.join(@output_dir, 'prompt_packs'))
        
        result = generator.call
        @results[:prompt_packs] = result
        
        total_prompts = result.values.select { |v| v.is_a?(Hash) && v[:prompt_count] }
                                    .sum { |v| v[:prompt_count] }
        
        Rails.logger.info "Prompt packs completed: #{total_prompts} prompts generated"
      rescue => e
        @errors << "Prompt pack generation failed: #{e.message}"
        Rails.logger.error "Prompt pack error: #{e.message}"
      end
    end

    def generate_evaluation_bundle
      Rails.logger.info "Generating evaluation bundle..."
      
      begin
        bundler = EvaluationBundler.new(@batch_id,
                                       output_dir: File.join(@output_dir, 'evaluation_bundles'))
        
        result = bundler.call
        @results[:evaluation_bundle] = result
        
        # Validate the bundle
        validation = bundler.validate
        if validation[:valid]
          Rails.logger.info "Evaluation bundle completed and validated"
        else
          @errors << "Evaluation bundle validation failed: #{validation[:errors].join(', ')}"
        end
      rescue => e
        @errors << "Evaluation bundle generation failed: #{e.message}"
        Rails.logger.error "Evaluation bundle error: #{e.message}"
      end
    end

    def calculate_refresh_schedule
      Rails.logger.info "Calculating refresh schedule..."
      
      begin
        calculator = RefreshCalculator.new(@batch_id, output_dir: @output_dir)
        
        result = calculator.call
        @results[:refresh_schedule] = result
        
        Rails.logger.info "Refresh schedule calculated: #{result[:recommended_cadence][:recommended_cadence]} cadence recommended"
      rescue => e
        @errors << "Refresh calculation failed: #{e.message}"
        Rails.logger.error "Refresh calculation error: #{e.message}"
      end
    end

    def export_formats
      Rails.logger.info "Exporting to multiple formats..."
      
      @results[:format_exports] = {}
      
      @options[:formats].each do |format|
        begin
          Rails.logger.info "Exporting to #{format}..."
          
          exporter = FormatExporter.new(@batch_id,
                                       format: format,
                                       output_dir: File.join(@output_dir, 'exports'))
          
          result = exporter.call
          @results[:format_exports][format] = result
          
          Rails.logger.info "#{format} export completed"
        rescue => e
          @errors << "#{format} export failed: #{e.message}"
          Rails.logger.error "#{format} export error: #{e.message}"
        end
      end
    end

    def generate_manifest
      Rails.logger.info "Generating manifest..."
      
      manifest = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch: {
          id: @batch_id,
          name: IngestBatch.find(@batch_id).name,
          literacy_score: IngestBatch.find(@batch_id).literacy_score,
          status: 'deliverables_generated'
        },
        deliverables: {
          graph_exports: list_files('graph_exports'),
          prompt_packs: list_files('prompt_packs'),
          evaluation_bundles: list_files('evaluation_bundles'),
          format_exports: list_files('exports')
        },
        statistics: collect_statistics,
        options: @options,
        errors: @errors,
        checksums: generate_checksums
      }
      
      filepath = File.join(@output_dir, 'manifest.json')
      File.write(filepath, JSON.pretty_generate(manifest))
      
      @results[:manifest] = {
        filename: 'manifest.json',
        path: filepath
      }
      
      Rails.logger.info "Manifest generated"
    end

    def generate_readme
      Rails.logger.info "Generating README..."
      
      batch = IngestBatch.find(@batch_id)
      
      readme = []
      readme << "# Enliterated Dataset Deliverables"
      readme << ""
      readme << "## Batch Information"
      readme << "- **Batch ID**: #{batch.id}"
      readme << "- **Batch Name**: #{batch.name}"
      readme << "- **Literacy Score**: #{batch.literacy_score}"
      readme << "- **Generated**: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      readme << ""
      
      readme << "## Contents"
      readme << ""
      readme << "### 📊 Graph Exports (`graph_exports/`)"
      readme << "- `graph_public.cypher` - Neo4j graph dump (public content only)"
      readme << "- `query_templates.cypher` - Common query patterns"
      readme << "- `statistics.json` - Graph statistics and metrics"
      readme << "- `path_catalog.json` - Textized path examples"
      readme << "- `metadata.json` - Export metadata"
      readme << ""
      
      readme << "### 💬 Prompt Packs (`prompt_packs/`)"
      readme << "- `discovery_prompts.json` - Entity connection discovery"
      readme << "- `exploration_prompts.json` - Deep entity exploration"
      readme << "- `synthesis_prompts.json` - Multi-entity synthesis"
      readme << "- `temporal_prompts.json` - Time-based queries"
      readme << "- `spatial_prompts.json` - Location-based queries"
      readme << "- `examples.jsonl` - Example completions"
      readme << ""
      
      readme << "### 🧪 Evaluation Bundle (`evaluation_bundles/`)"
      readme << "- `test_questions.json` - Evaluation questions"
      readme << "- `expected_answers.json` - Ground truth answers"
      readme << "- `groundedness_tests.json` - Citation validation"
      readme << "- `rights_compliance_tests.json` - Rights enforcement"
      readme << "- `coverage_tests.json` - Dataset coverage"
      readme << "- `path_accuracy_tests.json` - Relationship validation"
      readme << "- `temporal_consistency_tests.json` - Time consistency"
      readme << "- `evaluation_rubric.json` - Scoring criteria"
      readme << "- `baseline_scores.json` - Expected performance"
      readme << ""
      
      readme << "### 📁 Format Exports (`exports/`)"
      if @options[:formats].include?('json_ld')
        readme << "- `graph.jsonld` - JSON-LD semantic format"
      end
      if @options[:formats].include?('graphml')
        readme << "- `graph.graphml` - GraphML for analysis tools"
      end
      if @options[:formats].include?('rdf')
        readme << "- `graph.ttl` - RDF Turtle format"
      end
      if @options[:formats].include?('csv')
        readme << "- `*_entities.csv` - CSV exports by pool"
        readme << "- `relationships.csv` - All relationships"
      end
      if @options[:formats].include?('markdown')
        readme << "- `dataset_documentation.md` - Human-readable docs"
      end
      if @options[:formats].include?('sql')
        readme << "- `database.sql` - SQL database dump"
      end
      readme << ""
      
      readme << "### 📅 Refresh Schedule"
      if @results[:refresh_schedule]
        cadence = @results[:refresh_schedule][:recommended_cadence][:recommended_cadence]
        readme << "- **Recommended Cadence**: #{cadence}"
        readme << "- **Next Refresh**: #{@results[:refresh_schedule][:refresh_schedule][:next_refresh]}"
        readme << "- **Configuration**: See `refresh_schedule.json`"
      end
      readme << ""
      
      readme << "## Quick Start"
      readme << ""
      readme << "### Loading the Graph"
      readme << "```bash"
      readme << "# Neo4j"
      readme << "cypher-shell < graph_exports/graph_public.cypher"
      readme << ""
      readme << "# Python with networkx"
      readme << "import networkx as nx"
      readme << "G = nx.read_graphml('exports/graph.graphml')"
      readme << "```"
      readme << ""
      
      readme << "### Using Prompts"
      readme << "```python"
      readme << "import json"
      readme << ""
      readme << "# Load discovery prompts"
      readme << "with open('prompt_packs/discovery_prompts.json') as f:"
      readme << "    prompts = json.load(f)"
      readme << ""
      readme << "# Use with OpenAI API"
      readme << "for prompt in prompts[:5]:"
      readme << "    # Replace placeholders and send to API"
      readme << "    pass"
      readme << "```"
      readme << ""
      
      readme << "### Running Evaluations"
      readme << "```python"
      readme << "# Load test questions and answers"
      readme << "with open('evaluation_bundles/test_questions.json') as f:"
      readme << "    questions = json.load(f)"
      readme << ""
      readme << "with open('evaluation_bundles/expected_answers.json') as f:"
      readme << "    answers = json.load(f)"
      readme << ""
      readme << "# Evaluate your system"
      readme << "# Compare responses to expected answers"
      readme << "```"
      readme << ""
      
      if @errors.any?
        readme << "## ⚠️ Generation Warnings"
        readme << ""
        @errors.each do |error|
          readme << "- #{error}"
        end
        readme << ""
      end
      
      readme << "## License & Rights"
      readme << ""
      readme << "This dataset includes rights tracking for all entities. Please respect:"
      readme << "- **Publishability flags** for public sharing"
      readme << "- **Training eligibility** for model training"
      readme << "- See individual entity rights in exported files"
      readme << ""
      
      readme << "---"
      readme << "*Generated by Enliterator v1.0.0 - Stage 8: Autogenerated Deliverables*"
      readme << ""
      
      filepath = File.join(@output_dir, 'README.md')
      File.write(filepath, readme.join("\n"))
      
      @results[:readme] = {
        filename: 'README.md',
        path: filepath
      }
      
      Rails.logger.info "README generated"
    end

    def package_deliverables
      Rails.logger.info "Creating deliverables archive..."
      
      archive_name = "enliterator_batch_#{@batch_id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.tar.gz"
      archive_path = Rails.root.join('tmp', archive_name)
      
      # Create tar.gz archive
      system("cd #{File.dirname(@output_dir)} && tar -czf #{archive_path} #{File.basename(@output_dir)}")
      
      if File.exist?(archive_path)
        @results[:archive] = {
          filename: archive_name,
          path: archive_path.to_s,
          size: File.size(archive_path)
        }
        
        Rails.logger.info "Archive created: #{archive_name} (#{(File.size(archive_path) / 1024.0 / 1024.0).round(2)} MB)"
      else
        @errors << "Failed to create archive"
      end
    end

    def update_batch_status
      batch = IngestBatch.find(@batch_id)
      
      if @errors.empty?
        batch.update!(
          status: 'deliverables_generated',
          deliverables_generated_at: Time.current,
          deliverables_path: @output_dir.to_s
        )
        
        Rails.logger.info "Batch status updated to 'deliverables_generated'"
      else
        batch.update!(
          status: 'deliverables_partial',
          deliverables_errors: @errors
        )
        
        Rails.logger.warn "Batch status updated to 'deliverables_partial' due to errors"
      end
    rescue => e
      Rails.logger.error "Failed to update batch status: #{e.message}"
    end

    def list_files(directory)
      dir_path = File.join(@output_dir, directory)
      return [] unless File.directory?(dir_path)
      
      Dir.glob(File.join(dir_path, '*')).map do |filepath|
        {
          filename: File.basename(filepath),
          size: File.size(filepath),
          modified: File.mtime(filepath).iso8601
        }
      end
    end

    def collect_statistics
      stats = {
        total_files: 0,
        total_size: 0,
        by_category: {}
      }
      
      %w[graph_exports prompt_packs evaluation_bundles exports].each do |category|
        files = list_files(category)
        stats[:by_category][category] = {
          file_count: files.count,
          total_size: files.sum { |f| f[:size] }
        }
        stats[:total_files] += files.count
        stats[:total_size] += files.sum { |f| f[:size] }
      end
      
      stats[:total_size_mb] = (stats[:total_size] / 1024.0 / 1024.0).round(2)
      stats
    end

    def generate_checksums
      require 'digest'
      
      checksums = {}
      
      Dir.glob(File.join(@output_dir, '**', '*')).select { |f| File.file?(f) }.each do |filepath|
        relative_path = filepath.sub(@output_dir.to_s + '/', '')
        checksums[relative_path] = Digest::SHA256.file(filepath).hexdigest
      end
      
      checksums
    end
  end
end