# frozen_string_literal: true

module FineTune
  # Service to build training datasets for fine-tuning OpenAI models
  # Generates JSONL files with different task types for teaching the model
  # about the canon, verbs, and path narration
  class DatasetBuilder < ApplicationService
    TASK_TYPES = %w[
      canon_map
      path_text
      route
      normalize
      rights_style
      gap_awareness
    ].freeze
    
    TRAIN_VAL_TEST_SPLIT = [0.8, 0.1, 0.1].freeze
    MIN_EXAMPLES_PER_TASK = 50
    MAX_EXAMPLES_PER_TASK = 1000
    
    attr_reader :batch_id, :output_dir, :task_filters
    
    def initialize(batch_id:, output_dir: nil, task_filters: nil)
      @batch_id = batch_id
      @output_dir = output_dir || Rails.root.join('tmp', 'fine_tune', "batch_#{batch_id}")
      @task_filters = task_filters || TASK_TYPES
      @examples = []
      
      FileUtils.mkdir_p(@output_dir)
    end
    
    def call
      validate_batch!
      
      Rails.logger.info "Building fine-tune dataset for batch #{batch_id}"
      
      # Generate examples for each task type
      task_filters.each do |task_type|
        Rails.logger.info "Generating #{task_type} examples..."
        
        case task_type
        when 'canon_map'
          generate_canon_mapping_examples
        when 'path_text'
          generate_path_narration_examples
        when 'route'
          generate_tool_routing_examples
        when 'normalize'
          generate_query_normalization_examples
        when 'rights_style'
          generate_rights_aware_examples
        when 'gap_awareness'
          generate_gap_detection_examples
        end
      end
      
      # Split into train/val/test
      split_datasets
      
      # Write JSONL files
      write_jsonl_files
      
      # Generate metadata
      generate_metadata
    end
    
    private
    
    def validate_batch!
      @batch = IngestBatch.find(batch_id)
      raise ArgumentError, "Batch not found: #{batch_id}" unless @batch
      raise ArgumentError, "Batch not ready (literacy score < 70)" if @batch.literacy_score.to_f < 70
    end
    
    # Task 1: Canonical term mapping
    def generate_canon_mapping_examples
      # Get lexicon entries with surface forms
      lexicon_entries = Lexicon.where(ingest_batch_id: batch_id)
                               .where.not(surface_forms: nil)
      
      lexicon_entries.find_each do |entry|
        # Map surface forms to canonical terms
        entry.surface_forms.each do |surface_form|
          @examples << {
            task: 'canon_map',
            input: surface_form,
            output: {
              canonical: entry.canonical_term,
              pool: entry.pool_type,
              description: entry.canonical_description
            }.to_json
          }
        end
        
        # Include negative examples if present
        entry.negative_surface_forms&.each do |negative_form|
          @examples << {
            task: 'canon_map',
            input: negative_form,
            output: {
              canonical: nil,
              pool: nil,
              note: "Not a valid term for #{entry.canonical_term}"
            }.to_json
          }
        end
      end
    end
    
    # Task 2: Path narration from graph structures
    def generate_path_narration_examples
      # Query Neo4j for interesting paths
      neo4j_session = Neo4j::Driver::GraphDatabase.driver(
        ENV.fetch('NEO4J_URL', 'bolt://127.0.0.1:7687'),
        Neo4j::Driver::AuthTokens.basic('neo4j', 'cheese28')
      ).session
      
      begin
        # Find paths of length 2-5 between different pool types
        query = <<~CYPHER
          MATCH path = (n1)-[r1]->(n2)-[r2*0..3]->(n3)
          WHERE n1.ingest_batch_id = $batch_id
            AND n2.ingest_batch_id = $batch_id
            AND n3.ingest_batch_id = $batch_id
            AND labels(n1)[0] <> labels(n3)[0]
          RETURN path
          LIMIT 500
        CYPHER
        
        result = neo4j_session.run(query, batch_id: batch_id)
        
        result.each do |record|
          path = record[:path]
          nodes = extract_nodes_from_path(path)
          edges = extract_edges_from_path(path)
          
          # Build path narration
          path_text = build_path_sentence(nodes, edges)
          
          @examples << {
            task: 'path_text',
            input: {
              nodes: nodes.map { |n| "#{n[:label]}:#{n[:name]}" },
              edges: edges.map { |e| e[:verb] }
            }.to_json,
            output: path_text
          }
        end
      ensure
        neo4j_session.close
      end
    end
    
    # Task 3: Tool routing based on intent
    def generate_tool_routing_examples
      # Define routing patterns
      routing_patterns = [
        {
          intent: "find camps near a specific location",
          tool: "location_neighbors",
          params_template: { camp_name: "{{camp}}", year: "{{year}}", radius: "adjacent" }
        },
        {
          intent: "search for ideas about radical inclusion",
          tool: "search",
          params_template: { query: "{{query}}", pools: ["idea"], diversify_by_pool: true }
        },
        {
          intent: "what connects two concepts",
          tool: "bridge",
          params_template: { a: "{{concept1}}", b: "{{concept2}}", top_k: 10 }
        },
        {
          intent: "extract entities from text",
          tool: "extract_and_link",
          params_template: { text: "{{text}}", mode: "extract" }
        },
        {
          intent: "get full details about an entity",
          tool: "fetch",
          params_template: { id: "{{entity_id}}", include_relations: true }
        }
      ]
      
      # Generate variations for each pattern
      routing_patterns.each do |pattern|
        # Create 10-20 variations per pattern
        10.times do
          variation = generate_intent_variation(pattern[:intent])
          
          @examples << {
            task: 'route',
            input: { intent: variation }.to_json,
            output: {
              tool: pattern[:tool],
              params: pattern[:params_template]
            }.to_json
          }
        end
      end
    end
    
    # Task 4: Query normalization
    def generate_query_normalization_examples
      normalization_examples = [
        {
          raw: "show me camps near 3:30 portal last few years",
          normalized: "camps near 3:30 Portal, 2020-2024, spatial radius: adjacent"
        },
        {
          raw: "temple of tears experiences",
          normalized: "Experience pool: Temple, keyword: tears, diversify results"
        },
        {
          raw: "burning man principles from 2015",
          normalized: "Idea pool: principles, time: 2015, context: Burning Man"
        },
        {
          raw: "how did the man burn evolve",
          normalized: "Evolutionary pool: Man Burn, show timeline, include versions"
        }
      ]
      
      normalization_examples.each do |example|
        @examples << {
          task: 'normalize',
          input: example[:raw],
          output: example[:normalized]
        }
        
        # Generate variations
        3.times do
          variation = generate_query_variation(example[:raw])
          @examples << {
            task: 'normalize',
            input: variation,
            output: example[:normalized]
          }
        end
      end
    end
    
    # Task 5: Rights-aware phrasing
    def generate_rights_aware_examples
      # Find experiences with different rights levels
      public_experiences = Experience.where(
        ingest_batch_id: batch_id,
        publishability: true,
        training_eligibility: true
      ).limit(20)
      
      restricted_experiences = Experience.where(
        ingest_batch_id: batch_id,
        publishability: false
      ).limit(20)
      
      public_experiences.each do |exp|
        @examples << {
          task: 'rights_style',
          input: "quote experience #{exp.id}",
          output: "Direct quote allowed: '#{exp.narrative_text.truncate(200)}'"
        }
      end
      
      restricted_experiences.each do |exp|
        @examples << {
          task: 'rights_style',
          input: "quote experience #{exp.id}",
          output: "Paraphrase only (rights restricted): #{paraphrase_experience(exp)}"
        }
      end
    end
    
    # Task 6: Gap detection and awareness
    def generate_gap_detection_examples
      # Load gap analysis if available
      gap_report_path = Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}", 'gap_analysis.json')
      
      if File.exist?(gap_report_path)
        gaps = JSON.parse(File.read(gap_report_path))
        
        gaps['gaps'].each do |gap|
          @examples << {
            task: 'gap_awareness',
            input: "analyze coverage for #{gap['category']}",
            output: {
              gap_type: gap['type'],
              severity: gap['severity'],
              recommendation: gap['recommendation'],
              affected_pools: gap['affected_pools']
            }.to_json
          }
        end
      end
      
      # Add synthetic gap examples
      synthetic_gaps = [
        {
          query: "temporal coverage 2010-2015",
          gap: { type: "temporal", severity: "high", note: "Sparse data for this period" }
        },
        {
          query: "practical guides for first-timers",
          gap: { type: "pool_coverage", severity: "medium", note: "Limited Practical pool entries" }
        }
      ]
      
      synthetic_gaps.each do |example|
        @examples << {
          task: 'gap_awareness',
          input: example[:query],
          output: example[:gap].to_json
        }
      end
    end
    
    # Helper methods
    
    def extract_nodes_from_path(path)
      path.nodes.map do |node|
        {
          id: node.properties[:id],
          name: node.properties[:canonical_name] || node.properties[:title] || node.properties[:label],
          label: node.labels.first
        }
      end
    end
    
    def extract_edges_from_path(path)
      path.relationships.map do |rel|
        {
          verb: rel.type.downcase,
          source_id: rel.start_node.properties[:id],
          target_id: rel.end_node.properties[:id]
        }
      end
    end
    
    def build_path_sentence(nodes, edges)
      return "" if nodes.empty?
      
      sentence_parts = []
      
      nodes.each_with_index do |node, i|
        node_text = "#{node[:label].capitalize}(#{node[:name]})"
        sentence_parts << node_text
        
        if i < edges.length
          sentence_parts << "→ #{edges[i][:verb]} →"
        end
      end
      
      sentence_parts.join(" ") + "."
    end
    
    def generate_intent_variation(base_intent)
      variations = [
        base_intent,
        "I want to #{base_intent}",
        "Can you help me #{base_intent}?",
        "Please #{base_intent}",
        "Show me how to #{base_intent}"
      ]
      
      variations.sample
    end
    
    def generate_query_variation(base_query)
      # Simple variations - could be enhanced with more sophisticated NLP
      variations = [
        base_query.capitalize,
        "#{base_query} please",
        "can you #{base_query}",
        base_query.gsub(/\s+/, ' ')
      ]
      
      variations.sample
    end
    
    def paraphrase_experience(experience)
      # Simple paraphrasing - in production, might use an LLM for this
      "A participant shared an experience about #{experience.title || 'an event'} " \
      "that occurred around #{experience.observed_at&.year || 'an unspecified time'}."
    end
    
    def split_datasets
      # Shuffle examples
      @examples.shuffle!
      
      # Calculate split points
      total = @examples.length
      train_size = (total * TRAIN_VAL_TEST_SPLIT[0]).to_i
      val_size = (total * TRAIN_VAL_TEST_SPLIT[1]).to_i
      
      @train_examples = @examples[0...train_size]
      @val_examples = @examples[train_size...(train_size + val_size)]
      @test_examples = @examples[(train_size + val_size)..]
    end
    
    def write_jsonl_files
      # Write training set
      write_jsonl(
        File.join(@output_dir, 'train.jsonl'),
        @train_examples
      )
      
      # Write validation set
      write_jsonl(
        File.join(@output_dir, 'validation.jsonl'),
        @val_examples
      )
      
      # Write test set
      write_jsonl(
        File.join(@output_dir, 'test.jsonl'),
        @test_examples
      )
    end
    
    def write_jsonl(filepath, examples)
      File.open(filepath, 'w') do |file|
        examples.each do |example|
          # Convert to OpenAI fine-tuning format
          formatted = {
            messages: [
              {
                role: "system",
                content: system_prompt_for_task(example[:task])
              },
              {
                role: "user",
                content: example[:input]
              },
              {
                role: "assistant",
                content: example[:output]
              }
            ]
          }
          
          file.puts formatted.to_json
        end
      end
      
      Rails.logger.info "Wrote #{examples.length} examples to #{filepath}"
    end
    
    def system_prompt_for_task(task_type)
      case task_type
      when 'canon_map'
        "You map user phrases to canonical terms and pools from the Enliterator knowledge graph."
      when 'path_text'
        "You generate natural language descriptions of paths through the knowledge graph."
      when 'route'
        "You determine which MCP tool to use based on user intent."
      when 'normalize'
        "You normalize user queries into structured search parameters."
      when 'rights_style'
        "You ensure responses respect content rights and privacy settings."
      when 'gap_awareness'
        "You identify gaps and coverage issues in the knowledge graph."
      else
        "You are an assistant for the Enliterator knowledge graph system."
      end
    end
    
    def generate_metadata
      metadata = {
        batch_id: batch_id,
        generated_at: Time.current.iso8601,
        task_types: task_filters,
        example_counts: {
          total: @examples.length,
          train: @train_examples.length,
          validation: @val_examples.length,
          test: @test_examples.length
        },
        task_distribution: @examples.group_by { |e| e[:task] }
                                    .transform_values(&:length),
        output_files: {
          train: 'train.jsonl',
          validation: 'validation.jsonl',
          test: 'test.jsonl'
        }
      }
      
      metadata_path = File.join(@output_dir, 'metadata.json')
      File.write(metadata_path, JSON.pretty_generate(metadata))
      
      Rails.logger.info "Dataset generation complete. Metadata saved to #{metadata_path}"
      
      metadata
    end
  end
end