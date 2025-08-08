# frozen_string_literal: true

# PURPOSE: Stage 9 of the 9-stage pipeline - Fine-tune Dataset Building
# Builds training data for fine-tuning a model on the knowledge graph
#
# Inputs: Complete knowledge graph with all previous stages
# Outputs: JSONL training dataset for fine-tuning

module FineTune
  class DatasetBuilderJob < Pipeline::BaseJob
    queue_as :pipeline
    
    def perform(pipeline_run_id)
      # BaseJob sets up @pipeline_run, @batch, @ekn via around_perform
      # Do NOT call super - BaseJob uses around_perform to wrap this method
      
      log_progress "Starting fine-tune dataset building"
      
      @training_examples = []
      
      begin
        # Generate training examples
        generate_canonical_term_examples
        generate_path_narration_examples
        generate_tool_routing_examples
        
        # Save dataset
        dataset_path = save_dataset
        
        log_progress "✅ Fine-tune dataset complete: #{@training_examples.size} examples"
        
        # Submit to OpenAI for fine-tuning
        log_progress "Submitting dataset to OpenAI for fine-tuning..."
        trainer = FineTune::Trainer.new(
          dataset_path: dataset_path,
          suffix: "enliterator-ekn-#{@ekn.id}"
        )
        result = trainer.call
        
        if result[:success]
          log_progress "✅ Fine-tune job created: #{result[:job_id]}"
          track_metric :fine_tune_job_id, result[:job_id]
          
          # Update batch with both dataset path and job ID
          @batch.update!(
            status: 'completed',
            fine_tune_dataset_path: dataset_path,
            fine_tune_job_id: result[:job_id]
          )
        else
          log_progress "❌ Failed to create fine-tune job: #{result[:error]}", level: :error
          # Still save the dataset path even if submission failed
          @batch.update!(
            status: 'completed',
            fine_tune_dataset_path: dataset_path
          )
        end
        
        # Track metrics
        track_metric :training_examples, @training_examples.size
        track_metric :dataset_path, dataset_path
        
      rescue => e
        log_progress "Fine-tune dataset building failed: #{e.message}", level: :error
        raise
      end
    end
    
    private
    
    def generate_canonical_term_examples
      # Generate examples for canonical term mapping
      LexiconAndOntology.canonical.limit(100).each do |term|
        next if term.surface_forms.blank?
        
        term.surface_forms.each do |surface|
          @training_examples << {
            task: 'canon_map',
            input: surface,
            output: {
              canonical: term.term,
              pool: term.pool_association
            }
          }
        end
      end
      
      log_progress "Generated #{@training_examples.size} canonical term examples", level: :debug
    end
    
    def generate_path_narration_examples
      # Simplified - would query Neo4j for actual paths
      @training_examples << {
        task: 'path_text',
        input: {
          nodes: ['idea:radical_inclusion', 'manifest:camp_x'],
          edges: ['embodies']
        },
        output: 'Idea(Radical Inclusion) embodies Manifest(Camp X).'
      }
      
      log_progress "Generated path narration examples", level: :debug
    end
    
    def generate_tool_routing_examples
      # Generate examples for tool routing
      @training_examples << {
        task: 'route',
        input: { intent: 'find similar concepts' },
        output: { tool: 'search', params: { diversify_by_pool: true } }
      }
      
      log_progress "Generated tool routing examples", level: :debug
    end
    
    def save_dataset
      # Save to tmp directory
      dataset_path = Rails.root.join('tmp', "fine_tune_#{@batch.id}.jsonl")
      
      File.open(dataset_path, 'w') do |file|
        @training_examples.each do |example|
          # Convert to OpenAI chat format
          formatted_example = format_for_openai(example)
          file.puts formatted_example.to_json
        end
      end
      
      dataset_path.to_s
    end
    
    def format_for_openai(example)
      # Convert our internal format to OpenAI's expected chat format
      case example[:task]
      when 'canon_map'
        {
          messages: [
            {
              role: 'system',
              content: 'You are an expert at mapping user phrases to canonical terms and their pools.'
            },
            {
              role: 'user',
              content: "Map this phrase to its canonical term: #{example[:input]}"
            },
            {
              role: 'assistant',
              content: "Canonical: #{example[:output][:canonical]}, Pool: #{example[:output][:pool]}"
            }
          ]
        }
      when 'path_text'
        {
          messages: [
            {
              role: 'system',
              content: 'You are an expert at narrating knowledge graph paths using the Relation Verb Glossary.'
            },
            {
              role: 'user',
              content: "Narrate this path: nodes=#{example[:input][:nodes].join(', ')}, edges=#{example[:input][:edges].join(', ')}"
            },
            {
              role: 'assistant',
              content: example[:output]
            }
          ]
        }
      when 'route'
        {
          messages: [
            {
              role: 'system',
              content: 'You are an expert at routing user intents to the appropriate MCP tools.'
            },
            {
              role: 'user',
              content: "What tool should I use for: #{example[:input][:intent]}"
            },
            {
              role: 'assistant',
              content: "Use tool: #{example[:output][:tool]} with params: #{example[:output][:params].to_json}"
            }
          ]
        }
      else
        # Default format
        {
          messages: [
            {
              role: 'user',
              content: example[:input].to_s
            },
            {
              role: 'assistant',
              content: example[:output].to_s
            }
          ]
        }
      end
    end
    
    def collect_stage_metrics
      {
        training_examples: @metrics[:training_examples] || 0
      }
    end
  end
end
