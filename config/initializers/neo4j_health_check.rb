# frozen_string_literal: true

# Verify Neo4j connection on Rails startup
# This ensures we fail fast if Neo4j is not accessible
Rails.application.config.after_initialize do
  begin
    # Skip in test environment to avoid CI/CD issues
    next if Rails.env.test?
    
    # Test the connection
    driver = Graph::Connection.instance.driver
    session = driver.session
    result = session.run("RETURN 1 as test")
    
    if result.single['test'] == 1
      config = Rails.application.config.neo4j
      Rails.logger.info "✅ Neo4j connection verified: #{config[:url]}"
      
      # Check for GenAI plugin
      genai_result = session.run(<<~CYPHER)
        SHOW PROCEDURES
        YIELD name 
        WHERE name STARTS WITH 'genai.' 
        RETURN count(name) as genai_count
      CYPHER
      
      genai_count = genai_result.single['genai_count']
      if genai_count > 0
        Rails.logger.info "✅ Neo4j GenAI plugin found: #{genai_count} procedures available"
      else
        Rails.logger.warn "⚠️  Neo4j GenAI plugin not found - embeddings will not work"
      end
    end
    
    session.close
  rescue => e
    config = Rails.application.config.neo4j
    error_msg = <<~ERROR
      
      ❌ Neo4j Connection Failed!
      ============================
      URL: #{config[:url]}
      Error: #{e.message}
      
      Please ensure:
      1. Neo4j is running
      2. The URL in .env is correct (NEO4J_URL=bolt://100.104.170.10:8687)
      3. Authentication is disabled (no username/password needed)
      
      To test the connection:
        rails runner "puts Graph::Connection.instance.neo4j_connected?"
      
      To check Neo4j status:
        nc -zv 100.104.170.10 8687
    ERROR
    
    Rails.logger.error error_msg
    
    # In development, show a more prominent warning but don't crash
    if Rails.env.development?
      puts "\n" + "=" * 60
      puts error_msg
      puts "=" * 60 + "\n"
    else
      # In production, fail fast
      raise
    end
  end
end