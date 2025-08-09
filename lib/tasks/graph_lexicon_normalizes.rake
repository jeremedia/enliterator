namespace :enliterator do
  namespace :graph do
    desc "Create NORMALIZES edges from Lexicon.type_mapping (usage: rails enliterator:graph:lexicon_normalizes[ekn_slug])"
    task :lexicon_normalizes, [:ekn_slug] => :environment do |_, args|
      slug = args[:ekn_slug]
      unless slug
        puts "Usage: rails enliterator:graph:lexicon_normalizes[ekn_slug]"
        exit 1
      end

      ekn = Ekn.friendly.find(slug) rescue nil
      ekn ||= Ekn.find_by(slug: slug) || Ekn.find_by(name: slug)
      unless ekn
        puts "❌ EKN not found for '#{slug}'"
        exit 1
      end

      db = ekn.neo4j_database_name
      puts "🔎 Creating NORMALIZES edges in DB: #{db} (EKN: #{ekn.name})"

      driver = Graph::Connection.instance.driver
      session = driver.session(database: db)
      begin
        before = session.run('MATCH ()-[r:NORMALIZES]->() RETURN count(r) as c').single[:c]
        count = 0
        LexiconAndOntology.where.not(type_mapping: [nil, {}]).find_each do |lex|
          tm = lex.type_mapping || {}
          pool = tm['pool'] || tm[:pool]
          ent_id = tm['entity_id'] || tm[:entity_id]
          next unless pool && ent_id
          label = pool.to_s.classify
          session.write_transaction do |tx|
            tx.run("MATCH (l:Lexicon {id: $lid}) MATCH (t:#{label} {id: $tid}) MERGE (l)-[:NORMALIZES]->(t)", { 'lid' => lex.id, 'tid' => ent_id })
          end
          count += 1
        end
        after = session.run('MATCH ()-[r:NORMALIZES]->() RETURN count(r) as c').single[:c]
        puts "✅ NORMALIZES edges created/ensured for #{count} lexicon mappings"
        puts "   Before=#{before} After=#{after} (Δ=#{after.to_i - before.to_i})"
      rescue => e
        puts "❌ Lexicon normalization pass failed: #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        exit 1
      ensure
        session&.close
      end
    end
  end
end

