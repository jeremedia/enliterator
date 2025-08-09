namespace :enliterator do
  namespace :graph do
    desc "Audit graph stats for an EKN (usage: rails enliterator:graph:audit[ekn_slug_or_name])"
    task :audit, [:ekn_slug] => :environment do |_, args|
      slug = args[:ekn_slug]
      unless slug
        puts "Usage: rails enliterator:graph:audit[ekn_slug]"
        exit 1
      end

      ekn = Ekn.friendly.find(slug) rescue nil
      ekn ||= Ekn.find_by(slug: slug) || Ekn.find_by(name: slug)
      unless ekn
        puts "❌ EKN not found for '#{slug}'"
        exit 1
      end

      db = ekn.neo4j_database_name
      puts "🔍 Auditing Neo4j DB: #{db} (EKN: #{ekn.name})"

      driver = Graph::Connection.instance.driver
      session = driver.session(database: db)
      begin
        # Node labels breakdown
        puts "\nNode labels:"
        node_rows = session.run('MATCH (n) RETURN labels(n)[0] as label, count(n) as c ORDER BY c DESC')
        node_rows.each do |row|
          puts "  - #{row[:label]}: #{row[:c]}"
        end

        # Relationship types breakdown
        puts "\nRelationship types:"
        rel_rows = session.run('MATCH ()-[r]->() RETURN type(r) as type, count(r) as c ORDER BY c DESC')
        if rel_rows.peek
          rel_rows.each do |row|
            puts "  - #{row[:type]}: #{row[:c]}"
          end
        else
          puts "  (none)"
        end

        # Total counts
        nodes = session.run('MATCH (n) RETURN count(n) as c').single[:c]
        rels  = session.run('MATCH ()-[r]->() RETURN count(r) as c').single[:c]
        puts "\nTotals: nodes=#{nodes} relationships=#{rels}"
      rescue => e
        puts "❌ Audit failed: #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        exit 1
      ensure
        session&.close
      end
    end
  end
end

