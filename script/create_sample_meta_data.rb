#!/usr/bin/env ruby

# Create sample data in Meta-Enliterator to enable visualizations
# This simulates what would happen if the pipeline had processed real files

puts "\n🚀 Creating Sample Data for Meta-Enliterator\n"
puts "=" * 60

ekn = Ekn.find('meta-enliterator')
puts "\n📊 Current Status:"
puts "  • Name: #{ekn.name}"
puts "  • Database: #{ekn.neo4j_database_name}"
puts "  • Current nodes: #{ekn.total_nodes}"

# Connect to Neo4j
connection = Graph::Connection.instance
session = connection.driver.session(database: ekn.neo4j_database_name)

begin
  puts "\n📦 Creating sample knowledge graph..."
  
  # Create Pipeline Stage nodes
  puts "\n1. Creating pipeline stage nodes..."
  stages = [
    { number: 0, name: "Frame the Mission", description: "Configuration and goal setting" },
    { number: 1, name: "Intake", description: "Bundle discovery, hashing, deduplication" },
    { number: 2, name: "Rights & Provenance", description: "License tracking, eligibility" },
    { number: 3, name: "Lexicon Bootstrap", description: "Canonical terms extraction" },
    { number: 4, name: "Pool Filling", description: "Ten Pool Canon extraction" },
    { number: 5, name: "Graph Assembly", description: "Neo4j knowledge graph building" },
    { number: 6, name: "Representations", description: "Embeddings and indexing" },
    { number: 7, name: "Literacy Scoring", description: "Maturity assessment" },
    { number: 8, name: "Deliverables", description: "Prompt packs generation" },
    { number: 9, name: "Knowledge Navigator", description: "The actual product" }
  ]
  
  stages.each do |stage|
    cypher = <<~CYPHER
      MERGE (s:Stage:Service {name: $name})
      SET s.stage = $number,
          s.description = $description,
          s.status = $status,
          s.created_at = datetime()
      RETURN s
    CYPHER
    
    session.run(cypher,
      name: stage[:name],
      number: stage[:number],
      description: stage[:description],
      status: stage[:number] < 9 ? 'completed' : 'in_progress'
    )
  end
  
  # Create stage connections
  puts "  • Connecting stages in sequence..."
  stages.each_cons(2) do |s1, s2|
    cypher = <<~CYPHER
      MATCH (a:Stage {name: $name1})
      MATCH (b:Stage {name: $name2})
      MERGE (a)-[r:TRIGGERS]->(b)
      SET r.sequence = true,
          r.created_at = datetime()
      RETURN r
    CYPHER
    
    session.run(cypher, name1: s1[:name], name2: s2[:name])
  end
  
  # Create Service nodes for extraction services
  puts "\n2. Creating extraction service nodes..."
  services = [
    { name: "Lexicon::ExtractorService", type: "extraction", uses: "OpenAI" },
    { name: "Pools::EntityExtractor", type: "extraction", uses: "OpenAI" },
    { name: "Graph::PathBuilder", type: "graph", uses: "Neo4j" },
    { name: "Embedding::VectorBuilder", type: "embedding", uses: "OpenAI" },
    { name: "FineTune::DatasetBuilder", type: "fine_tune", uses: "OpenAI" }
  ]
  
  services.each do |service|
    cypher = <<~CYPHER
      MERGE (s:Service {name: $name})
      SET s.type = $type,
          s.uses = $uses,
          s.created_at = datetime()
      RETURN s
    CYPHER
    
    session.run(cypher, service)
  end
  
  # Connect extraction services
  puts "  • Creating service dependencies..."
  cypher = <<~CYPHER
    MATCH (a:Service {name: 'Lexicon::ExtractorService'})
    MATCH (b:Service {name: 'Pools::EntityExtractor'})
    MERGE (b)-[r:DEPENDS_ON]->(a)
    SET r.reason = 'Needs canonical terms',
        r.created_at = datetime()
    RETURN r
  CYPHER
  session.run(cypher)
  
  # Create Ten Pool Canon nodes
  puts "\n3. Creating Ten Pool Canon nodes..."
  pools = [
    { name: "Idea", description: "Abstract concepts and principles", color: "#FF6B6B" },
    { name: "Manifest", description: "Physical representations", color: "#4ECDC4" },
    { name: "Experience", description: "Subjective encounters", color: "#45B7D1" },
    { name: "Relational", description: "Connections between entities", color: "#96CEB4" },
    { name: "Evolutionary", description: "Changes over time", color: "#FFEAA7" },
    { name: "Practical", description: "Methods and implementations", color: "#DDA0DD" },
    { name: "Emanation", description: "Consequences and effects", color: "#FFB6C1" },
    { name: "Spatial", description: "Location and geography", color: "#98D8C8" },
    { name: "Intent", description: "Goals and purposes", color: "#85C1E2" },
    { name: "Actor", description: "Agents and participants", color: "#FFA07A" }
  ]
  
  pools.each do |pool|
    cypher = <<~CYPHER
      MERGE (p:Pool {name: $name})
      SET p.description = $description,
          p.color = $color,
          p.canonical = lower($name),
          p.created_at = datetime()
      RETURN p
    CYPHER
    
    session.run(cypher, pool)
  end
  
  # Create pool relationships
  puts "  • Creating pool relationships..."
  pool_relations = [
    ["Idea", "Manifest", "EMBODIES"],
    ["Manifest", "Experience", "CREATES"],
    ["Experience", "Relational", "INVOLVES"],
    ["Relational", "Actor", "CONNECTS"],
    ["Evolutionary", "Experience", "TRANSFORMS"],
    ["Practical", "Manifest", "ENABLES"],
    ["Intent", "Idea", "GUIDES"],
    ["Emanation", "Experience", "CAUSES"]
  ]
  
  pool_relations.each do |source, target, rel_type|
    cypher = <<~CYPHER
      MATCH (a:Pool {name: $source})
      MATCH (b:Pool {name: $target})
      MERGE (a)-[r:#{rel_type}]->(b)
      SET r.strength = 0.8,
          r.created_at = datetime()
      RETURN r
    CYPHER
    
    session.run(cypher, source: source, target: target)
  end
  
  # Create MCP Tool nodes
  puts "\n4. Creating MCP tool nodes..."
  tools = [
    { name: "extract_and_link", description: "Extract & link entities by pool" },
    { name: "search", description: "Unified semantic + graph search" },
    { name: "fetch", description: "Retrieve full record + relations" },
    { name: "bridge", description: "Find items that connect concepts" },
    { name: "location_neighbors", description: "Spatial neighbors and patterns" }
  ]
  
  tools.each do |tool|
    cypher = <<~CYPHER
      MERGE (t:MCPTool {name: $name})
      SET t.description = $description,
          t.created_at = datetime()
      RETURN t
    CYPHER
    
    session.run(cypher, tool)
  end
  
  # Connect MCP tools to services
  puts "  • Connecting MCP tools to services..."
  cypher = <<~CYPHER
    MATCH (t:MCPTool)
    MATCH (s:Service) WHERE s.type = 'extraction'
    WITH t, s LIMIT 5
    MERGE (t)-[r:CALLS]->(s)
    SET r.created_at = datetime()
    RETURN r
  CYPHER
  session.run(cypher)
  
  # Create some Model nodes
  puts "\n5. Creating model nodes..."
  models = [
    { name: "Ekn", type: "ActiveRecord", description: "Top-level Knowledge Navigator" },
    { name: "IngestBatch", type: "ActiveRecord", description: "Batch of items to process" },
    { name: "IngestItem", type: "ActiveRecord", description: "Individual file or document" },
    { name: "Conversation", type: "ActiveRecord", description: "Chat conversation" }
  ]
  
  models.each do |model|
    cypher = <<~CYPHER
      MERGE (m:Model {name: $name})
      SET m.type = $type,
          m.description = $description,
          m.created_at = datetime()
      RETURN m
    CYPHER
    
    session.run(cypher, model)
  end
  
  # Connect models
  puts "  • Creating model relationships..."
  cypher = <<~CYPHER
    MATCH (e:Model {name: 'Ekn'})
    MATCH (b:Model {name: 'IngestBatch'})
    MERGE (e)-[r:HAS_MANY]->(b)
    SET r.created_at = datetime()
    RETURN r
  CYPHER
  session.run(cypher)
  
  puts "\n✅ Sample data created successfully!"
  
  # Count results
  result = session.run("MATCH (n) RETURN count(n) as count")
  node_count = result.single[:count]
  
  result = session.run("MATCH ()-[r]->() RETURN count(r) as count")
  rel_count = result.single[:count]
  
  puts "\n📊 Created:"
  puts "  • #{node_count} nodes"
  puts "  • #{rel_count} relationships"
  
rescue => e
  puts "\n✗ Error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  session&.close
end

# Verify final status
puts "\n📊 Final Meta-Enliterator Status:"
ekn.reload
puts "  • Total nodes: #{ekn.total_nodes}"
puts "  • Total relationships: #{ekn.total_relationships}"
puts "  • Knowledge density: #{ekn.knowledge_density}"

if ekn.total_nodes > 0
  puts "\n✅ SUCCESS! Meta-Enliterator now has knowledge to visualize!"
  puts "\n📝 Ready to test! The 4 concrete queries should now work:"
  puts "1. 'Show me how the pipeline stages connect'"
  puts "2. 'How are the extraction services related?'"
  puts "3. 'Visualize the Ten Pool Canon'"
  puts "4. 'What connects the MCP tools to the graph?'"
  puts "\n🚀 Start the server with: bin/dev"
  puts "   Then visit: http://localhost:3000/navigator"
else
  puts "\n⚠️  No nodes found - check Neo4j connection"
end