namespace :enliterator do
  namespace :graph do
    desc "Create targeted known associations (Idea↔Manifest/Practical/Emanation, Manifest↔Experience, Practical↔Experience) in Neo4j for an EKN (usage: rails enliterator:graph:edges:targeted[ekn_slug])"
    task 'edges:targeted', [:ekn_slug] => :environment do |_, args|
      slug = args[:ekn_slug]
      unless slug
        puts "Usage: rails enliterator:graph:edges:targeted[ekn_slug]"
        exit 1
      end

      ekn = Ekn.friendly.find(slug) rescue nil
      ekn ||= Ekn.find_by(slug: slug) || Ekn.find_by(name: slug)
      unless ekn
        puts "❌ EKN not found for '#{slug}'"
        exit 1
      end

      db = ekn.neo4j_database_name
      puts "🎯 Targeted edge pass on DB: #{db} (EKN: #{ekn.name})"

      driver = Graph::Connection.instance.driver
      session = driver.session(database: db)
      begin
        before = session.run('MATCH ()-[r]->() RETURN count(r) as c').single[:c]

        created = Hash.new(0)

        session.write_transaction do |tx|
          # Idea -> Manifest (embodies)
          Idea.joins(:idea_manifests).includes(:manifests).find_each do |idea|
            idea.manifests.each do |manifest|
              tx.run('MATCH (a:Idea {id:$a}) MATCH (b:Manifest {id:$b}) MERGE (a)-[:EMBODIES]->(b)', a: idea.id, b: manifest.id)
              created['embodies'] += 1
            end
          end

          # Idea -> Practical (codifies)
          Idea.joins(:idea_practicals).includes(:practicals).find_each do |idea|
            idea.practicals.each do |practical|
              tx.run('MATCH (a:Idea {id:$a}) MATCH (b:Practical {id:$b}) MERGE (a)-[:CODIFIES]->(b)', a: idea.id, b: practical.id)
              created['codifies'] += 1
            end
          end

          # Idea -> Emanation (influences) — only if Emanation table exists
          if defined?(Emanation)
            Idea.joins(:idea_emanations).includes(:emanations).find_each do |idea|
              idea.emanations.each do |emanation|
                tx.run('MATCH (a:Idea {id:$a}) MATCH (b:Emanation {id:$b}) MERGE (a)-[:INFLUENCES]->(b)', a: idea.id, b: emanation.id)
                created['influences'] += 1
              end
            end
          end

          # Manifest -> Experience (elicits) — if join exists
          if defined?(ManifestExperience)
            Manifest.joins(:manifest_experiences).includes(:experiences).find_each do |manifest|
              manifest.experiences.each do |experience|
                tx.run('MATCH (a:Manifest {id:$a}) MATCH (b:Experience {id:$b}) MERGE (a)-[:ELICITS]->(b)', a: manifest.id, b: experience.id)
                created['elicits'] += 1
              end
            end
          end

          # Practical -> Experience (validated_by) — if join exists
          if defined?(ExperiencePractical)
            Practical.joins(:experience_practicals).includes(:experiences).find_each do |practical|
              practical.experiences.each do |experience|
                tx.run('MATCH (a:Practical {id:$a}) MATCH (b:Experience {id:$b}) MERGE (a)-[:VALIDATED_BY]->(b)', a: practical.id, b: experience.id)
                created['validated_by'] += 1
              end
            end
          end
        end

        after = session.run('MATCH ()-[r]->() RETURN count(r) as c').single[:c]
        puts "✅ Targeted pass done. Before=#{before} After=#{after} (Δ=#{after.to_i - before.to_i})"
        puts "   Created (MERGE attempts):"
        created.each { |k,v| puts "    - #{k}: #{v}" }
      rescue => e
        puts "❌ Targeted edge pass failed: #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        exit 1
      ensure
        session&.close
      end
    end
  end
end

