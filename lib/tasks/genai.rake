namespace :ops do
  namespace :genai do
    desc "Diagnose Neo4j GenAI setup and embeddings (usage: bin/rails ops:genai:diagnose[<EKN name>])"
    task :diagnose, [:ekn_name] => :environment do |_, args|
      begin
        driver = Graph::Connection.instance.driver

        # Show available GenAI procedures
        s = driver.session(database: 'neo4j')
        procs = s.run("SHOW PROCEDURES YIELD name WHERE name STARTS WITH 'genai.' RETURN collect(name) AS names").single&.[]( :names ) || []
        puts "GenAI procedures: #{procs}"

        # Show providers
        providers = []
        begin
          providers = s.run("CALL genai.vector.listEncodingProviders() YIELD name RETURN collect(name) AS providers").single&.[]( :providers ) || []
        rescue => e
          puts "listEncodingProviders error: #{e.message}"
        end
        puts "GenAI providers: #{providers}"

        # Canary encodeBatch with inline token
        api_key = ENV['OPENAI_API_KEY']
        if api_key.to_s.empty?
          puts "OPENAI_API_KEY not set in Rails environment"
        else
          begin
            canary = s.run("CALL genai.vector.encodeBatch(['diagnostic text'], 'OpenAI', { token: $token, model: 'text-embedding-3-small' }) YIELD index, vector RETURN size(vector) AS dims", token: api_key).single
            puts "Canary encodeBatch dims=#{canary && canary[:dims]}"
          rescue => e
            puts "Canary encodeBatch error: #{e.class}: #{e.message}"
          end
        end
        s.close

        # Target EKN database stats
        ekn = if args[:ekn_name].present?
                Ekn.find_by(name: args[:ekn_name])
              else
                Ekn.find_by(name: 'Meta-Enliterator') || Ekn.first
              end
        if ekn
          db = ekn.neo4j_database_name
          se = driver.session(database: db)
          stats = se.run("MATCH (n) WHERE n.embedding IS NOT NULL RETURN count(n) AS c, coalesce(avg(size(n.embedding)),0) AS dims").single
          puts "EKN '#{ekn.name}' DB=#{db} embedded_nodes=#{stats && stats[:c]} avg_dims=#{stats && stats[:dims]}"
          se.close
        else
          puts "No EKN found to inspect embeddings"
        end
      rescue => e
        puts "ERROR: #{e.class}: #{e.message}"
      end
    end
  end
end

