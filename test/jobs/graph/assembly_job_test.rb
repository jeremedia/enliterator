# frozen_string_literal: true

require "test_helper"

module Graph
  class AssemblyJobTest < ActiveJob::TestCase
    setup do
      @batch = IngestBatch.create!(
        name: "Test Batch",
        status: "pool_filling_completed",
        source_path: "/test/path"
      )
      
      # Create test data
      create_test_entities
    end
    
    test "performs graph assembly for a batch" do
      # Mock the Neo4j connection
      mock_connection = Minitest::Mock.new
      mock_transaction = Minitest::Mock.new
      
      # Expect transaction to be called
      mock_connection.expect :transaction, nil do |&block|
        block.call(mock_transaction)
      end
      
      # Mock the various service calls
      mock_transaction.expect :run, nil, [String]
      
      Graph::Connection.stub :instance, mock_connection do
        AssemblyJob.perform_now(@batch.id)
      end
      
      @batch.reload
      assert_equal "graph_assembly_completed", @batch.status
      assert_not_nil @batch.graph_assembly_stats
      assert_not_nil @batch.graph_assembled_at
    end
    
    test "handles graph assembly failure" do
      # Force an error
      Graph::Connection.stub :instance, ->{ raise "Connection failed" } do
        assert_raises(RuntimeError) do
          AssemblyJob.perform_now(@batch.id)
        end
      end
      
      @batch.reload
      assert_equal "graph_assembly_failed", @batch.status
      assert @batch.graph_assembly_stats["error"].present?
    end
    
    test "tracks statistics during assembly" do
      skip "Requires Neo4j test instance"
      
      AssemblyJob.perform_now(@batch.id)
      
      @batch.reload
      stats = @batch.graph_assembly_stats
      
      assert stats["nodes_created"] > 0
      assert stats["edges_created"] > 0
      assert_not_nil stats["constraints_created"]
      assert_not_nil stats["indexes_created"]
      assert_not_nil stats["duplicates_resolved"]
      assert_not_nil stats["orphans_removed"]
    end
    
    private
    
    def create_test_entities
      # Create ProvenanceAndRights
      rights = ProvenanceAndRights.create!(
        source_ids: ["test"],
        collectors: ["Test Collector"],
        method: "Test Method",
        license: "CC-BY",
        consent: "granted",
        publishability: true,
        training_eligibility: true,
        valid_time_start: Time.current
      )
      
      # Create test Idea
      idea = Idea.create!(
        label: "Test Principle",
        abstract: "A test principle",
        principle_tags: ["test"],
        authorship: "Test Author",
        inception_date: Date.today,
        valid_time_start: Time.current,
        repr_text: "Test Principle (test)",
        provenance_and_rights: rights
      )
      
      # Create test Manifest
      manifest = Manifest.create!(
        label: "Test Artifact",
        manifest_type: "installation",
        components: ["component1"],
        time_bounds_start: Time.current,
        valid_time_start: Time.current,
        repr_text: "Test Artifact installation",
        provenance_and_rights: rights
      )
      
      # Create test Experience
      experience = Experience.create!(
        agent_label: "Test Agent",
        context: "Test context",
        narrative_text: "This is a test experience",
        sentiment: "positive",
        observed_at: Time.current,
        repr_text: "Test experience by Test Agent",
        provenance_and_rights: rights
      )
      
      # Create relationships
      IdeaManifest.create!(idea: idea, manifest: manifest)
      ManifestExperience.create!(manifest: manifest, experience: experience)
      
      # Create test Lexicon
      LexiconAndOntology.create!(
        term: "test_term",
        definition: "A test term",
        canonical_description: "Test term for testing",
        surface_forms: ["test", "testing"],
        negative_surface_forms: ["not_test"],
        type_mapping: { "pool" => "idea", "entity_id" => idea.id },
        valid_time_start: Time.current
      )
    end
  end
end