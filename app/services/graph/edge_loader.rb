# frozen_string_literal: true

module Graph
  # Loads edges/relationships into Neo4j using the Relation Verb Glossary
  class EdgeLoader
    # Copy of the verb glossary from Pools::ExtractionJob
    VERB_GLOSSARY = {
      'embodies' => { source: 'Idea', target: 'Manifest', reverse: 'is_embodiment_of' },
      'elicits' => { source: 'Manifest', target: 'Experience', reverse: 'is_elicited_by' },
      'influences' => { source: %w[Idea Emanation], target: '*', reverse: 'is_influenced_by' },
      'refines' => { source: 'Evolutionary', target: 'Idea', reverse: 'is_refined_by' },
      'version_of' => { source: 'Evolutionary', target: 'Manifest', reverse: 'has_version' },
      'co_occurs_with' => { source: 'Relational', target: 'Relational', symmetric: true },
      'located_at' => { source: 'Manifest', target: 'Spatial', reverse: 'hosts' },
      'adjacent_to' => { source: 'Spatial', target: 'Spatial', symmetric: true },
      'validated_by' => { source: 'Practical', target: 'Experience', reverse: 'validates' },
      'supports' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'refutes' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'diffuses_through' => { source: 'Emanation', target: 'Relational', reverse: nil },
      'codifies' => { source: 'Idea', target: 'Practical', reverse: 'derived_from' },
      'inspires' => { source: 'Experience', target: 'Emanation', reverse: 'is_inspired_by' },
      'feeds_back' => { source: 'Emanation', target: 'Idea', reverse: 'is_fed_by' },
      'connects_to' => { source: '*', target: '*', reverse: nil },
      'cites' => { source: '*', target: '*', reverse: 'cited_by' },
      'precedes' => { source: '*', target: '*', reverse: 'follows' },
      'authors' => { source: 'Actor', target: 'Manifest', reverse: 'authored_by' },
      'owns' => { source: 'Actor', target: 'Manifest', reverse: 'owned_by' },
      'member_of' => { source: 'Actor', target: 'Relational', reverse: 'has_member' },
      'reports' => { source: 'Actor', target: 'Experience', reverse: 'reported_by' },
      'in_sector_with' => { source: 'Spatial', target: 'Relational', reverse: nil },
      'measures' => { source: 'Evidence', target: 'Manifest', reverse: 'measured_by' },
      'requires_mitigation' => { source: 'Risk', target: 'Practical', reverse: 'mitigates' },
      'constrains' => { source: 'Governance', target: 'ProvenanceAndRights', reverse: 'constrained_by' },
      'produces' => { source: 'MethodPool', target: 'Evidence', reverse: 'produced_by' },
      'standardizes' => { source: 'MethodPool', target: 'Practical', reverse: 'standardized_by' },
      'implements' => { source: 'MethodPool', target: 'Practical', reverse: nil },
      'normalizes' => { source: 'Lexicon', target: '*', reverse: 'normalized_by' },
      'disambiguates' => { source: 'Lexicon', target: '*', reverse: 'disambiguated_by' },
      'requests' => { source: 'Intent', target: 'Relational', reverse: 'requested_by' },
      'selects_template' => { source: 'Intent', target: 'Practical', reverse: 'template_for' },
      'traverses_pattern' => { source: 'Intent', target: '*', reverse: nil },
      'targets' => { source: 'Intent', target: 'Manifest', reverse: 'targeted_by' },
      # System relationships
      'has_rights' => { source: '*', target: 'ProvenanceAndRights', reverse: nil }
    }.freeze
    
    def initialize(transaction, batch)
      @tx = transaction
      @batch = batch
      @edge_counts = Hash.new(0)
      @reverse_edge_count = 0
    end
    
    def load_all
      Rails.logger.info "Loading edges for batch #{@batch.id}"
      
      # Load relationships from ActiveRecord associations
      load_idea_relationships
      load_manifest_relationships
      load_experience_relationships
      load_relational_relationships
      load_evolutionary_relationships
      load_practical_relationships
      load_emanation_relationships
      load_lexicon_relationships
      load_intent_relationships
      
      # Load optional pool relationships if present
      load_actor_relationships if Actor.table_exists?
      load_spatial_relationships if Spatial.table_exists?
      load_evidence_relationships if Evidence.table_exists?
      load_risk_relationships if Risk.table_exists?
      load_method_relationships if MethodPool.table_exists?
      
      # Load rights relationships
      load_rights_relationships
      
      {
        total_edges: @edge_counts.values.sum,
        by_verb: @edge_counts,
        reverse_edges: @reverse_edge_count,
        rights_edges: @edge_counts['has_rights'] || 0
      }
    end
    
    private
    
    def load_idea_relationships
      # Idea -> Manifest (embodies)
      Idea.joins(:idea_manifests).find_each do |idea|
        idea.manifests.each do |manifest|
          create_relationship('Idea', idea.id, 'Manifest', manifest.id, 'embodies')
        end
      end
      
      # Idea -> Practical (codifies)
      Idea.joins(:idea_practicals).find_each do |idea|
        idea.practicals.each do |practical|
          create_relationship('Idea', idea.id, 'Practical', practical.id, 'codifies')
        end
      end
      
      # Idea -> Emanation (influences)
      Idea.joins(:idea_emanations).find_each do |idea|
        idea.emanations.each do |emanation|
          create_relationship('Idea', idea.id, 'Emanation', emanation.id, 'influences')
        end
      end
    end
    
    def load_manifest_relationships
      # Manifest -> Experience (elicits)
      Manifest.joins(:manifest_experiences).find_each do |manifest|
        manifest.experiences.each do |experience|
          create_relationship('Manifest', manifest.id, 'Experience', experience.id, 'elicits')
        end
      end
      
      # Manifest -> Spatial (located_at) if spatial_ref is present
      if Spatial.table_exists?
        Manifest.where.not(spatial_ref: nil).find_each do |manifest|
          if spatial = ::Spatial.find_by(id: manifest.spatial_ref)
            create_relationship('Manifest', manifest.id, 'Spatial', spatial.id, 'located_at')
          end
        end
      end
    end
    
    def load_experience_relationships
      # Experience -> Emanation (inspires)
      Experience.joins(:experience_emanations).find_each do |experience|
        experience.emanations.each do |emanation|
          create_relationship('Experience', experience.id, 'Emanation', emanation.id, 'inspires')
        end
      end
      
      # Link to Actor if agent_label maps to an actor
      if Actor.table_exists?
        Experience.where.not(agent_label: nil).find_each do |experience|
          if actor = Actor.find_by(name: experience.agent_label)
            create_relationship('Actor', actor.id, 'Experience', experience.id, 'reports')
          end
        end
      end
    end
    
    def load_relational_relationships
      Relational.find_each do |relational|
        # Create the relationship based on relation_type
        if relational.source_id && relational.target_id
          # For co_occurs_with between Relationals
          if relational.relation_type == 'co_occurs_with'
            create_relationship(
              relational.source_type,
              relational.source_id,
              relational.target_type,
              relational.target_id,
              'co_occurs_with'
            )
          else
            # Generic relationship
            create_relationship(
              relational.source_type,
              relational.source_id,
              relational.target_type,
              relational.target_id,
              relational.relation_type
            )
          end
        end
      end
    end
    
    def load_evolutionary_relationships
      # Evolutionary -> Idea (refines)
      Evolutionary.where.not(refined_idea_id: nil).find_each do |evolutionary|
        create_relationship('Evolutionary', evolutionary.id, 'Idea', evolutionary.refined_idea_id, 'refines')
      end
      
      # Evolutionary -> Manifest (version_of)
      Evolutionary.where.not(manifest_version_id: nil).find_each do |evolutionary|
        create_relationship('Evolutionary', evolutionary.id, 'Manifest', evolutionary.manifest_version_id, 'version_of')
      end
    end
    
    def load_practical_relationships
      # Practical -> Experience (validated_by)
      Practical.joins(:experience_practicals).find_each do |practical|
        practical.experiences.each do |experience|
          create_relationship('Practical', practical.id, 'Experience', experience.id, 'validated_by')
        end
      end
      
      # Practical -> Idea (reverse of codifies = derived_from)
      # This is handled by reverse edge creation
    end
    
    def load_emanation_relationships
      # Emanation -> Idea (feeds_back)
      Emanation.joins(:emanation_ideas).find_each do |emanation|
        emanation.ideas.each do |idea|
          create_relationship('Emanation', emanation.id, 'Idea', idea.id, 'feeds_back')
        end
      end
      
      # Emanation -> Relational (diffuses_through)
      Emanation.joins(:emanation_relationals).find_each do |emanation|
        emanation.relationals.each do |relational|
          create_relationship('Emanation', emanation.id, 'Relational', relational.id, 'diffuses_through')
        end
      end
    end
    
    def load_lexicon_relationships
      # Lexicon normalizes/disambiguates all entities
      LexiconAndOntology.find_each do |lexicon|
        # Create normalizes relationships to entities mentioned in surface_forms
        if lexicon.type_mapping.present?
          pool_type = lexicon.type_mapping['pool']
          entity_id = lexicon.type_mapping['entity_id']
          
          if pool_type && entity_id
            create_relationship('Lexicon', lexicon.id, pool_type.capitalize, entity_id, 'normalizes')
          end
        end
      end
    end
    
    def load_intent_relationships
      IntentAndTask.find_each do |intent|
        # Intent -> Manifest (targets) if there's a specific target
        if intent.respond_to?(:target_manifest_id) && intent.target_manifest_id
          create_relationship('Intent', intent.id, 'Manifest', intent.target_manifest_id, 'targets')
        end
        
        # Intent -> Practical (selects_template) if template is referenced
        if intent.adapter_name && practical = Practical.find_by(goal: intent.adapter_name)
          create_relationship('Intent', intent.id, 'Practical', practical.id, 'selects_template')
        end
      end
    end
    
    def load_actor_relationships
      # Handled in load_experience_relationships and specific Actor associations
    end
    
    def load_spatial_relationships
      # Spatial -> Spatial (adjacent_to)
      # This would require a spatial adjacency table or computation
      # For now, we'll skip automatic adjacency detection
    end
    
    def load_evidence_relationships
      Evidence.find_each do |evidence|
        # Evidence -> Idea (supports/refutes)
        # This would require parsing evidence.metadata for relationships
      end
    end
    
    def load_risk_relationships
      Risk.find_each do |risk|
        # Risk -> Practical (requires_mitigation)
        # This would require a risk_mitigations join table
      end
    end
    
    def load_method_relationships
      # MethodPool -> Practical (implements)
      MethodPool.joins(:method_pool_practicals).find_each do |method|
        method.practicals.each do |practical|
          create_relationship('MethodPool', method.id, 'Practical', practical.id, 'implements')
        end
      end
    end
    
    def load_rights_relationships
      # Every entity should have a relationship to its ProvenanceAndRights
      models_with_rights = [
        Idea, Manifest, Experience, Relational, Evolutionary,
        Practical, Emanation
      ]
      
      models_with_rights << Actor if Actor.table_exists?
      models_with_rights << Spatial if Spatial.table_exists?
      models_with_rights << Evidence if Evidence.table_exists?
      models_with_rights << Risk if Risk.table_exists?
      models_with_rights << MethodPool if MethodPool.table_exists?
      
      models_with_rights.each do |model|
        model.find_each do |entity|
          if entity.provenance_and_rights_id
            create_relationship(
              model.name,
              entity.id,
              'ProvenanceAndRights',
              entity.provenance_and_rights_id,
              'has_rights'
            )
          end
        end
      end
    end
    
    def create_relationship(source_label, source_id, target_label, target_id, verb)
      # Get verb configuration
      verb_config = VERB_GLOSSARY[verb]
      
      unless verb_config
        Rails.logger.warn "Unknown verb: #{verb}"
        return
      end
      
      # Create the primary relationship
      query = <<~CYPHER
        MATCH (source:#{source_label} {id: $source_id})
        MATCH (target:#{target_label} {id: $target_id})
        MERGE (source)-[r:#{verb.upcase}]->(target)
        SET r.created_at = timestamp()
      CYPHER
      
      @tx.run(query, source_id: source_id, target_id: target_id)
      @edge_counts[verb] += 1
      
      # Create reverse relationship if defined and not symmetric
      if verb_config[:reverse] && !verb_config[:symmetric]
        reverse_verb = verb_config[:reverse]
        reverse_query = <<~CYPHER
          MATCH (source:#{target_label} {id: $target_id})
          MATCH (target:#{source_label} {id: $source_id})
          MERGE (source)-[r:#{reverse_verb.upcase}]->(target)
          SET r.created_at = timestamp()
        CYPHER
        
        @tx.run(reverse_query, source_id: source_id, target_id: target_id)
        @reverse_edge_count += 1
      end
      
      # For symmetric relationships, create both directions with same verb
      if verb_config[:symmetric]
        reverse_query = <<~CYPHER
          MATCH (source:#{target_label} {id: $target_id})
          MATCH (target:#{source_label} {id: $source_id})
          MERGE (source)-[r:#{verb.upcase}]->(target)
          SET r.created_at = timestamp()
        CYPHER
        
        @tx.run(reverse_query, source_id: source_id, target_id: target_id)
        @reverse_edge_count += 1
      end
    rescue Neo4j::Driver::Exceptions::ClientException => e
      Rails.logger.error "Failed to create relationship #{verb} between #{source_label}:#{source_id} and #{target_label}:#{target_id}: #{e.message}"
    end
  end
end
