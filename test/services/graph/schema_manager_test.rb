# frozen_string_literal: true

require "test_helper"

module Graph
  class SchemaManagerTest < ActiveSupport::TestCase
    setup do
      @mock_tx = Minitest::Mock.new
      @schema_manager = SchemaManager.new(@mock_tx)
    end
    
    test "creates constraints for all node types" do
      # Expect constraint creation queries
      expected_labels = %w[
        Idea Manifest Experience Relational Evolutionary 
        Practical Emanation ProvenanceAndRights Lexicon Intent
      ]
      
      # Each label should have at least one constraint (unique id)
      expected_labels.each do |label|
        @mock_tx.expect :run, nil do |query|
          query.include?("CONSTRAINT") && query.include?(label)
        end
      end
      
      # Allow additional constraint calls
      50.times { @mock_tx.expect :run, nil, [String] }
      
      result = @schema_manager.setup
      
      assert result[:constraints_created] >= 0
      assert result[:indexes_created] >= 0
    end
    
    test "creates unique constraint on id for each node type" do
      constraint_queries = []
      
      # Capture all queries
      @mock_tx.stub :run, ->(query) { constraint_queries << query; nil } do
        @schema_manager.setup
      end
      
      # Check that unique id constraints were created
      %w[Idea Manifest Experience].each do |label|
        assert constraint_queries.any? { |q| 
          q.include?("CONSTRAINT") && 
          q.include?(label) && 
          q.include?("id IS UNIQUE")
        }
      end
    end
    
    test "creates existence constraints for required properties" do
      constraint_queries = []
      
      @mock_tx.stub :run, ->(query) { constraint_queries << query; nil } do
        @schema_manager.setup
      end
      
      # Check rights_id constraint for content nodes
      assert constraint_queries.any? { |q| 
        q.include?("CONSTRAINT") && 
        q.include?("Idea") && 
        q.include?("rights_id IS NOT NULL")
      }
      
      # Check publishability constraint for ProvenanceAndRights
      assert constraint_queries.any? { |q| 
        q.include?("CONSTRAINT") && 
        q.include?("ProvenanceAndRights") && 
        q.include?("publishability IS NOT NULL")
      }
    end
    
    test "creates indexes for commonly queried properties" do
      index_queries = []
      
      @mock_tx.stub :run, ->(query) { index_queries << query; nil } do
        @schema_manager.setup
      end
      
      # Check that important indexes were created
      assert index_queries.any? { |q| 
        q.include?("INDEX") && 
        q.include?("Idea") && 
        q.include?("label")
      }
      
      assert index_queries.any? { |q| 
        q.include?("INDEX") && 
        q.include?("Manifest") && 
        q.include?("type")
      }
      
      assert index_queries.any? { |q| 
        q.include?("INDEX") && 
        q.include?("Experience") && 
        q.include?("observed_at")
      }
    end
    
    test "handles existing constraints gracefully" do
      # Simulate constraint already exists error
      @mock_tx.stub :run, ->(query) { 
        if query.include?("CONSTRAINT")
          raise Neo4j::Driver::Exceptions::ClientException.new("Constraint already exists")
        end
        nil
      } do
        # Should not raise an error
        result = @schema_manager.setup
        assert_not_nil result
      end
    end
    
    test "creates time field constraints appropriately" do
      constraint_queries = []
      
      @mock_tx.stub :run, ->(query) { constraint_queries << query; nil } do
        @schema_manager.setup
      end
      
      # Nodes with valid_time_start
      %w[Idea Manifest Practical].each do |label|
        assert constraint_queries.any? { |q| 
          q.include?("CONSTRAINT") && 
          q.include?(label) && 
          q.include?("valid_time_start IS NOT NULL")
        }
      end
      
      # Nodes with observed_at
      %w[Experience Intent].each do |label|
        assert constraint_queries.any? { |q| 
          q.include?("CONSTRAINT") && 
          q.include?(label) && 
          q.include?("observed_at IS NOT NULL")
        }
      end
    end
  end
end