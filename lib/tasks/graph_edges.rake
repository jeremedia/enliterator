namespace :enliterator do
  namespace :graph do
    desc "Re-run EdgeLoader to (re)create relationships for an EKN (usage: rails enliterator:graph:edges[ekn_slug_or_name])"
    task :edges, [:ekn_slug] => :environment do |_, args|
      slug = args[:ekn_slug]
      unless slug
        puts "Usage: rails enliterator:graph:edges[ekn_slug]"
        exit 1
      end

      ekn = Ekn.friendly.find(slug) rescue nil
      ekn ||= Ekn.find_by(slug: slug) || Ekn.find_by(name: slug)
      unless ekn
        puts "❌ EKN not found for '#{slug}'"
        exit 1
      end

      db = ekn.neo4j_database_name
      puts "🔗 Rebuilding relationships in Neo4j DB: #{db} (EKN: #{ekn.name})"

      driver = Graph::Connection.instance.driver
      session = driver.session(database: db)
      begin
        # Use a lightweight batch-like object for logging
        batch_id = ekn.ingest_batches.last&.id || 0
        batch_stub = OpenStruct.new(id: batch_id)

        before = session.run('MATCH ()-[r]->() RETURN count(r) as c').single[:c]

        result = nil
        session.write_transaction do |tx|
          loader = Graph::EdgeLoader.new(tx, batch_stub)
          result = loader.load_all
        end

        after = session.run('MATCH ()-[r]->() RETURN count(r) as c').single[:c]

        puts "✅ Edge rebuild complete"
        puts "   Before: #{before}  After: #{after}  (+#{after.to_i - before.to_i})"
        if result
          puts "   Total created (this pass): #{result[:total_edges]}"
          puts "   Reverse edges: #{result[:reverse_edges]}"
          puts "   By verb:"
          result[:by_verb].each { |verb, cnt| puts "     - #{verb}: #{cnt}" }
        end
      rescue => e
        puts "❌ Failed to rebuild edges: #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        exit 1
      ensure
        session&.close
      end
    end
  end
end

