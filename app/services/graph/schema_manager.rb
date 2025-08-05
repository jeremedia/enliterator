# frozen_string_literal: true

module Graph
  # Manages Neo4j schema setup including constraints and indexes
  class SchemaManager
    def initialize(transaction)
      @tx = transaction
      @constraints_created = 0
      @indexes_created = 0
    end
    
    def setup
      create_constraints
      create_indexes
      
      {
        constraints_created: @constraints_created,
        indexes_created: @indexes_created
      }
    end
    
    private
    
    def create_constraints
      # Node labels from the Ten Pool Canon + optional pools
      node_labels = %w[
        Idea Manifest Experience Relational Evolutionary 
        Practical Emanation ProvenanceAndRights Lexicon Intent
        Actor Spatial Evidence Risk Method
      ]
      
      node_labels.each do |label|
        # Unique constraint on id for each node type
        create_unique_constraint(label, 'id')
        
        # Mandatory properties based on spec
        case label
        when 'Idea', 'Manifest', 'Experience', 'Practical', 'Emanation'
          create_existence_constraint(label, 'rights_id')
          create_existence_constraint(label, 'repr_text')
        when 'ProvenanceAndRights'
          create_existence_constraint(label, 'publishability')
          create_existence_constraint(label, 'training_eligibility')
        when 'Lexicon'
          create_existence_constraint(label, 'canonical_description')
        end
        
        # Time field constraints (valid_time or observed_at)
        if %w[Idea Manifest Practical Emanation Relational Evolutionary ProvenanceAndRights Lexicon].include?(label)
          # These use valid_time (start/end)
          create_existence_constraint(label, 'valid_time_start')
        elsif %w[Experience Intent].include?(label)
          # These use observed_at
          create_existence_constraint(label, 'observed_at')
        end
      end
      
      Rails.logger.info "Created #{@constraints_created} constraints"
    end
    
    def create_indexes
      # Create indexes for commonly queried properties
      index_configs = [
        # Text search indexes
        { label: 'Idea', property: 'label' },
        { label: 'Idea', property: 'abstract' },
        { label: 'Manifest', property: 'label' },
        { label: 'Manifest', property: 'type' },
        { label: 'Experience', property: 'agent_label' },
        { label: 'Experience', property: 'sentiment' },
        { label: 'Practical', property: 'goal' },
        { label: 'Emanation', property: 'influence_type' },
        { label: 'Lexicon', property: 'term' },
        { label: 'Intent', property: 'user_goal' },
        
        # Time-based indexes
        { label: 'Idea', property: 'inception_date' },
        { label: 'Manifest', property: 'valid_time_start' },
        { label: 'Experience', property: 'observed_at' },
        { label: 'Evolutionary', property: 'valid_time_start' },
        
        # Rights and provenance indexes
        { label: 'ProvenanceAndRights', property: 'publishability' },
        { label: 'ProvenanceAndRights', property: 'training_eligibility' },
        
        # Spatial indexes (when Spatial pool is used)
        { label: 'Spatial', property: 'sector' },
        { label: 'Spatial', property: 'portal' },
        { label: 'Spatial', property: 'year' }
      ]
      
      index_configs.each do |config|
        create_index(config[:label], config[:property])
      end
      
      Rails.logger.info "Created #{@indexes_created} indexes"
    end
    
    def create_unique_constraint(label, property)
      query = <<~CYPHER
        CREATE CONSTRAINT IF NOT EXISTS
        FOR (n:#{label})
        REQUIRE n.#{property} IS UNIQUE
      CYPHER
      
      begin
        @tx.run(query)
        @constraints_created += 1
      rescue Neo4j::Driver::Exceptions::ClientException => e
        # Constraint already exists
        Rails.logger.debug "Constraint already exists: #{label}.#{property}"
      end
    end
    
    def create_existence_constraint(label, property)
      query = <<~CYPHER
        CREATE CONSTRAINT IF NOT EXISTS
        FOR (n:#{label})
        REQUIRE n.#{property} IS NOT NULL
      CYPHER
      
      begin
        @tx.run(query)
        @constraints_created += 1
      rescue Neo4j::Driver::Exceptions::ClientException => e
        # Constraint already exists or not supported in this Neo4j version
        Rails.logger.debug "Could not create existence constraint: #{label}.#{property} - #{e.message}"
      end
    end
    
    def create_index(label, property)
      # Create index for performance
      query = <<~CYPHER
        CREATE INDEX IF NOT EXISTS
        FOR (n:#{label})
        ON (n.#{property})
      CYPHER
      
      begin
        @tx.run(query)
        @indexes_created += 1
      rescue Neo4j::Driver::Exceptions::ClientException => e
        Rails.logger.debug "Index already exists: #{label}.#{property}"
      end
    end
  end
end