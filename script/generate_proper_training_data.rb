#!/usr/bin/env ruby
# Generate proper OpenAI fine-tuning dataset for Meta-EKN

require 'json'
require 'fileutils'

class ProperDatasetGenerator
  def initialize(batch_id: 7)
    @batch_id = batch_id
    @output_dir = Rails.root.join('tmp', 'fine_tune', "batch_#{batch_id}")
    @examples = []
    
    FileUtils.mkdir_p(@output_dir)
  end
  
  def generate!
    puts "Generating proper training dataset for batch #{@batch_id}..."
    
    # Generate examples for each task type
    generate_canon_mapping_examples
    generate_path_narration_examples
    generate_tool_routing_examples
    generate_query_normalization_examples
    generate_rights_style_examples
    generate_gap_detection_examples
    
    # Write the JSONL file in correct OpenAI format
    write_training_file
    
    puts "Dataset generation complete!"
    puts "Total examples: #{@examples.length}"
    puts "Output directory: #{@output_dir}"
    
    @output_dir
  end
  
  private
  
  def generate_canon_mapping_examples
    puts "Generating canonical mapping examples..."
    
    # Use LexiconAndOntology entries
    LexiconAndOntology.where.not(surface_forms: nil).find_each do |entry|
      next if entry.surface_forms.blank?
      
      entry.surface_forms.each do |surface_form|
        @examples << create_chat_example(
          task: 'canon_map',
          user_input: surface_form,
          assistant_output: {
            canonical: entry.term,
            pool: entry.pool_association || 'lexicon',
            description: entry.canonical_description
          }.to_json
        )
      end
    end
    
    puts "  Generated #{@examples.length} canon mapping examples"
  end
  
  def generate_path_narration_examples
    puts "Generating path narration examples..."
    
    # Create sample paths for the Enliterator domain
    sample_paths = [
      {
        nodes: ["Idea:Enliteration", "Manifest:Pipeline", "Practical:DatasetBuilder"],
        edges: ["manifests", "implements"],
        narration: "Idea(Enliteration) → manifests → Manifest(Pipeline) → implements → Practical(DatasetBuilder)."
      },
      {
        nodes: ["Idea:Ten Pool Canon", "Manifest:PoolModels", "Emanation:KnowledgeGraph"],
        edges: ["defines", "produces"],
        narration: "Idea(Ten Pool Canon) → defines → Manifest(PoolModels) → produces → Emanation(KnowledgeGraph)."
      },
      {
        nodes: ["Practical:FineTuning", "Emanation:EKN", "Experience:UserInteraction"],
        edges: ["creates", "enables"],
        narration: "Practical(FineTuning) → creates → Emanation(EKN) → enables → Experience(UserInteraction)."
      }
    ]
    
    sample_paths.each do |path|
      @examples << create_chat_example(
        task: 'path_text',
        user_input: {
          nodes: path[:nodes],
          edges: path[:edges]
        }.to_json,
        assistant_output: path[:narration]
      )
    end
    
    puts "  Generated #{sample_paths.length} path narration examples"
  end
  
  def generate_tool_routing_examples
    puts "Generating tool routing examples..."
    
    routing_patterns = [
      {
        intent: "find camps near a specific location",
        tool: "location_neighbors",
        params: { camp_name: "{{camp}}", year: "{{year}}", radius: "adjacent" }
      },
      {
        intent: "search for ideas about radical inclusion",
        tool: "search",
        params: { query: "{{query}}", pools: ["idea"], diversify_by_pool: true }
      },
      {
        intent: "what connects two concepts",
        tool: "bridge",
        params: { a: "{{concept1}}", b: "{{concept2}}", top_k: 10 }
      },
      {
        intent: "extract entities from text",
        tool: "extract_and_link",
        params: { text: "{{text}}", mode: "extract" }
      },
      {
        intent: "get full details about an entity",
        tool: "fetch",
        params: { id: "{{entity_id}}", include_relations: true }
      }
    ]
    
    routing_patterns.each do |pattern|
      # Create 3 variations per pattern
      3.times do |i|
        variation = case i
                   when 0 then pattern[:intent]
                   when 1 then "I want to #{pattern[:intent]}"
                   when 2 then "Can you help me #{pattern[:intent]}?"
                   end
        
        @examples << create_chat_example(
          task: 'route',
          user_input: { intent: variation }.to_json,
          assistant_output: {
            tool: pattern[:tool],
            params: pattern[:params]
          }.to_json
        )
      end
    end
    
    puts "  Generated #{routing_patterns.length * 3} routing examples"
  end
  
  def generate_query_normalization_examples
    puts "Generating query normalization examples..."
    
    normalization_pairs = [
      {
        raw: "show me camps near 3:30 portal last few years",
        normalized: "camps near 3:30 Portal, 2020-2024, spatial radius: adjacent"
      },
      {
        raw: "enliterator pipeline stages",
        normalized: "Manifest pool: pipeline, keyword: stages, include relationships"
      },
      {
        raw: "how does fine-tuning work",
        normalized: "Practical pool: fine-tuning, show process flow, include documentation"
      },
      {
        raw: "what is the literacy score",
        normalized: "Idea pool: literacy, metric: score, include calculation method"
      }
    ]
    
    normalization_pairs.each do |pair|
      @examples << create_chat_example(
        task: 'normalize',
        user_input: pair[:raw],
        assistant_output: pair[:normalized]
      )
    end
    
    puts "  Generated #{normalization_pairs.length} normalization examples"
  end
  
  def generate_rights_style_examples
    puts "Generating rights-aware examples..."
    
    rights_examples = [
      {
        input: "quote internal documentation",
        output: "Direct quote allowed for internal documentation with training eligibility"
      },
      {
        input: "share proprietary code",
        output: "Paraphrase only - proprietary code requires rights verification"
      },
      {
        input: "describe open source components",
        output: "Full description allowed - open source components are publicly available"
      }
    ]
    
    rights_examples.each do |example|
      @examples << create_chat_example(
        task: 'rights_style',
        user_input: example[:input],
        assistant_output: example[:output]
      )
    end
    
    puts "  Generated #{rights_examples.length} rights examples"
  end
  
  def generate_gap_detection_examples
    puts "Generating gap detection examples..."
    
    gap_examples = [
      {
        query: "coverage for Experience pool",
        gap: {
          type: "pool_coverage",
          severity: "high",
          note: "Experience pool has limited entries - only 0% coverage",
          recommendation: "Extract user stories and testimonials"
        }
      },
      {
        query: "spatial data completeness",
        gap: {
          type: "spatial",
          severity: "medium",
          note: "Spatial coverage at 30% - expected for codebase",
          recommendation: "Add architectural diagrams and deployment topology"
        }
      },
      {
        query: "relationship density",
        gap: {
          type: "connectivity",
          severity: "low",
          note: "Graph connectivity at 91% - excellent coverage",
          recommendation: "Maintain current relationship extraction"
        }
      }
    ]
    
    gap_examples.each do |example|
      @examples << create_chat_example(
        task: 'gap_awareness',
        user_input: example[:query],
        assistant_output: example[:gap].to_json
      )
    end
    
    puts "  Generated #{gap_examples.length} gap detection examples"
  end
  
  def create_chat_example(task:, user_input:, assistant_output:)
    {
      messages: [
        {
          role: "system",
          content: system_prompt_for_task(task)
        },
        {
          role: "user",
          content: user_input
        },
        {
          role: "assistant",
          content: assistant_output
        }
      ]
    }
  end
  
  def system_prompt_for_task(task_type)
    case task_type
    when 'canon_map'
      "You are the Enliterator Knowledge Navigator. Map user phrases to canonical terms and pools from the knowledge graph."
    when 'path_text'
      "You are the Enliterator Knowledge Navigator. Generate natural language descriptions of paths through the knowledge graph using the Relation Verb Glossary."
    when 'route'
      "You are the Enliterator Knowledge Navigator. Determine which MCP tool to use based on user intent."
    when 'normalize'
      "You are the Enliterator Knowledge Navigator. Normalize user queries into structured search parameters with pool filtering and time/space scoping."
    when 'rights_style'
      "You are the Enliterator Knowledge Navigator. Ensure responses respect content rights, training eligibility, and privacy settings."
    when 'gap_awareness'
      "You are the Enliterator Knowledge Navigator. Identify gaps and coverage issues in the knowledge graph, providing severity and recommendations."
    else
      "You are the Enliterator Knowledge Navigator for the meta-enliterated Enliterator system."
    end
  end
  
  def write_training_file
    # Write main training file
    training_file = File.join(@output_dir, 'training_data.jsonl')
    
    File.open(training_file, 'w') do |file|
      @examples.each do |example|
        file.puts example.to_json
      end
    end
    
    puts "Wrote #{@examples.length} examples to #{training_file}"
    
    # Also split into train/validation sets (80/20)
    train_size = (@examples.length * 0.8).to_i
    train_examples = @examples[0...train_size]
    val_examples = @examples[train_size..]
    
    # Write train set
    File.open(File.join(@output_dir, 'train.jsonl'), 'w') do |file|
      train_examples.each { |ex| file.puts ex.to_json }
    end
    
    # Write validation set
    File.open(File.join(@output_dir, 'validation.jsonl'), 'w') do |file|
      val_examples.each { |ex| file.puts ex.to_json }
    end
    
    puts "Split into #{train_examples.length} training and #{val_examples.length} validation examples"
    
    # Write metadata
    metadata = {
      batch_id: @batch_id,
      generated_at: Time.current.iso8601,
      total_examples: @examples.length,
      train_examples: train_examples.length,
      validation_examples: val_examples.length,
      task_distribution: @examples.map { |e| 
        task = JSON.parse(e[:messages][1][:content]) rescue nil
        task.is_a?(Hash) ? (task['task'] || 'unknown') : 'unknown'
      }.tally
    }
    
    File.write(
      File.join(@output_dir, 'metadata.json'),
      JSON.pretty_generate(metadata)
    )
  end
end

# Run the generator
generator = ProperDatasetGenerator.new(batch_id: 7)
output_dir = generator.generate!

puts "\n✅ Dataset generation complete!"
puts "Files created in: #{output_dir}"
puts "\nNext step: Run fine-tuning with:"
puts "  rails runner \"FineTune::Trainer.new(dataset_path: '#{output_dir}/training_data.jsonl').call\""