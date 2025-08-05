#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the graph assembly pipeline
# Usage: rails runner script/test_graph_assembly.rb

require 'logger'

logger = Logger.new(STDOUT)
logger.info "Starting Graph Assembly test..."

begin
  # Check if we have test data from previous stages
  batch = IngestBatch.where(status: 'pool_filling_completed').first
  
  unless batch
    logger.info "No batch with completed pool filling found. Creating test data..."
    
    # Create a test batch
    batch = IngestBatch.create!(
      name: "Graph Assembly Test Batch",
      status: "pool_filling_completed",
      source_path: "/test/graph_assembly"
    )
    
    # Create test rights
    rights = ProvenanceAndRights.create!(
      source_ids: ["test_source"],
      collectors: ["Test Collector"],
      method: "Test Collection",
      license: "CC-BY-4.0",
      consent: "granted",
      publishability: true,
      training_eligibility: true,
      valid_time_start: Time.current
    )
    
    # Create test Ideas
    idea1 = Idea.create!(
      label: "Radical Inclusion",
      abstract: "Everyone is welcome to participate",
      principle_tags: ["inclusion", "community"],
      authorship: "Community",
      inception_date: Date.new(1990, 1, 1),
      valid_time_start: Time.current,
      repr_text: "Radical Inclusion principle",
      provenance_and_rights: rights
    )
    
    idea2 = Idea.create!(
      label: "Gifting",
      abstract: "Giving without expectation of return",
      principle_tags: ["gift", "economy"],
      authorship: "Community",
      inception_date: Date.new(1990, 1, 1),
      valid_time_start: Time.current,
      repr_text: "Gifting principle",
      provenance_and_rights: rights
    )
    
    # Create test Manifests
    manifest1 = Manifest.create!(
      label: "Welcome Station",
      manifest_type: "installation",
      components: ["tent", "signage", "volunteers"],
      time_bounds_start: Time.current,
      valid_time_start: Time.current,
      repr_text: "Welcome Station installation",
      provenance_and_rights: rights
    )
    
    manifest2 = Manifest.create!(
      label: "Gift Circle",
      manifest_type: "event",
      components: ["participants", "gifts"],
      time_bounds_start: Time.current,
      valid_time_start: Time.current,
      repr_text: "Gift Circle event",
      provenance_and_rights: rights
    )
    
    # Create test Experiences
    experience1 = Experience.create!(
      agent_label: "First-time Participant",
      context: "Arrival at event",
      narrative_text: "I was warmly welcomed and felt immediately included",
      sentiment: "positive",
      observed_at: Time.current,
      repr_text: "Positive welcome experience",
      provenance_and_rights: rights
    )
    
    experience2 = Experience.create!(
      agent_label: "Veteran Participant",
      context: "Gift exchange",
      narrative_text: "The joy of giving without expectation transformed my perspective",
      sentiment: "transformative",
      observed_at: Time.current,
      repr_text: "Transformative gifting experience",
      provenance_and_rights: rights
    )
    
    # Create test Practical
    practical = Practical.create!(
      goal: "Welcome new participants",
      steps: ["Set up welcome station", "Train greeters", "Provide orientation"],
      prerequisites: ["Volunteers", "Materials"],
      hazards: ["Weather conditions"],
      validation_refs: ["Community feedback"],
      valid_time_start: Time.current,
      repr_text: "Welcome protocol",
      provenance_and_rights: rights
    )
    
    # Create test Emanation
    emanation = Emanation.create!(
      influence_type: "cultural_spread",
      target_context: "Regional events",
      pathway: "Participant networks",
      evidence: ["Event proliferation data"],
      valid_time_start: Time.current,
      repr_text: "Cultural influence spread",
      provenance_and_rights: rights
    )
    
    # Create relationships
    IdeaManifest.create!(idea: idea1, manifest: manifest1)
    IdeaManifest.create!(idea: idea2, manifest: manifest2)
    ManifestExperience.create!(manifest: manifest1, experience: experience1)
    ManifestExperience.create!(manifest: manifest2, experience: experience2)
    IdeaPractical.create!(idea: idea1, practical: practical)
    ExperienceEmanation.create!(experience: experience2, emanation: emanation)
    
    # Create test Lexicon entries
    LexiconAndOntology.create!(
      term: "inclusion",
      definition: "The practice of welcoming all",
      canonical_description: "Radical Inclusion - welcoming everyone",
      surface_forms: ["include", "inclusive", "including"],
      negative_surface_forms: ["exclude", "exclusive"],
      type_mapping: { "pool" => "idea", "entity_id" => idea1.id },
      valid_time_start: Time.current
    )
    
    LexiconAndOntology.create!(
      term: "gift",
      definition: "Something given without expectation",
      canonical_description: "Gift - unconditional offering",
      surface_forms: ["gifting", "gifted", "gifts"],
      negative_surface_forms: ["transaction", "trade"],
      type_mapping: { "pool" => "idea", "entity_id" => idea2.id },
      valid_time_start: Time.current
    )
    
    logger.info "Test data created successfully"
  end
  
  logger.info "Running Graph Assembly for batch #{batch.id}: #{batch.name}"
  
  # Check Neo4j connection
  begin
    Graph::Connection.instance.session do |session|
      result = session.run("RETURN 1 as test")
      logger.info "✓ Neo4j connection successful"
    end
  rescue => e
    logger.error "✗ Neo4j connection failed: #{e.message}"
    logger.error "Make sure Neo4j is running (docker-compose up neo4j)"
    exit 1
  end
  
  # Run the graph assembly job
  logger.info "Starting graph assembly..."
  Graph::AssemblyJob.perform_now(batch.id)
  
  # Reload and check results
  batch.reload
  
  if batch.status == 'graph_assembly_completed'
    logger.info "✓ Graph assembly completed successfully!"
    
    stats = batch.graph_assembly_stats
    logger.info "Statistics:"
    logger.info "  - Nodes created: #{stats['nodes_created']}"
    logger.info "  - Edges created: #{stats['edges_created']}"
    logger.info "  - Constraints created: #{stats['constraints_created']}"
    logger.info "  - Indexes created: #{stats['indexes_created']}"
    logger.info "  - Duplicates resolved: #{stats['duplicates_resolved']}"
    logger.info "  - Orphans removed: #{stats['orphans_removed']}"
    
    if stats['nodes_by_pool']
      logger.info "  - Nodes by pool:"
      stats['nodes_by_pool'].each do |pool, count|
        logger.info "    * #{pool}: #{count}"
      end
    end
    
    if stats['edges_by_verb']
      logger.info "  - Edges by verb:"
      stats['edges_by_verb'].each do |verb, count|
        logger.info "    * #{verb}: #{count}"
      end
    end
    
    # Test path textization
    logger.info "\nTesting path textization..."
    textizer = Graph::PathTextizer.new
    
    test_path = {
      nodes: [
        { id: idea1.id, label: "Idea", name: "Radical Inclusion" },
        { id: manifest1.id, label: "Manifest", name: "Welcome Station" },
        { id: experience1.id, label: "Experience", name: "First-timer welcome" }
      ],
      edges: ["embodies", "elicits"]
    }
    
    path_text = textizer.textize_path(test_path)
    logger.info "  Path: #{path_text}"
    
    narrative = textizer.narrate_path(test_path)
    logger.info "  Narrative: #{narrative}"
    
    logger.info "\n✓ All graph assembly tests passed!"
    
  else
    logger.error "✗ Graph assembly failed with status: #{batch.status}"
    if batch.graph_assembly_stats && batch.graph_assembly_stats['error']
      logger.error "Error: #{batch.graph_assembly_stats['error']}"
    end
    exit 1
  end
  
rescue => e
  logger.error "Error during graph assembly test: #{e.message}"
  logger.error e.backtrace.join("\n")
  exit 1
end