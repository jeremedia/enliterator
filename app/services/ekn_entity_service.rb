class EknEntityService
  def initialize(ekn)
    @ekn = ekn
    @driver = Graph::Connection.instance.driver
    @database = "ekn-#{@ekn.slug}"
  end
  
  def get_entity_details(entity_id)
    query = <<~CYPHER
      MATCH (n)
      WHERE id(n) = $entity_id
      
      OPTIONAL MATCH (n)-[r]-(connected)
      WITH n, collect(DISTINCT {
        id: id(connected),
        name: coalesce(connected.term, connected.label, connected.goal, connected.narrative_text, connected.agent_label, 'Entity ' + toString(id(connected))),
        pool: labels(connected)[0],
        relationship: type(r),
        direction: CASE WHEN startNode(r) = n THEN 'outgoing' ELSE 'incoming' END
      })[..20] as connections
      
      RETURN {
        id: id(n),
        name: coalesce(n.term, n.label, n.goal, n.narrative_text, n.agent_label, 'Entity ' + toString(id(n))),
        pool: labels(n)[0],
        description: coalesce(n.canonical_description, n.definition, n.abstract, n.context, n.steps, 'No description available'),
        properties: {
          time_start: n.valid_time_start,
          time_end: n.time_end,
          spatial_context: n.spatial_context,
          created_at: n.created_at,
          repr_text: n.repr_text,
          observed_at: n.observed_at,
          sentiment: n.sentiment,
          authorship: n.authorship,
          license: n.license
        },
        connections: connections,
        stats: {
          total_connections: size([(n)--() | 1]),
          incoming_count: size([(n)<--() | 1]),
          outgoing_count: size([(n)-->() | 1])
        }
      } as entity
    CYPHER
    
    result = execute_cypher(query, { entity_id: entity_id.to_i }).first
    raise "Entity not found" unless result
    
    result['entity']
  end
  
  private
  
  def execute_cypher(query, parameters = {})
    @driver.session(database: @database) do |session|
      result = session.run(query, parameters)
      # Convert Neo4j::Driver records to hashes for easier access
      result.map do |record|
        record.keys.zip(record.values).to_h.stringify_keys
      end
    end
  rescue => e
    Rails.logger.error "Neo4j entity query failed: #{e.message}"
    Rails.logger.error "Query: #{query}"
    Rails.logger.error "Parameters: #{parameters}"
    []
  end
end