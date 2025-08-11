# frozen_string_literal: true

module Reporting
  # Builds per-file import evidence using Neo4j as primary source,
  # correlated to SQL IngestItem and ProvenanceAndRights.
  class ImportStatsService
    def initialize(ekn, include_rights: false)
      @ekn = ekn
      @include_rights = include_rights
      @driver = Graph::Connection.instance.driver
      @database = @ekn.neo4j_database_name
    end

    # Lightweight summary for list rows
    def summary_for_item(item)
      return empty_summary unless item&.provenance_and_rights_id.present?

      pool_counts = pool_counts_for(item)
      rel_count = relationship_count_for(item)
      { pool_counts: pool_counts, relationship_count: rel_count }
    rescue => e
      Rails.logger.error "ImportStatsService.summary_for_item error: #{e.message}"
      empty_summary
    end

    # Full details for an item with independent pagination
    def details_for_item(item, entities_page: 1, rels_page: 1, per_page: 25)
      return { entities: [], relationships: [] } unless item&.provenance_and_rights_id.present?

      entities_offset = (entities_page - 1) * per_page
      rels_offset = (rels_page - 1) * per_page

      {
        entities: entities_for(item, limit: per_page, offset: entities_offset),
        relationships: relationships_for(item, limit: per_page, offset: rels_offset),
        entities_page: entities_page,
        rels_page: rels_page,
        per_page: per_page
      }
    rescue => e
      Rails.logger.error "ImportStatsService.details_for_item error: #{e.message}"
      { entities: [], relationships: [], entities_page: entities_page, rels_page: rels_page, per_page: per_page }
    end

    # API calls specifically related to an item, with intelligent fallback
    def api_calls_for_item(item, limit: 8)
      scope = @ekn.api_calls
      calls = scope.where(trackable_type: 'IngestItem', trackable_id: item.id)
                   .order(created_at: :desc)
                   .limit(limit)
      return calls if calls.any?

      # Fallback: timebox around the item's processing window
      window_start = (item.created_at - 2.hours) rescue 1.day.ago
      window_end = (item.updated_at + 2.hours) rescue Time.current
      scope.where(created_at: window_start..window_end)
           .order(created_at: :desc)
           .limit(limit)
    end

    private

    def empty_summary
      { pool_counts: {}, relationship_count: 0, entity_count: 0 }
    end

    # Fallback count: prefer item.pool_metadata['entities_count'] if present
    def entity_count_fallback(item)
      begin
        meta = item.pool_metadata || {}
        count = meta['entities_count'] || meta[:entities_count]
        count.to_i
      rescue
        0
      end
    end

    def pool_counts_for(item, enforce_source: true, enforce_batch: true)
      query = <<~CYPHER
        MATCH (pr:ProvenanceAndRights {id: $rights_id})
        WITH pr
        MATCH (n)
        WHERE ($include_rights OR labels(n)[0] <> 'ProvenanceAndRights')
          AND ($enforce_batch = false OR $batch_id IS NULL OR n.batch_id = $batch_id)
          AND (
            (exists(n.rights_id) AND n.rights_id = $rights_id)
            OR EXISTS( (n)-[:HAS_RIGHTS]->(pr) )
          )
          AND ($enforce_source = false OR pr.source_ids IS NULL OR size(pr.source_ids) = 0 OR $source_hash IN pr.source_ids)
        WITH labels(n)[0] AS pool, count(*) AS c
        RETURN pool, c
      CYPHER

      rows = execute(query, rights_id: item.provenance_and_rights_id,
                           source_hash: item.source_hash,
                           batch_id: item.ingest_batch_id,
                           include_rights: @include_rights,
                           enforce_source: enforce_source,
                           enforce_batch: enforce_batch)
      if rows.empty?
        if enforce_source
          return pool_counts_for(item, enforce_source: false, enforce_batch: enforce_batch)
        elsif enforce_batch
          return pool_counts_for(item, enforce_source: false, enforce_batch: false)
        end
      end
      if rows.empty? && item.pool_item_type.present? && item.pool_item_id.present?
        label = item.pool_item_type.to_s
        quick = execute("MATCH (n:#{label} {id: $pid}) RETURN labels(n)[0] as pool, count(n) as c", pid: item.pool_item_id)
        return quick.to_h { |r| [r['pool'] || 'Unknown', r['c'].to_i] }
      end
      rows.to_h { |r| [r['pool'] || 'Unknown', r['c'].to_i] }
    end

    def relationship_count_for(item, enforce_source: true, enforce_batch: true)
      query = <<~CYPHER
        CALL {
          MATCH (pr:ProvenanceAndRights {id: $rights_id})
          WITH pr
          MATCH (n)
          WHERE ($enforce_batch = false OR $batch_id IS NULL OR n.batch_id = $batch_id)
            AND (
              (exists(n.rights_id) AND n.rights_id = $rights_id)
              OR EXISTS( (n)-[:HAS_RIGHTS]->(pr) )
            )
            AND ($enforce_source = false OR pr.source_ids IS NULL OR size(pr.source_ids) = 0 OR $source_hash IN pr.source_ids)
          RETURN collect(id(n)) AS ids
        }
        MATCH (a)-[r]->(b)
        WHERE id(a) IN ids AND id(b) IN ids
          AND ($include_rights OR (labels(a)[0] <> 'ProvenanceAndRights' AND labels(b)[0] <> 'ProvenanceAndRights'))
        RETURN count(r) AS relationship_count
      CYPHER

      rows = execute(query, rights_id: item.provenance_and_rights_id,
                           source_hash: item.source_hash,
                           batch_id: item.ingest_batch_id,
                           include_rights: @include_rights,
                           enforce_source: enforce_source,
                           enforce_batch: enforce_batch)
      count = rows.first&.dig('relationship_count').to_i
      if count.zero?
        if enforce_source
          return relationship_count_for(item, enforce_source: false, enforce_batch: enforce_batch)
        elsif enforce_batch
          return relationship_count_for(item, enforce_source: false, enforce_batch: false)
        end
      end
      if count.zero? && item.pool_item_type.present? && item.pool_item_id.present?
        label = item.pool_item_type.to_s
        quick = execute("MATCH (n:#{label} {id: $pid})-[r]-() RETURN count(r) as c", pid: item.pool_item_id)
        return quick.first&.dig('c').to_i
      end
      count
    end

    def entities_for(item, limit:, offset:, enforce_source: true, enforce_batch: true)
      query = <<~CYPHER
        MATCH (pr:ProvenanceAndRights {id: $rights_id})
        WITH pr
        MATCH (n)
        WHERE ($include_rights OR labels(n)[0] <> 'ProvenanceAndRights')
          AND ($enforce_batch = false OR $batch_id IS NULL OR n.batch_id = $batch_id)
          AND (
            (exists(n.rights_id) AND n.rights_id = $rights_id)
            OR EXISTS( (n)-[:HAS_RIGHTS]->(pr) )
          )
          AND ($enforce_source = false OR pr.source_ids IS NULL OR size(pr.source_ids) = 0 OR $source_hash IN pr.source_ids)
        RETURN id(n) AS id,
               labels(n)[0] AS pool,
               coalesce(n.canonical_name, n.term, n.label, n.goal, n.narrative_text, 'Entity ' + toString(id(n))) AS name,
               coalesce(n.repr_text, n.canonical_description, n.definition, '')[..200] AS repr
        ORDER BY pool, name
        SKIP $offset LIMIT $limit
      CYPHER

      rows = execute(query, rights_id: item.provenance_and_rights_id,
                           source_hash: item.source_hash,
                           batch_id: item.ingest_batch_id,
                           include_rights: @include_rights,
                           enforce_source: enforce_source,
                           enforce_batch: enforce_batch,
                           limit: limit,
                           offset: offset)
      if rows.empty?
        if enforce_source
          return entities_for(item, limit: limit, offset: offset, enforce_source: false, enforce_batch: enforce_batch)
        elsif enforce_batch
          return entities_for(item, limit: limit, offset: offset, enforce_source: false, enforce_batch: false)
        end
      end
      if rows.empty? && item.pool_item_type.present? && item.pool_item_id.present?
        label = item.pool_item_type.to_s
        return execute("MATCH (n:#{label} {id: $pid}) RETURN id(n) as id, labels(n)[0] as pool, coalesce(n.canonical_name, n.term, n.label, n.goal, n.narrative_text, 'Entity ' + toString(id(n))) as name, coalesce(n.repr_text, n.canonical_description, n.definition, '')[..200] as repr", pid: item.pool_item_id)
      end
      rows
    end

    def relationships_for(item, limit:, offset:, enforce_source: true, enforce_batch: true)
      query = <<~CYPHER
        CALL {
          MATCH (pr:ProvenanceAndRights {id: $rights_id})
          WITH pr
          MATCH (n)
          WHERE ($enforce_batch = false OR $batch_id IS NULL OR n.batch_id = $batch_id)
            AND (
              (exists(n.rights_id) AND n.rights_id = $rights_id)
              OR EXISTS( (n)-[:HAS_RIGHTS]->(pr) )
            )
            AND ($enforce_source = false OR pr.source_ids IS NULL OR size(pr.source_ids) = 0 OR $source_hash IN pr.source_ids)
          RETURN collect(id(n)) AS ids
        }
        MATCH (a)-[r]->(b)
        WHERE id(a) IN ids AND id(b) IN ids
          AND ($include_rights OR (labels(a)[0] <> 'ProvenanceAndRights' AND labels(b)[0] <> 'ProvenanceAndRights'))
        RETURN id(a) AS source_id,
               coalesce(a.canonical_name, a.term, a.label, a.goal, a.narrative_text, toString(id(a))) AS source_name,
               labels(a)[0] AS source_pool,
               toLower(type(r)) AS verb,
               id(b) AS target_id,
               coalesce(b.canonical_name, b.term, b.label, b.goal, b.narrative_text, toString(id(b))) AS target_name,
               labels(b)[0] AS target_pool,
               source_pool + '(' + source_name + ') → ' + verb + ' → ' + target_pool + '(' + target_name + ')' AS path_text
        ORDER BY source_pool, verb, target_pool
        SKIP $offset LIMIT $limit
      CYPHER

      rows = execute(query, rights_id: item.provenance_and_rights_id,
                           source_hash: item.source_hash,
                           batch_id: item.ingest_batch_id,
                           include_rights: @include_rights,
                           enforce_source: enforce_source,
                           enforce_batch: enforce_batch,
                           limit: limit,
                           offset: offset)
      if rows.empty?
        if enforce_source
          return relationships_for(item, limit: limit, offset: offset, enforce_source: false, enforce_batch: enforce_batch)
        elsif enforce_batch
          return relationships_for(item, limit: limit, offset: offset, enforce_source: false, enforce_batch: false)
        end
      end
      if rows.empty? && item.pool_item_type.present? && item.pool_item_id.present?
        label = item.pool_item_type.to_s
        return execute(<<~CYPHER, pid: item.pool_item_id, limit: limit, offset: offset)
          MATCH (a:#{label} {id: $pid})-[r]->(b)
          RETURN id(a) as source_id,
                 coalesce(a.canonical_name, a.term, a.label, a.goal, a.narrative_text, toString(id(a))) AS source_name,
                 labels(a)[0] AS source_pool,
                 toLower(type(r)) AS verb,
                 id(b) AS target_id,
                 coalesce(b.canonical_name, b.term, b.label, b.goal, b.narrative_text, toString(id(b))) AS target_name,
                 labels(b)[0] AS target_pool,
                 source_pool + '(' + source_name + ') → ' + verb + ' → ' + target_pool + '(' + target_name + ')' AS path_text
          ORDER BY source_pool, verb, target_pool
          SKIP $offset LIMIT $limit
        CYPHER
      end
      rows
    end

    def execute(query, parameters = {})
      @driver.session(database: @database) do |session|
        result = session.run(query, parameters)
        result.map { |rec| rec.keys.zip(rec.values).to_h.stringify_keys }
      end
    rescue => e
      Rails.logger.error "Neo4j query failed (ImportStatsService): #{e.message}"
      Rails.logger.error "Database: #{@database}"
      Rails.logger.error "Query: #{query}"
      Rails.logger.error "Parameters: #{parameters}"
      []
    end
  end
end
