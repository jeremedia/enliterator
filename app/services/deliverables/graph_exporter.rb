# app/services/deliverables/graph_exporter.rb
module Deliverables
  class GraphExporter < ApplicationService
    attr_reader :batch_id, :rights_filter, :output_dir

    def initialize(batch_id, rights_filter: 'public', output_dir: nil)
      @batch_id = batch_id
      @rights_filter = rights_filter
      @output_dir = output_dir || Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}", 'graph_exports')
      FileUtils.mkdir_p(@output_dir)
    end

    def call
      validate_batch!
      
      {
        cypher_dump: export_cypher_dump,
        query_templates: generate_query_templates,
        statistics: export_statistics,
        path_catalog: export_path_catalog,
        metadata: generate_metadata
      }
    end

    private

    def validate_batch!
      batch = IngestBatch.find(batch_id)
      raise "Batch not found" unless batch
      raise "Batch not ready for deliverables" unless batch.literacy_score.to_f >= 70
    end

    def export_cypher_dump
      filename = "graph_#{rights_filter}.cypher"
      filepath = File.join(output_dir, filename)
      
      queries = []
      
      # Export constraints and indexes
      queries << generate_schema_statements
      
      # Export nodes by pool
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |label|
        queries << export_nodes(label)
      end
      
      # Export relationships
      queries << export_relationships
      
      File.write(filepath, queries.flatten.compact.join("\n\n"))
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath),
        line_count: File.readlines(filepath).count
      }
    end

    def generate_schema_statements
      statements = []
      
      # Constraints
      statements << "// Schema Constraints"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Idea) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Manifest) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Experience) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Relational) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Evolutionary) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Practical) REQUIRE n.id IS UNIQUE;"
      statements << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:Emanation) REQUIRE n.id IS UNIQUE;"
      
      # Indexes
      statements << "\n// Indexes"
      statements << "CREATE INDEX IF NOT EXISTS FOR (n:Idea) ON (n.canonical_name);"
      statements << "CREATE INDEX IF NOT EXISTS FOR (n:Manifest) ON (n.title);"
      statements << "CREATE INDEX IF NOT EXISTS FOR (n:Experience) ON (n.occurred_at);"
      
      statements
    end

    def export_nodes(label)
      statements = []
      statements << "// #{label} Nodes"
      
      result = neo4j_query(<<-CYPHER)
        MATCH (n:#{label})
        #{rights_filter_clause('n')}
        RETURN n
        LIMIT 10000
      CYPHER
      
      result.each do |row|
        node = row['n']
        props = node.properties.map { |k, v| "#{k}: #{cypher_value(v)}" }.join(', ')
        statements << "CREATE (n:#{label} {#{props}});"
      end
      
      statements
    end

    def export_relationships
      statements = []
      statements << "// Relationships"
      
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        #{rights_filter_clause('a')}
        #{rights_filter_clause('b')}
        RETURN a, r, b, labels(a)[0] as label_a, labels(b)[0] as label_b
        LIMIT 50000
      CYPHER
      
      result.each do |row|
        from_id = row['a']['id']
        to_id = row['b']['id']
        rel_type = row['r'].type
        from_label = row['label_a']
        to_label = row['label_b']
        
        props = row['r'].properties
        props_str = props.empty? ? '' : " {#{props.map { |k, v| "#{k}: #{cypher_value(v)}" }.join(', ')}}"
        
        statements << "MATCH (a:#{from_label} {id: '#{from_id}'}), (b:#{to_label} {id: '#{to_id}'})"
        statements << "CREATE (a)-[:#{rel_type}#{props_str}]->(b);"
      end
      
      statements
    end

    def generate_query_templates
      filename = 'query_templates.cypher'
      filepath = File.join(output_dir, filename)
      
      templates = []
      
      # Discovery queries
      templates << <<-CYPHER
// Discovery: Find connections between two entities
// Parameters: $entity1_id, $entity2_id
MATCH path = shortestPath((a {id: $entity1_id})-[*..5]-(b {id: $entity2_id}))
RETURN path, length(path) as distance
ORDER BY distance
LIMIT 10;
      CYPHER
      
      # Exploration queries
      templates << <<-CYPHER
// Exploration: Get full context for an entity
// Parameters: $entity_id
MATCH (n {id: $entity_id})
OPTIONAL MATCH (n)-[r]-(connected)
RETURN n, collect(DISTINCT {
  relationship: type(r),
  direction: CASE WHEN startNode(r) = n THEN 'OUT' ELSE 'IN' END,
  connected: connected
}) as connections;
      CYPHER
      
      # Temporal queries
      templates << <<-CYPHER
// Temporal: Find events in time range
// Parameters: $start_date, $end_date
MATCH (e:Experience)
WHERE e.occurred_at >= $start_date AND e.occurred_at <= $end_date
RETURN e
ORDER BY e.occurred_at;
      CYPHER
      
      # Spatial queries (if Spatial pool exists)
      templates << <<-CYPHER
// Spatial: Find nearby camps
// Parameters: $camp_name, $year
MATCH (m:Manifest {title: $camp_name})
WHERE m.year = $year
OPTIONAL MATCH (m)-[:ADJACENT_TO]-(neighbor:Manifest)
WHERE neighbor.year = $year
RETURN m, collect(neighbor) as neighbors;
      CYPHER
      
      # Pool-specific queries
      templates << <<-CYPHER
// Pool Analysis: Count entities by pool
MATCH (n)
RETURN labels(n)[0] as pool, count(n) as count
ORDER BY count DESC;
      CYPHER
      
      # Path analysis
      templates << <<-CYPHER
// Path Analysis: Most connected nodes
MATCH (n)
WITH n, size((n)-[]-()) as degree
ORDER BY degree DESC
LIMIT 20
RETURN n, degree, labels(n)[0] as pool;
      CYPHER
      
      File.write(filepath, templates.join("\n\n"))
      
      {
        filename: filename,
        path: filepath,
        template_count: templates.count
      }
    end

    def export_statistics
      filename = 'statistics.json'
      filepath = File.join(output_dir, filename)
      
      stats = {
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        rights_filter: rights_filter,
        node_counts: {},
        relationship_counts: {},
        graph_metrics: {}
      }
      
      # Node counts by pool
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |label|
        result = neo4j_query("MATCH (n:#{label}) #{rights_filter_clause('n')} RETURN count(n) as count")
        stats[:node_counts][label.downcase] = result.first['count']
      end
      
      # Relationship counts by type
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        RETURN type(r) as type, count(r) as count
        ORDER BY count DESC
      CYPHER
      
      result.each do |row|
        stats[:relationship_counts][row['type'].downcase] = row['count']
      end
      
      # Graph metrics
      total_nodes = stats[:node_counts].values.sum
      total_relationships = stats[:relationship_counts].values.sum
      
      stats[:graph_metrics] = {
        total_nodes: total_nodes,
        total_relationships: total_relationships,
        density: total_relationships.to_f / (total_nodes * (total_nodes - 1)),
        avg_degree: (2.0 * total_relationships) / total_nodes
      }
      
      # Component analysis
      result = neo4j_query(<<-CYPHER)
        CALL gds.graph.exists('analytics_graph')
        YIELD exists
        RETURN exists
      CYPHER
      
      if result.first['exists']
        result = neo4j_query(<<-CYPHER)
          CALL gds.wcc.stats('analytics_graph')
          YIELD componentCount, componentDistribution
          RETURN componentCount, componentDistribution
        CYPHER
        
        if result.any?
          stats[:graph_metrics][:connected_components] = result.first['componentCount']
        end
      end
      
      File.write(filepath, JSON.pretty_generate(stats))
      
      {
        filename: filename,
        path: filepath,
        stats: stats
      }
    end

    def export_path_catalog
      filename = 'path_catalog.json'
      filepath = File.join(output_dir, filename)
      
      catalog = {
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        paths: []
      }
      
      # Sample important paths
      result = neo4j_query(<<-CYPHER)
        MATCH path = (idea:Idea)-[*1..3]-(experience:Experience)
        #{rights_filter_clause('idea')}
        #{rights_filter_clause('experience')}
        WITH path, length(path) as len
        ORDER BY len
        LIMIT 100
        RETURN path
      CYPHER
      
      result.each do |row|
        path = row['path']
        nodes = path.nodes.map { |n| { id: n['id'], label: n.labels.first, title: n['title'] || n['canonical_name'] } }
        relationships = path.relationships.map { |r| r.type }
        
        # Generate textized version using PathTextizer
        textizer = Graph::PathTextizer.new
        text = textizer.textize_path(nodes, relationships)
        
        catalog[:paths] << {
          nodes: nodes,
          relationships: relationships,
          textized: text,
          length: path.length
        }
      end
      
      File.write(filepath, JSON.pretty_generate(catalog))
      
      {
        filename: filename,
        path: filepath,
        path_count: catalog[:paths].count
      }
    end

    def generate_metadata
      filename = 'metadata.json'
      filepath = File.join(output_dir, filename)
      
      batch = IngestBatch.find(batch_id)
      
      metadata = {
        export_version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch: {
          id: batch.id,
          name: batch.name,
          literacy_score: batch.literacy_score,
          status: batch.status
        },
        rights_filter: rights_filter,
        files: Dir.glob(File.join(output_dir, '*')).map { |f| File.basename(f) },
        export_settings: {
          node_limit: 10000,
          relationship_limit: 50000,
          path_sample_size: 100
        }
      }
      
      File.write(filepath, JSON.pretty_generate(metadata))
      
      {
        filename: filename,
        path: filepath
      }
    end

    def rights_filter_clause(alias_name)
      case rights_filter
      when 'public'
        "WHERE #{alias_name}.publishability = true"
      when 'internal'
        "WHERE #{alias_name}.training_eligibility = true"
      when 'all'
        ""
      else
        "WHERE #{alias_name}.publishability = true"
      end
    end

    def cypher_value(value)
      case value
      when String
        "'#{value.gsub("'", "\\'")}'"
      when nil
        'null'
      when true, false
        value.to_s
      when Numeric
        value.to_s
      when Time, DateTime
        "datetime('#{value.iso8601}')"
      when Date
        "date('#{value.iso8601}')"
      else
        "'#{value}'"
      end
    end

    def neo4j_query(cypher)
      Rails.configuration.neo4j_driver.session do |session|
        session.run(cypher).to_a
      end
    end
  end
end