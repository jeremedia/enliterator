# frozen_string_literal: true

namespace :enliterator do
  namespace :graph do
    namespace :relations do
      desc "Backfill relations for a batch using existing entities (relation extraction only)"
      task :backfill, [:batch_id] => :environment do |t, args|
        batch_id = args[:batch_id] || ENV['BATCH_ID']
        
        unless batch_id
          puts "Usage: rails enliterator:graph:relations:backfill[batch_id]"
          puts "   or: BATCH_ID=123 rails enliterator:graph:relations:backfill"
          exit 1
        end
        
        batch = IngestBatch.find_by(id: batch_id)
        unless batch
          puts "ERROR: Batch ##{batch_id} not found"
          exit 1
        end
        
        puts "=" * 80
        puts "RELATION EXTRACTION BACKFILL - Batch ##{batch.id}: #{batch.name}"
        puts "=" * 80
        puts
        
        # Check current state
        entity_count = 0
        %w[Idea Manifest Experience Practical Relational Evolutionary Emanation].each do |pool|
          # Entities are linked to batch via ProvenanceAndRights custom_terms JSON
          count = pool.constantize.joins(:provenance_and_rights)
                      .where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", batch.id.to_s)
                      .count
          entity_count += count
          puts "  #{pool}: #{count} entities"
        end
        
        # Relational records might have batch reference directly or via ProvenanceAndRights
        existing_relations = Relational.joins(:provenance_and_rights)
                                      .where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", batch.id.to_s)
                                      .count
        puts "\nExisting Relational records: #{existing_relations}"
        puts
        
        if entity_count == 0
          puts "ERROR: No entities found for batch. Run entity extraction first."
          exit 1
        end
        
        puts "Starting relation extraction for #{batch.ingest_items.count} items..."
        puts
        
        # Track progress
        total_relations = 0
        errors = []
        
        batch.ingest_items.find_each.with_index do |item, index|
          print "\rProcessing item #{index + 1}/#{batch.ingest_items.count}..."
          
          begin
            # Build entity context from THIS ITEM ONLY
            entities = []
            
            # Collect entities that were extracted from this specific item
            %w[Idea Manifest Experience Practical Relational Evolutionary Emanation].each do |pool_name|
              pool_class = pool_name.constantize
              pool_type = pool_name.downcase
              
              # Find entities extracted from THIS ITEM specifically
              pool_class.joins(:provenance_and_rights)
                       .where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", batch.id.to_s)
                       .where("provenance_and_rights.custom_terms->>'extraction_item' = ?", item.id.to_s)
                       .find_each do |entity|
                # Get the appropriate label field for each pool type
                label = case pool_name
                        when 'Idea', 'Manifest', 'Practical', 'Relational', 'Evolutionary', 'Emanation'
                          entity.label if entity.respond_to?(:label)
                        when 'Experience'
                          entity.narrative_text || entity.agent_label if entity.respond_to?(:narrative_text)
                        when 'Practical'
                          entity.goal if entity.respond_to?(:goal)
                        else
                          entity.label if entity.respond_to?(:label)
                        end || entity.repr_text || "#{pool_name} #{entity.id}"
                
                entities << {
                  pool_type: pool_type,
                  label: label,
                  id: entity.id.to_s
                }
              end
            end
            
            # Skip if no entities from this item
            next if entities.empty?
            
            puts " (#{entities.size} entities)" if index < 5  # Debug first few
            
            # Extract relations using the refactored service
            result = Pools::RelationExtractionService.new(
              content: item.content,
              entities: entities
            ).extract
            
            if result[:success] && result[:relations].present?
              # Save each relation as a Relational record
              result[:relations].each do |rel|
                begin
                  # Resolve source entity
                  source_pool = rel[:source][:pool_type].capitalize
                  source_class = source_pool.constantize
                  source_entity = if rel[:source][:id]
                    source_class.find_by(id: rel[:source][:id])
                  else
                    # Try different label fields based on pool type
                    if source_pool == 'Experience'
                      source_class.find_by(narrative_text: rel[:source][:label]) ||
                      source_class.find_by(agent_label: rel[:source][:label]) ||
                      source_class.find_by(repr_text: rel[:source][:label])
                    else
                      source_class.find_by(label: rel[:source][:label]) ||
                      source_class.find_by(repr_text: rel[:source][:label])
                    end
                  end
                  
                  # Resolve target entity
                  target_pool = rel[:target][:pool_type].capitalize
                  target_class = target_pool.constantize
                  target_entity = if rel[:target][:id]
                    target_class.find_by(id: rel[:target][:id])
                  else
                    # Try different label fields based on pool type
                    if target_pool == 'Experience'
                      target_class.find_by(narrative_text: rel[:target][:label]) ||
                      target_class.find_by(agent_label: rel[:target][:label]) ||
                      target_class.find_by(repr_text: rel[:target][:label])
                    else
                      target_class.find_by(label: rel[:target][:label]) ||
                      target_class.find_by(repr_text: rel[:target][:label])
                    end
                  end
                  
                  if source_entity && target_entity
                    # Create ProvenanceAndRights for this relation
                    rights = ProvenanceAndRights.find_or_create_by!(
                      source_ids: ["relation_backfill_#{batch.id}_#{item.id}"],
                      collection_method: "openai_relation_extraction_backfill",
                      consent_status: "implicit_consent",
                      license_type: "custom",
                      valid_time_start: Time.current,
                      publishability: item.publishability || false,
                      training_eligibility: item.training_eligibility || false,
                      quarantined: false,
                      custom_terms: { 
                        'extraction_batch' => batch.id, 
                        'stage' => 'relation_backfill',
                        'item_id' => item.id
                      }
                    )
                    
                    # Get display labels for repr_text
                    source_label = source_pool == 'Experience' ? 
                      (source_entity.narrative_text || source_entity.agent_label || source_entity.repr_text) :
                      (source_entity.label || source_entity.repr_text)
                    
                    target_label = target_pool == 'Experience' ?
                      (target_entity.narrative_text || target_entity.agent_label || target_entity.repr_text) :
                      (target_entity.label || target_entity.repr_text)
                    
                    # Create Relational record
                    relational = Relational.create!(
                      label: "#{rel[:verb]} relationship",
                      relation_type: rel[:verb],
                      source_id: source_entity.id,
                      source_type: source_pool,
                      target_id: target_entity.id,
                      target_type: target_pool,
                      strength: rel[:confidence] || 0.7,
                      evidence_span: rel[:evidence_span],
                      valid_time_start: Time.current,
                      provenance_and_rights: rights,
                      repr_text: "#{source_label} #{rel[:verb]} #{target_label}"
                    )
                    
                    total_relations += 1
                  end
                rescue => e
                  errors << "Failed to save relation: #{e.message}"
                end
              end
            end
          rescue => e
            errors << "Item #{item.id}: #{e.message}"
          end
        end
        
        puts "\n\n" + "=" * 80
        puts "RELATION EXTRACTION COMPLETE"
        puts "=" * 80
        puts "  Total relations extracted: #{total_relations}"
        puts "  Total Relational records: #{Relational.joins(:provenance_and_rights).where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", batch.id.to_s).count}"
        puts "  Errors: #{errors.size}"
        puts
        
        if errors.any?
          puts "Errors encountered:"
          errors.first(10).each { |e| puts "  - #{e}" }
          puts "  ... and #{errors.size - 10} more" if errors.size > 10
        end
        
        # Now run EdgeLoader to create graph edges
        if total_relations > 0
          puts "\nRunning EdgeLoader to create graph edges..."
          
          ekn = batch.ekn
          if ekn
            result = Graph::Connection.instance.with_database(ekn.neo4j_database) do |driver|
              driver.session(database: ekn.neo4j_database) do |session|
                session.write_transaction do |tx|
                  loader = Graph::EdgeLoader.new(tx, batch)
                  loader.load_all
                end
              end
            end
            
            puts "EdgeLoader complete: #{result[:total_edges]} edges created"
            puts "By verb: #{result[:by_verb].inspect}"
          else
            puts "WARNING: No EKN associated with batch, skipping EdgeLoader"
          end
        end
        
        puts "\nDone! Use `rails enliterator:graph:audit[#{batch.ekn&.name || 'ekn_name'}]` to verify edges."
      end
      
      desc "Extract relations for a specific item (debugging)"
      task :test_item, [:item_id] => :environment do |t, args|
        item_id = args[:item_id]
        unless item_id
          puts "Usage: rails enliterator:graph:relations:test_item[item_id]"
          exit 1
        end
        
        item = IngestItem.find(item_id)
        batch = item.ingest_batch
        
        # Build entity context
        entities = []
        %w[Idea Manifest Experience Practical].each do |pool_name|
          pool_class = pool_name.constantize
          pool_type = pool_name.downcase
          
          pool_class.joins(:provenance_and_rights)
                   .where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", batch.id.to_s)
                   .limit(10).each do |entity|
            # Get the appropriate label field for each pool type
            label = case pool_name
                    when 'Experience'
                      entity.narrative_text || entity.agent_label || entity.repr_text
                    else
                      entity.label || entity.repr_text
                    end || "#{pool_name} #{entity.id}"
            
            entities << {
              pool_type: pool_type,
              label: label,
              id: entity.id.to_s
            }
          end
        end
        
        puts "Testing relation extraction for item ##{item.id}"
        puts "Content preview: #{item.content.truncate(200)}"
        puts "\nEntity context (#{entities.size} entities):"
        entities.each { |e| puts "  - #{e[:pool_type]}: #{e[:label]}" }
        puts
        
        result = Pools::RelationExtractionService.new(
          content: item.content,
          entities: entities
        ).extract
        
        if result[:success]
          puts "Relations found: #{result[:relations].size}"
          result[:relations].each do |rel|
            puts "\n#{rel[:source][:label]} (#{rel[:source][:pool_type]})"
            puts "  --[#{rel[:verb]}]--> "
            puts "#{rel[:target][:label]} (#{rel[:target][:pool_type]})"
            puts "  Confidence: #{rel[:confidence]}"
            puts "  Evidence: #{rel[:evidence_span].truncate(100) if rel[:evidence_span]}"
          end
        else
          puts "ERROR: #{result[:error]}"
        end
      end
    end
  end
end