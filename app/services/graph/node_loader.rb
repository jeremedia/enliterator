# frozen_string_literal: true

module Graph
  # Loads nodes from all pools into Neo4j
  class NodeLoader
    def initialize(transaction, batch)
      @tx = transaction
      @batch = batch
      @node_counts = Hash.new(0)
    end
    
    def load_all
      Rails.logger.info "Loading nodes for batch #{@batch.id}"
      
      # Load nodes from each pool
      load_ideas
      load_manifests
      load_experiences
      load_relationals
      load_evolutionaries
      load_practicals
      load_emanations
      load_provenance_and_rights
      load_lexicon
      load_intents
      
      # Load optional pools if present
      load_actors if Actor.table_exists?
      load_spatials if Spatial.table_exists?
      load_evidence if Evidence.table_exists?
      load_risks if Risk.table_exists?
      load_methods if MethodPool.table_exists?
      
      {
        total_nodes: @node_counts.values.sum,
        by_pool: @node_counts
      }
    end
    
    private
    
    def load_ideas
      Idea.joins(:provenance_and_rights).find_each do |idea|
        properties = build_idea_properties(idea)
        create_node('Idea', properties)
        @node_counts[:ideas] += 1
      end
    end
    
    def load_manifests
      Manifest.joins(:provenance_and_rights).find_each do |manifest|
        properties = build_manifest_properties(manifest)
        create_node('Manifest', properties)
        @node_counts[:manifests] += 1
      end
    end
    
    def load_experiences
      Experience.joins(:provenance_and_rights).find_each do |experience|
        properties = build_experience_properties(experience)
        create_node('Experience', properties)
        @node_counts[:experiences] += 1
      end
    end
    
    def load_relationals
      Relational.joins(:provenance_and_rights).find_each do |relational|
        properties = build_relational_properties(relational)
        create_node('Relational', properties)
        @node_counts[:relationals] += 1
      end
    end
    
    def load_evolutionaries
      Evolutionary.joins(:provenance_and_rights).find_each do |evolutionary|
        properties = build_evolutionary_properties(evolutionary)
        create_node('Evolutionary', properties)
        @node_counts[:evolutionaries] += 1
      end
    end
    
    def load_practicals
      Practical.joins(:provenance_and_rights).find_each do |practical|
        properties = build_practical_properties(practical)
        create_node('Practical', properties)
        @node_counts[:practicals] += 1
      end
    end
    
    def load_emanations
      Emanation.joins(:provenance_and_rights).find_each do |emanation|
        properties = build_emanation_properties(emanation)
        create_node('Emanation', properties)
        @node_counts[:emanations] += 1
      end
    end
    
    def load_provenance_and_rights
      ProvenanceAndRights.find_each do |rights|
        properties = build_rights_properties(rights)
        create_node('ProvenanceAndRights', properties)
        @node_counts[:rights] += 1
      end
    end
    
    def load_lexicon
      LexiconAndOntology.find_each do |lexicon|
        properties = build_lexicon_properties(lexicon)
        create_node('Lexicon', properties)
        @node_counts[:lexicon] += 1
      end
    end
    
    def load_intents
      IntentAndTask.find_each do |intent|
        properties = build_intent_properties(intent)
        create_node('Intent', properties)
        @node_counts[:intents] += 1
      end
    end
    
    def load_actors
      Actor.joins(:provenance_and_rights).find_each do |actor|
        properties = build_actor_properties(actor)
        create_node('Actor', properties)
        @node_counts[:actors] += 1
      end
    end
    
    def load_spatials
      Spatial.joins(:provenance_and_rights).find_each do |spatial|
        properties = build_spatial_properties(spatial)
        create_node('Spatial', properties)
        @node_counts[:spatials] += 1
      end
    end
    
    def load_evidence
      Evidence.joins(:provenance_and_rights).find_each do |evidence|
        properties = build_evidence_properties(evidence)
        create_node('Evidence', properties)
        @node_counts[:evidence] += 1
      end
    end
    
    def load_risks
      Risk.joins(:provenance_and_rights).find_each do |risk|
        properties = build_risk_properties(risk)
        create_node('Risk', properties)
        @node_counts[:risks] += 1
      end
    end
    
    def load_methods
      MethodPool.joins(:provenance_and_rights).find_each do |method|
        properties = build_method_properties(method)
        create_node('MethodPool', properties)
        @node_counts[:methods] += 1
      end
    end
    
    # Property builders for each pool type
    
    def build_idea_properties(idea)
      {
        id: idea.id,
        label: idea.label,
        abstract: idea.abstract,
        # Ensure arrays contain only primitive types for Neo4j
        principle_tags: sanitize_for_neo4j(idea.principle_tags),
        authorship: idea.authorship,
        inception_date: idea.inception_date.to_s,
        valid_time_start: idea.valid_time_start.to_s,
        valid_time_end: idea.valid_time_end&.to_s,
        repr_text: idea.repr_text,
        rights_id: idea.provenance_and_rights_id,
        created_at: idea.created_at.to_s,
        updated_at: idea.updated_at.to_s
      }.compact
    end
    
    def build_manifest_properties(manifest)
      {
        id: manifest.id,
        label: manifest.label,
        type: manifest.manifest_type,
        # Ensure arrays/hashes are Neo4j-compatible
        components: sanitize_for_neo4j(manifest.components),
        time_bounds_start: manifest.time_bounds_start.to_s,
        time_bounds_end: manifest.time_bounds_end&.to_s,
        valid_time_start: manifest.valid_time_start.to_s,
        valid_time_end: manifest.valid_time_end&.to_s,
        repr_text: manifest.repr_text,
        rights_id: manifest.provenance_and_rights_id,
        spatial_ref: manifest.spatial_ref,
        created_at: manifest.created_at.to_s,
        updated_at: manifest.updated_at.to_s
      }.compact
    end
    
    def build_experience_properties(experience)
      {
        id: experience.id,
        agent_label: experience.agent_label,
        context: experience.context,
        narrative_text: experience.narrative_text,
        sentiment: experience.sentiment,
        observed_at: experience.observed_at.to_s,
        repr_text: experience.repr_text,
        rights_id: experience.provenance_and_rights_id,
        created_at: experience.created_at.to_s,
        updated_at: experience.updated_at.to_s
      }.compact
    end
    
    def build_relational_properties(relational)
      {
        id: relational.id,
        relation_type: relational.relation_type,
        source_id: relational.source_id,
        source_type: relational.source_type,
        target_id: relational.target_id,
        target_type: relational.target_type,
        strength: relational.strength,
        valid_time_start: relational.valid_time_start.to_s,
        valid_time_end: relational.valid_time_end&.to_s,
        rights_id: relational.provenance_and_rights_id,
        created_at: relational.created_at.to_s,
        updated_at: relational.updated_at.to_s
      }.compact
    end
    
    def build_evolutionary_properties(evolutionary)
      {
        id: evolutionary.id,
        change_note: evolutionary.change_note,
        # Split polymorphic reference into primitives
        prior_ref_id: evolutionary.prior_ref_id,
        prior_ref_type: evolutionary.prior_ref_type,
        version_id: evolutionary.version_id,
        valid_time_start: evolutionary.valid_time_start.to_s,
        valid_time_end: evolutionary.valid_time_end&.to_s,
        rights_id: evolutionary.provenance_and_rights_id,
        created_at: evolutionary.created_at.to_s,
        updated_at: evolutionary.updated_at.to_s
      }.compact
    end
    
    def build_practical_properties(practical)
      {
        id: practical.id,
        goal: practical.goal,
        # Sanitize potentially nested arrays
        steps: sanitize_for_neo4j(practical.steps),
        prerequisites: sanitize_for_neo4j(practical.prerequisites),
        hazards: sanitize_for_neo4j(practical.hazards),
        validation_refs: sanitize_for_neo4j(practical.validation_refs),
        valid_time_start: practical.valid_time_start.to_s,
        valid_time_end: practical.valid_time_end&.to_s,
        repr_text: practical.repr_text,
        rights_id: practical.provenance_and_rights_id,
        created_at: practical.created_at.to_s,
        updated_at: practical.updated_at.to_s
      }.compact
    end
    
    def build_emanation_properties(emanation)
      {
        id: emanation.id,
        influence_type: emanation.influence_type,
        target_context: emanation.target_context,
        pathway: emanation.pathway,
        evidence: emanation.evidence,
        valid_time_start: emanation.valid_time_start.to_s,
        valid_time_end: emanation.valid_time_end&.to_s,
        repr_text: emanation.repr_text,
        rights_id: emanation.provenance_and_rights_id,
        created_at: emanation.created_at.to_s,
        updated_at: emanation.updated_at.to_s
      }.compact
    end
    
    def build_rights_properties(rights)
      {
        id: rights.id,
        # Ensure JSONB arrays are Neo4j-compatible
        source_ids: sanitize_for_neo4j(rights.source_ids),
        collectors: sanitize_for_neo4j(rights.collectors),
        collection_method: rights.collection_method,
        license: rights.license_type,
        consent: rights.consent_status,
        embargo: rights.embargo_until,
        publishability: rights.publishability,
        training_eligibility: rights.training_eligibility,
        valid_time_start: rights.valid_time_start.to_s,
        valid_time_end: rights.valid_time_end&.to_s,
        created_at: rights.created_at.to_s,
        updated_at: rights.updated_at.to_s
        # NOTE: Excluding custom_terms as it's a hash/map
      }.compact
    end
    
    def build_lexicon_properties(lexicon)
      {
        id: lexicon.id,
        term: lexicon.term,
        definition: lexicon.definition,
        # Provide default for required Neo4j constraint (use .presence to handle empty strings)
        canonical_description: lexicon.canonical_description.presence || lexicon.definition.presence || "Extracted term",
        # Sanitize JSONB arrays and hashes
        surface_forms: sanitize_for_neo4j(lexicon.surface_forms),
        negative_surface_forms: sanitize_for_neo4j(lexicon.negative_surface_forms),
        type_mapping: sanitize_for_neo4j(lexicon.type_mapping),
        unit_system: lexicon.unit_system,
        schema_version: lexicon.schema_version,
        valid_time_start: lexicon.valid_time_start.to_s,
        valid_time_end: lexicon.valid_time_end&.to_s,
        created_at: lexicon.created_at.to_s,
        updated_at: lexicon.updated_at.to_s
      }.compact
    end
    
    def build_intent_properties(intent)
      {
        id: intent.id,
        user_goal: intent.user_goal,
        query_text: intent.query_text,
        presentation_preference: intent.presentation_preference,
        outcome_signal: intent.outcome_signal,
        success_criteria: intent.success_criteria,
        observed_at: intent.observed_at.to_s,
        repr_text: intent.repr_text,
        deliverable_type: intent.deliverable_type,
        modality: intent.modality,
        # Sanitize JSON fields
        constraints: sanitize_for_neo4j(intent.constraints),
        adapter_name: intent.adapter_name,
        adapter_params: sanitize_for_neo4j(intent.adapter_params),
        evaluation: sanitize_for_neo4j(intent.evaluation),
        created_at: intent.created_at.to_s,
        updated_at: intent.updated_at.to_s
      }.compact
    end
    
    def build_actor_properties(actor)
      {
        id: actor.id,
        name: actor.name,
        role: actor.role,
        # Sanitize JSON array
        permissions: sanitize_for_neo4j(actor.permissions),
        rights_id: actor.provenance_and_rights_id,
        created_at: actor.created_at.to_s,
        updated_at: actor.updated_at.to_s
      }.compact
    end
    
    def build_spatial_properties(spatial)
      {
        id: spatial.id,
        name: spatial.name,
        sector: spatial.sector,
        portal: spatial.portal,
        year: spatial.year,
        # Sanitize coordinates array/hash
        coordinates: sanitize_for_neo4j(spatial.coordinates),
        rights_id: spatial.provenance_and_rights_id,
        created_at: spatial.created_at.to_s,
        updated_at: spatial.updated_at.to_s
      }.compact
    end
    
    def build_evidence_properties(evidence)
      {
        id: evidence.id,
        observation: evidence.observation,
        # Sanitize measurement data
        measurement: sanitize_for_neo4j(evidence.measurement),
        timestamp: evidence.timestamp.to_s,
        rights_id: evidence.provenance_and_rights_id,
        created_at: evidence.created_at.to_s,
        updated_at: evidence.updated_at.to_s
      }.compact
    end
    
    def build_risk_properties(risk)
      {
        id: risk.id,
        hazard: risk.hazard,
        mitigation: risk.mitigation,
        approval_status: risk.approval_status,
        rights_id: risk.provenance_and_rights_id,
        created_at: risk.created_at.to_s,
        updated_at: risk.updated_at.to_s
      }.compact
    end
    
    def build_method_properties(method)
      {
        id: method.id,
        name: method.method_name,
        category: method.category,
        description: method.description,
        steps: method.steps,
        prerequisites: method.prerequisites,
        outcomes: method.outcomes,
        repr_text: method.repr_text,
        valid_time_start: method.valid_time_start.to_s,
        valid_time_end: method.valid_time_end&.to_s,
        rights_id: method.provenance_and_rights_id,
        created_at: method.created_at.to_s,
        updated_at: method.updated_at.to_s
      }.compact
    end
    
    def create_node(label, properties)
      # MERGE to handle potential duplicates
      # Tag nodes with the current batch for downstream embedding selection
      properties = properties.merge(batch_id: @batch.id)
      query = <<~CYPHER
        MERGE (n:#{label} {id: $id})
        SET n += $properties
      CYPHER
      
      @tx.run(query, id: properties[:id], properties: properties)
    end
    
    # Helper to ensure values are Neo4j-compatible
    def sanitize_for_neo4j(value)
      case value
      when Array
        # If array contains hashes/complex objects, convert to JSON string
        if value.any? { |v| v.is_a?(Hash) || v.is_a?(Array) }
          value.to_json
        else
          # Array of primitives is OK for Neo4j
          value
        end
      when Hash
        # Hashes must be converted to JSON strings
        value.to_json
      when nil
        nil
      else
        # Primitives are OK
        value
      end
    end
  end
end
