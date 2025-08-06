# frozen_string_literal: true

module FineTune
  # Stage 9: Build fine-tuning dataset from the knowledge graph
  # This creates training data that teaches the model to understand
  # the specific knowledge domain captured in the EKN
  class DatasetBuilderJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn
      super
      
      log_progress "Building fine-tune dataset for EKN: #{@ekn.name}"
      
      # Only proceed if literacy score is sufficient
      unless @batch.literacy_score && @batch.literacy_score >= 70
        log_progress "Skipping fine-tune: Literacy score (#{@batch.literacy_score || 0}) below minimum 70", level: :warn
        track_metric :skipped, true
        track_metric :reason, "insufficient_literacy_score"
        return
      end
      
      # Build the dataset
      builder = ::FineTune::DatasetBuilder.new(
        ekn: @ekn,
        batch: @batch
      )
      
      log_progress "Generating training examples from graph..."
      
      # Generate different types of training data
      canonical_examples = generate_canonical_mappings(builder)
      path_examples = generate_path_narrations(builder)
      routing_examples = generate_tool_routings(builder)
      normalization_examples = generate_query_normalizations(builder)
      
      total_examples = canonical_examples + path_examples + routing_examples + normalization_examples
      
      log_progress "✅ Generated #{total_examples} training examples"
      
      # Save dataset to file
      dataset_path = save_dataset(builder)
      
      # Track metrics
      track_metric :canonical_examples, canonical_examples
      track_metric :path_examples, path_examples
      track_metric :routing_examples, routing_examples
      track_metric :normalization_examples, normalization_examples
      track_metric :total_examples, total_examples
      track_metric :dataset_path, dataset_path
      
      # Update batch with dataset info
      @batch.update!(
        fine_tune_dataset_path: dataset_path,
        fine_tune_dataset_size: total_examples,
        fine_tune_dataset_created_at: Time.current
      )
      
      log_progress "Dataset saved to: #{dataset_path}"
      
      # Optionally trigger fine-tune job creation
      if ENV['AUTO_CREATE_FINE_TUNE'] == 'true'
        create_fine_tune_job(dataset_path)
      else
        log_progress "Fine-tune job creation disabled. Run manually when ready.", level: :info
      end
    end
    
    private
    
    def generate_canonical_mappings(builder)
      log_progress "Generating canonical term mappings...", level: :debug
      
      count = 0
      @batch.lexicon_entries.find_each do |entry|
        # Map surface forms to canonical terms
        entry.surface_forms&.each do |surface|
          builder.add_example(
            task: 'canon_map',
            input: surface,
            output: {
              canonical: entry.canonical,
              pool: entry.pool
            }
          )
          count += 1
        end
        
        # Map negative forms too (what NOT to match)
        entry.negative_surface_forms&.each do |negative|
          builder.add_example(
            task: 'canon_map_negative',
            input: negative,
            output: {
              canonical: nil,
              reason: "negative_form"
            }
          )
          count += 1
        end
      end
      
      log_progress "Generated #{count} canonical mapping examples", level: :debug
      count
    end
    
    def generate_path_narrations(builder)
      log_progress "Generating path narration examples...", level: :debug
      
      count = 0
      
      # Query Neo4j for interesting paths
      service = Graph::QueryService.new(@ekn.neo4j_database_name)
      
      # Get sample paths of varying lengths
      [2, 3, 4].each do |path_length|
        paths = service.get_sample_paths(length: path_length, limit: 50)
        
        paths.each do |path|
          builder.add_example(
            task: 'path_text',
            input: {
              nodes: path[:nodes],
              edges: path[:edges]
            },
            output: path[:narration]  # Natural language description of the path
          )
          count += 1
        end
      end
      
      log_progress "Generated #{count} path narration examples", level: :debug
      count
    end
    
    def generate_tool_routings(builder)
      log_progress "Generating tool routing examples...", level: :debug
      
      # Generate examples of when to use which MCP tools
      routing_examples = [
        {
          intent: "Find information about #{@ekn.name}",
          tool: "search",
          params: { query: @ekn.name, pools: ['idea', 'manifest'] }
        },
        {
          intent: "Show relationships between concepts",
          tool: "bridge",
          params: { a: "concept1", b: "concept2" }
        },
        {
          intent: "Get details about a specific entity",
          tool: "fetch",
          params: { id: "entity_id", include_relations: true }
        }
      ]
      
      count = 0
      routing_examples.each do |example|
        builder.add_example(
          task: 'route',
          input: { intent: example[:intent] },
          output: {
            tool: example[:tool],
            params: example[:params]
          }
        )
        count += 1
      end
      
      log_progress "Generated #{count} tool routing examples", level: :debug
      count
    end
    
    def generate_query_normalizations(builder)
      log_progress "Generating query normalization examples...", level: :debug
      
      # Generate examples of normalizing user queries
      count = 0
      
      # Sample query patterns
      query_patterns = [
        { raw: "show me stuff about X", normalized: "search for X entities across all pools" },
        { raw: "what connects A and B", normalized: "find bridge paths between A and B" },
        { raw: "tell me about Y", normalized: "fetch entity Y with relationships" }
      ]
      
      query_patterns.each do |pattern|
        builder.add_example(
          task: 'normalize',
          input: pattern[:raw],
          output: pattern[:normalized]
        )
        count += 1
      end
      
      log_progress "Generated #{count} query normalization examples", level: :debug
      count
    end
    
    def save_dataset(builder)
      # Save to JSONL format for OpenAI fine-tuning
      output_dir = Rails.root.join('tmp', 'fine_tune_datasets')
      FileUtils.mkdir_p(output_dir)
      
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      filename = "ekn_#{@ekn.id}_batch_#{@batch.id}_#{timestamp}.jsonl"
      filepath = output_dir.join(filename)
      
      builder.save_to_file(filepath)
      
      filepath.to_s
    end
    
    def create_fine_tune_job(dataset_path)
      log_progress "Creating OpenAI fine-tune job...", level: :info
      
      # This would integrate with OpenAI to create the actual fine-tune job
      # For now, just log that it would be created
      log_progress "Would create fine-tune job with dataset: #{dataset_path}", level: :info
      
      # In production:
      # job = OpenAI::FineTune.create(
      #   training_file: upload_file(dataset_path),
      #   model: 'gpt-4o-mini',
      #   suffix: "ekn-#{@ekn.id}"
      # )
      # @batch.update!(fine_tune_job_id: job.id)
    end
    
    def collect_stage_metrics
      {
        canonical_examples: @metrics[:canonical_examples] || 0,
        path_examples: @metrics[:path_examples] || 0,
        routing_examples: @metrics[:routing_examples] || 0,
        normalization_examples: @metrics[:normalization_examples] || 0,
        total_examples: @metrics[:total_examples] || 0,
        dataset_path: @metrics[:dataset_path],
        literacy_score: @batch.literacy_score
      }
    end
  end
end