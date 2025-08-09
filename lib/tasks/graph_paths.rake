# frozen_string_literal: true

namespace :enliterator do
  namespace :graph do
    desc "Validate all relationships in an EKN's graph"
    task :validate_paths, [:ekn_id] => :environment do |_t, args|
      ekn_id = args[:ekn_id]&.to_i
      
      unless ekn_id
        puts "Usage: rails enliterator:graph:validate_paths[ekn_id]"
        exit 1
      end
      
      ekn = Ekn.find(ekn_id)
      puts "Validating paths for EKN: #{ekn.name}"
      puts "=" * 80
      
      validator = Graph::PathValidator.new(ekn: ekn)
      result = validator.validate_all_relationships
      
      if result[:valid]
        puts "✅ All relationships are valid!"
      else
        puts "❌ Validation errors found:"
        result[:errors].each do |error|
          puts "  ERROR: #{error}"
        end
      end
      
      if result[:warnings].any?
        puts "\n⚠️ Warnings:"
        result[:warnings].each do |warning|
          puts "  WARNING: #{warning}"
        end
      end
      
      puts "\n#{result[:summary]}"
    end
    
    desc "Textize sample paths from an EKN's graph"
    task :textize_paths, [:ekn_id, :limit] => :environment do |_t, args|
      ekn_id = args[:ekn_id]&.to_i
      limit = args[:limit]&.to_i || 5
      
      unless ekn_id
        puts "Usage: rails enliterator:graph:textize_paths[ekn_id,limit]"
        exit 1
      end
      
      ekn = Ekn.find(ekn_id)
      puts "Textizing paths for EKN: #{ekn.name}"
      puts "=" * 80
      
      textizer = Graph::PathTextizer.new(ekn: ekn)
      driver = Graph::Connection.instance.driver
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        # Find some connected nodes
        query = <<~CYPHER
          MATCH (n1)-[]->(n2)
          WHERE NOT n1:ProvenanceAndRights AND NOT n1:Lexicon
            AND NOT n2:ProvenanceAndRights AND NOT n2:Lexicon
          RETURN DISTINCT id(n1) as source_id, id(n2) as target_id,
                 labels(n1)[0] as source_pool, n1.label as source_label,
                 labels(n2)[0] as target_pool, n2.label as target_label
          LIMIT #{limit}
        CYPHER
        
        result = session.run(query)
        
        paths_found = 0
        result.each do |record|
          source_id = record['source_id']
          target_id = record['target_id']
          source_label = "#{record['source_pool']}(#{record['source_label']})"
          target_label = "#{record['target_pool']}(#{record['target_label']})"
          
          puts "\n#{paths_found + 1}. Path from #{source_label} to #{target_label}:"
          puts "-" * 60
          
          # Try to find and textize the path
          textized = textizer.textize_full_path(source_id, target_id, max_hops: 3)
          
          if textized
            puts "📝 #{textized}"
            paths_found += 1
          else
            puts "  No path found within 3 hops"
          end
        end
        
        puts "\n" + "=" * 80
        puts "Found and textized #{paths_found} paths"
      end
    end
    
    desc "Show neighborhood narrative around a node"
    task :textize_neighborhood, [:ekn_id, :node_label, :depth] => :environment do |_t, args|
      ekn_id = args[:ekn_id]&.to_i
      node_label = args[:node_label]
      depth = args[:depth]&.to_i || 2
      
      unless ekn_id && node_label
        puts "Usage: rails enliterator:graph:textize_neighborhood[ekn_id,node_label,depth]"
        exit 1
      end
      
      ekn = Ekn.find(ekn_id)
      puts "Finding neighborhood around '#{node_label}' in EKN: #{ekn.name}"
      puts "=" * 80
      
      driver = Graph::Connection.instance.driver
      textizer = Graph::PathTextizer.new(ekn: ekn)
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        # Find the node
        query = <<~CYPHER
          MATCH (n)
          WHERE n.label = $label OR n.name = $label
            AND NOT n:ProvenanceAndRights
            AND NOT n:Lexicon
          RETURN id(n) as node_id, labels(n)[0] as pool, n.label as label
          LIMIT 1
        CYPHER
        
        result = session.run(query, label: node_label)
        record = result.single
        
        unless record
          puts "Node with label '#{node_label}' not found"
          exit 1
        end
        
        node_id = record['node_id']
        pool = record['pool']
        label = record['label']
        
        puts "Found: #{pool}(#{label})"
        puts "\nNeighborhood narrative (depth #{depth}):"
        puts "-" * 60
        
        narrative = textizer.textize_neighborhood(node_id, depth: depth)
        puts narrative
      end
    end
    
    desc "Analyze path coverage and connectivity"
    task :analyze_connectivity, [:ekn_id] => :environment do |_t, args|
      ekn_id = args[:ekn_id]&.to_i
      
      unless ekn_id
        puts "Usage: rails enliterator:graph:analyze_connectivity[ekn_id]"
        exit 1
      end
      
      ekn = Ekn.find(ekn_id)
      puts "Analyzing connectivity for EKN: #{ekn.name}"
      puts "=" * 80
      
      driver = Graph::Connection.instance.driver
      
      driver.session(database: ekn.neo4j_database_name) do |session|
        # Overall statistics
        stats_query = <<~CYPHER
          MATCH (n)
          WHERE NOT n:ProvenanceAndRights AND NOT n:Lexicon
          WITH count(n) as total_nodes
          
          MATCH ()-[r]->()
          WHERE type(r) <> 'HAS_RIGHTS'
          WITH total_nodes, count(r) as total_relationships
          
          MATCH (isolated)
          WHERE NOT (isolated)-[]-()
            AND NOT isolated:ProvenanceAndRights
            AND NOT isolated:Lexicon
          WITH total_nodes, total_relationships, count(isolated) as isolated_nodes
          
          MATCH (connected)
          WHERE (connected)-[]-()
            AND NOT connected:ProvenanceAndRights
            AND NOT connected:Lexicon
          WITH total_nodes, total_relationships, isolated_nodes, count(connected) as connected_nodes
          
          RETURN total_nodes, total_relationships, isolated_nodes, connected_nodes,
                 toFloat(total_relationships) / toFloat(total_nodes) as avg_degree
        CYPHER
        
        result = session.run(stats_query)
        stats = result.single
        
        if stats
          puts "📊 Graph Statistics:"
          puts "  Total nodes: #{stats['total_nodes']}"
          puts "  Connected nodes: #{stats['connected_nodes']}"
          puts "  Isolated nodes: #{stats['isolated_nodes']}"
          puts "  Total relationships: #{stats['total_relationships']}"
          puts "  Average degree: #{'%.2f' % stats['avg_degree']}"
          puts "  Connectivity: #{'%.1f' % (stats['connected_nodes'].to_f / stats['total_nodes'] * 100)}%"
        end
        
        # Relationship type distribution
        puts "\n📈 Relationship Distribution:"
        verb_query = <<~CYPHER
          MATCH ()-[r]->()
          WHERE type(r) <> 'HAS_RIGHTS'
          RETURN type(r) as verb, count(r) as count
          ORDER BY count DESC
        CYPHER
        
        result = session.run(verb_query)
        result.each do |record|
          puts "  #{record['verb']}: #{record['count']}"
        end
        
        # Pool connectivity
        puts "\n🎯 Pool Connectivity:"
        pool_query = <<~CYPHER
          MATCH (n)
          WHERE NOT n:ProvenanceAndRights AND NOT n:Lexicon
          WITH labels(n)[0] as pool, n
          WITH pool, count(n) as node_count,
               sum(size((n)-[]->())) as out_degree,
               sum(size((n)<-[]->())) as in_degree
          RETURN pool, node_count,
                 toFloat(out_degree) / toFloat(node_count) as avg_out_degree,
                 toFloat(in_degree) / toFloat(node_count) as avg_in_degree
          ORDER BY node_count DESC
        CYPHER
        
        result = session.run(pool_query)
        result.each do |record|
          pool = record['pool']
          count = record['node_count']
          avg_out = record['avg_out_degree']
          avg_in = record['avg_in_degree']
          
          puts "  #{pool}: #{count} nodes (out: #{'%.1f' % avg_out}, in: #{'%.1f' % avg_in})"
        end
      end
    end
  end
end