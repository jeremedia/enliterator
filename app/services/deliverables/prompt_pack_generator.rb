# app/services/deliverables/prompt_pack_generator.rb
module Deliverables
  class PromptPackGenerator < ApplicationService
    attr_reader :batch_id, :output_dir

    def initialize(batch_id, output_dir: nil)
      @batch_id = batch_id
      @output_dir = output_dir || Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}", 'prompt_packs')
      FileUtils.mkdir_p(@output_dir)
    end

    def call
      validate_batch!
      
      {
        discovery: generate_discovery_prompts,
        exploration: generate_exploration_prompts,
        synthesis: generate_synthesis_prompts,
        temporal: generate_temporal_prompts,
        spatial: generate_spatial_prompts,
        examples: generate_examples,
        metadata: generate_metadata
      }
    end

    private

    def validate_batch!
      batch = IngestBatch.find(batch_id)
      raise "Batch not found" unless batch
      raise "Batch not ready for deliverables" unless batch.literacy_score.to_f >= 70
    end

    def generate_discovery_prompts
      filename = 'discovery_prompts.json'
      filepath = File.join(output_dir, filename)
      
      prompts = []
      
      # Get sample entities from different pools
      ideas = Idea.where(ingest_batch_id: batch_id).limit(5)
      manifests = Manifest.where(ingest_batch_id: batch_id).limit(5)
      experiences = Experience.where(ingest_batch_id: batch_id).limit(5)
      
      # Generate cross-pool discovery prompts
      ideas.each do |idea|
        manifests.each do |manifest|
          prompts << {
            id: "discovery_#{idea.id}_#{manifest.id}",
            template: "What connects the idea of {{idea_name}} to {{manifest_name}}?",
            placeholders: {
              idea_name: idea.canonical_name,
              manifest_name: manifest.title
            },
            grounding_entities: [
              { id: idea.id, pool: 'idea', name: idea.canonical_name },
              { id: manifest.id, pool: 'manifest', name: manifest.title }
            ],
            expected_response_structure: {
              connections: ["array of connection paths"],
              relationship_types: ["array of relationship verbs"],
              intermediate_entities: ["array of entities on the path"]
            },
            rights_requirements: determine_rights(idea, manifest),
            category: 'cross_pool_discovery'
          }
        end
      end
      
      # Generate same-pool discovery prompts
      experiences.combination(2).first(10).each do |exp1, exp2|
        prompts << {
          id: "discovery_exp_#{exp1.id}_#{exp2.id}",
          template: "How are these experiences related: '{{exp1_title}}' and '{{exp2_title}}'?",
          placeholders: {
            exp1_title: exp1.title,
            exp2_title: exp2.title
          },
          grounding_entities: [
            { id: exp1.id, pool: 'experience', name: exp1.title },
            { id: exp2.id, pool: 'experience', name: exp2.title }
          ],
          expected_response_structure: {
            shared_themes: ["array of common ideas"],
            temporal_relationship: "before/after/concurrent",
            causal_relationship: "influenced/independent/correlated"
          },
          rights_requirements: determine_rights(exp1, exp2),
          category: 'same_pool_discovery'
        }
      end
      
      File.write(filepath, JSON.pretty_generate(prompts))
      
      {
        filename: filename,
        path: filepath,
        prompt_count: prompts.count
      }
    end

    def generate_exploration_prompts
      filename = 'exploration_prompts.json'
      filepath = File.join(output_dir, filename)
      
      prompts = []
      
      # Generate entity exploration prompts for each pool
      %w[idea manifest experience relational evolutionary practical emanation].each do |pool|
        model_class = pool.capitalize.constantize
        entities = model_class.where(ingest_batch_id: batch_id).limit(10)
        
        entities.each do |entity|
          name = entity.respond_to?(:canonical_name) ? entity.canonical_name : entity.title
          
          prompts << {
            id: "explore_#{pool}_#{entity.id}",
            template: "Tell me everything about {{entity_name}} (#{pool})",
            placeholders: {
              entity_name: name
            },
            grounding_entities: [
              { id: entity.id, pool: pool, name: name }
            ],
            expected_response_structure: {
              description: "detailed description",
              attributes: "key properties and characteristics",
              relationships: {
                inbound: ["entities that connect to this"],
                outbound: ["entities this connects to"]
              },
              temporal_context: "when relevant",
              significance: "why this matters in the dataset"
            },
            rights_requirements: entity.publishability ? 'public' : 'internal',
            category: "#{pool}_exploration"
          }
        end
      end
      
      File.write(filepath, JSON.pretty_generate(prompts))
      
      {
        filename: filename,
        path: filepath,
        prompt_count: prompts.count
      }
    end

    def generate_synthesis_prompts
      filename = 'synthesis_prompts.json'
      filepath = File.join(output_dir, filename)
      
      prompts = []
      
      # Multi-entity synthesis prompts
      ideas = Idea.where(ingest_batch_id: batch_id).limit(3)
      
      if ideas.count >= 3
        idea_names = ideas.map(&:canonical_name)
        prompts << {
          id: "synthesis_ideas_#{ideas.map(&:id).join('_')}",
          template: "How do these ideas relate to each other: {{idea1}}, {{idea2}}, and {{idea3}}?",
          placeholders: {
            idea1: idea_names[0],
            idea2: idea_names[1],
            idea3: idea_names[2]
          },
          grounding_entities: ideas.map { |i| { id: i.id, pool: 'idea', name: i.canonical_name } },
          expected_response_structure: {
            synthesis: "unified understanding",
            commonalities: ["shared aspects"],
            tensions: ["conflicting aspects"],
            emergent_insights: ["new understanding from combination"]
          },
          rights_requirements: ideas.all?(&:publishability) ? 'public' : 'internal',
          category: 'multi_idea_synthesis'
        }
      end
      
      # Theme synthesis prompts
      result = neo4j_query(<<-CYPHER)
        MATCH (i:Idea)-[r]-(m:Manifest)
        WHERE i.ingest_batch_id = #{batch_id}
        WITH i, collect(DISTINCT m) as manifests
        WHERE size(manifests) >= 3
        RETURN i, manifests[0..4] as sample_manifests
        LIMIT 5
      CYPHER
      
      result.each do |row|
        idea = row['i']
        manifests = row['sample_manifests']
        
        prompts << {
          id: "synthesis_theme_#{idea['id']}",
          template: "Synthesize how the idea of {{idea_name}} manifests across different contexts",
          placeholders: {
            idea_name: idea['canonical_name']
          },
          grounding_entities: [
            { id: idea['id'], pool: 'idea', name: idea['canonical_name'] },
            *manifests.map { |m| { id: m['id'], pool: 'manifest', name: m['title'] } }
          ],
          expected_response_structure: {
            core_theme: "central understanding",
            variations: ["different expressions"],
            evolution: "how understanding changes",
            patterns: ["recurring elements"]
          },
          rights_requirements: 'public',
          category: 'theme_synthesis'
        }
      end
      
      File.write(filepath, JSON.pretty_generate(prompts))
      
      {
        filename: filename,
        path: filepath,
        prompt_count: prompts.count
      }
    end

    def generate_temporal_prompts
      filename = 'temporal_prompts.json'
      filepath = File.join(output_dir, filename)
      
      prompts = []
      
      # Get temporal range
      experiences = Experience.where(ingest_batch_id: batch_id).where.not(occurred_at: nil)
      if experiences.any?
        min_date = experiences.minimum(:occurred_at)
        max_date = experiences.maximum(:occurred_at)
        
        # Year-based prompts
        years = (min_date.year..max_date.year).to_a.sample(5)
        years.each do |year|
          prompts << {
            id: "temporal_year_#{year}",
            template: "What happened in {{year}}?",
            placeholders: {
              year: year
            },
            grounding_entities: [],
            expected_response_structure: {
              events: ["list of experiences"],
              themes: ["dominant ideas that year"],
              changes: ["what evolved from previous year"]
            },
            rights_requirements: 'public',
            category: 'year_summary'
          }
        end
        
        # Period prompts
        prompts << {
          id: "temporal_period_early",
          template: "Describe the early period ({{start_year}} - {{mid_year}})",
          placeholders: {
            start_year: min_date.year,
            mid_year: min_date.year + (max_date.year - min_date.year) / 2
          },
          grounding_entities: [],
          expected_response_structure: {
            defining_characteristics: "what makes this period unique",
            key_events: ["important experiences"],
            emerging_themes: ["ideas taking shape"]
          },
          rights_requirements: 'public',
          category: 'period_analysis'
        }
      end
      
      # Sequence prompts
      manifests = Manifest.where(ingest_batch_id: batch_id).where.not(year: nil).order(:year).limit(5)
      if manifests.count >= 2
        prompts << {
          id: "temporal_sequence_#{manifests.first.id}_#{manifests.last.id}",
          template: "Trace the evolution from {{start_manifest}} ({{start_year}}) to {{end_manifest}} ({{end_year}})",
          placeholders: {
            start_manifest: manifests.first.title,
            start_year: manifests.first.year,
            end_manifest: manifests.last.title,
            end_year: manifests.last.year
          },
          grounding_entities: manifests.map { |m| { id: m.id, pool: 'manifest', name: m.title } },
          expected_response_structure: {
            timeline: ["key milestones"],
            changes: ["what evolved"],
            continuities: ["what remained constant"],
            trajectory: "overall direction"
          },
          rights_requirements: 'public',
          category: 'evolution_trace'
        }
      end
      
      File.write(filepath, JSON.pretty_generate(prompts))
      
      {
        filename: filename,
        path: filepath,
        prompt_count: prompts.count
      }
    end

    def generate_spatial_prompts
      filename = 'spatial_prompts.json'
      filepath = File.join(output_dir, filename)
      
      prompts = []
      
      # Check if spatial data exists
      manifests_with_location = Manifest.where(ingest_batch_id: batch_id)
                                       .where.not(placement: nil)
                                       .limit(10)
      
      manifests_with_location.each do |manifest|
        prompts << {
          id: "spatial_neighbors_#{manifest.id}",
          template: "What camps were near {{camp_name}} at {{location}}?",
          placeholders: {
            camp_name: manifest.title,
            location: manifest.placement
          },
          grounding_entities: [
            { id: manifest.id, pool: 'manifest', name: manifest.title }
          ],
          expected_response_structure: {
            immediate_neighbors: ["directly adjacent camps"],
            nearby_camps: ["camps within walking distance"],
            sector_characteristics: "what defines this area"
          },
          rights_requirements: manifest.publishability ? 'public' : 'internal',
          category: 'spatial_neighbors'
        }
        
        prompts << {
          id: "spatial_movement_#{manifest.id}",
          template: "How did {{camp_name}}'s location change over time?",
          placeholders: {
            camp_name: manifest.title
          },
          grounding_entities: [
            { id: manifest.id, pool: 'manifest', name: manifest.title }
          ],
          expected_response_structure: {
            placement_history: ["year: location"],
            movement_pattern: "stable/mobile/evolving",
            placement_reasons: ["why these locations"]
          },
          rights_requirements: manifest.publishability ? 'public' : 'internal',
          category: 'spatial_evolution'
        }
      end
      
      # Regional prompts
      if manifests_with_location.any?
        prompts << {
          id: "spatial_region_analysis",
          template: "Describe the spatial organization of the dataset",
          placeholders: {},
          grounding_entities: [],
          expected_response_structure: {
            regions: ["distinct areas"],
            clustering_patterns: "how entities group spatially",
            movement_flows: "common paths between areas",
            spatial_themes: "ideas associated with locations"
          },
          rights_requirements: 'public',
          category: 'spatial_overview'
        }
      end
      
      File.write(filepath, JSON.pretty_generate(prompts))
      
      {
        filename: filename,
        path: filepath,
        prompt_count: prompts.count
      }
    end

    def generate_examples
      filename = 'examples.jsonl'
      filepath = File.join(output_dir, filename)
      
      examples = []
      
      # Generate example completions for key prompt types
      ideas = Idea.where(ingest_batch_id: batch_id).limit(3)
      
      ideas.each do |idea|
        # Exploration example
        example = {
          prompt: "Tell me everything about #{idea.canonical_name} (idea)",
          completion: generate_exploration_completion(idea),
          metadata: {
            type: 'exploration',
            pool: 'idea',
            entity_id: idea.id,
            temperature: 0
          }
        }
        examples << example
        
        # Discovery example
        manifest = idea.manifests.first
        if manifest
          example = {
            prompt: "What connects the idea of #{idea.canonical_name} to #{manifest.title}?",
            completion: generate_discovery_completion(idea, manifest),
            metadata: {
              type: 'discovery',
              pools: ['idea', 'manifest'],
              entity_ids: [idea.id, manifest.id],
              temperature: 0
            }
          }
          examples << example
        end
      end
      
      # Write as JSONL
      File.open(filepath, 'w') do |file|
        examples.each { |ex| file.puts(JSON.generate(ex)) }
      end
      
      {
        filename: filename,
        path: filepath,
        example_count: examples.count
      }
    end

    def generate_exploration_completion(entity)
      pool = entity.class.name.downcase
      name = entity.respond_to?(:canonical_name) ? entity.canonical_name : entity.title
      
      completion = "#{name} is a central #{pool} in this dataset. "
      
      if entity.respond_to?(:description) && entity.description.present?
        completion += "#{entity.description} "
      end
      
      # Add relationships
      relationships = []
      if entity.respond_to?(:manifests)
        count = entity.manifests.count
        relationships << "manifests in #{count} forms" if count > 0
      end
      
      if entity.respond_to?(:experiences)
        count = entity.experiences.count
        relationships << "connects to #{count} experiences" if count > 0
      end
      
      if relationships.any?
        completion += "It #{relationships.join(' and ')}. "
      end
      
      # Add temporal context if available
      if entity.respond_to?(:occurred_at) && entity.occurred_at
        completion += "This occurred on #{entity.occurred_at.strftime('%Y-%m-%d')}. "
      elsif entity.respond_to?(:year) && entity.year
        completion += "Associated with the year #{entity.year}. "
      end
      
      # Add significance
      completion += "This entity is significant because it represents key aspects of the dataset's knowledge structure."
      
      completion
    end

    def generate_discovery_completion(entity1, entity2)
      "#{entity1.canonical_name} connects to #{entity2.title} through a relationship of manifestation. " \
      "The idea embodies principles that are made concrete in the manifest form. " \
      "This connection illustrates how abstract concepts take physical or experiential shape. " \
      "The path between them may include intermediate entities that bridge the conceptual and the tangible."
    end

    def generate_metadata
      filename = 'prompt_pack_metadata.json'
      filepath = File.join(output_dir, filename)
      
      batch = IngestBatch.find(batch_id)
      
      metadata = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch: {
          id: batch.id,
          name: batch.name,
          literacy_score: batch.literacy_score
        },
        prompt_statistics: {
          discovery: count_prompts('discovery_prompts.json'),
          exploration: count_prompts('exploration_prompts.json'),
          synthesis: count_prompts('synthesis_prompts.json'),
          temporal: count_prompts('temporal_prompts.json'),
          spatial: count_prompts('spatial_prompts.json'),
          total_examples: count_examples('examples.jsonl')
        },
        configuration: {
          temperature: 0,
          model_recommendations: {
            extraction: OpenaiConfig::SettingsManager.model_for('extraction'),
            completion: OpenaiConfig::SettingsManager.model_for('answer')
          }
        }
      }
      
      File.write(filepath, JSON.pretty_generate(metadata))
      
      {
        filename: filename,
        path: filepath
      }
    end

    def determine_rights(*entities)
      entities.all?(&:publishability) ? 'public' : 'internal'
    end

    def count_prompts(filename)
      filepath = File.join(output_dir, filename)
      return 0 unless File.exist?(filepath)
      JSON.parse(File.read(filepath)).count
    rescue
      0
    end

    def count_examples(filename)
      filepath = File.join(output_dir, filename)
      return 0 unless File.exist?(filepath)
      File.readlines(filepath).count
    rescue
      0
    end

    def neo4j_query(cypher)
      Rails.configuration.neo4j_driver.session do |session|
        session.run(cypher).to_a
      end
    end
  end
end