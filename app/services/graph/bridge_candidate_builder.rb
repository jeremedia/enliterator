# frozen_string_literal: true

module Graph
  # Builds candidate inter-pool bridges with lightweight heuristics
  # Sources:
  # - Per-item entity sets (from ProvenanceAndRights.custom_terms extraction markers)
  # - Co-mention windows in item.content (sentence/paragraph)
  # - Lexicon normalization overlap (basic string match)
  # Returns candidates with evidence snippets to feed LLM validation
  class BridgeCandidateBuilder
    ALLOWED_PAIRS = {
      'Idea' => %w[Manifest Practical Experience],
      'Manifest' => %w[Experience],
      'Practical' => %w[Experience],
      'Experience' => %w[Emanation],
      'Evolutionary' => %w[Idea Manifest]
    }.freeze

    Candidate = Struct.new(:source, :target, :evidence, keyword_init: true)

    def initialize(batch:)
      @batch = batch
    end

    # Yields [item, [Candidate, ...]]
    def each_item_candidates(max_pairs_per_item: 50)
      @batch.ingest_items.find_each do |item|
        entities_by_pool = entities_for_item(item)
        next if entities_by_pool.values.flatten.empty?

        content = item.content.to_s
        sentences = split_sentences(content)
        candidates = []

        entities_by_pool.each do |source_pool, sources|
          next unless ALLOWED_PAIRS.key?(source_pool)
          ALLOWED_PAIRS[source_pool].each do |target_pool|
            next unless entities_by_pool.key?(target_pool)
            sources.each do |s|
              entities_by_pool[target_pool].each do |t|
                ev = evidence_for_pair(sentences, s, t)
                next if ev.empty?
                candidates << Candidate.new(source: s, target: t, evidence: ev)
                break if candidates.size >= max_pairs_per_item
              end
              break if candidates.size >= max_pairs_per_item
            end
          end
        end

        yield item, candidates if block_given? && candidates.any?
      end
    end

    private

    # Returns { 'Idea' => [{id:, label:, pool:}, ...], ... }
    def entities_for_item(item)
      pools = %w[Idea Manifest Experience Practical Evolutionary Emanation]
      by_pool = {}
      pools.each do |pool|
        rel = pool.constantize.joins(:provenance_and_rights)
                 .where("provenance_and_rights.custom_terms->>'extraction_batch' = ?", @batch.id.to_s)
                 .where("provenance_and_rights.custom_terms->>'extraction_item' = ?", item.id.to_s)
        by_pool[pool] = rel.limit(200).map { |e| { id: e.id, label: entity_label(pool, e), pool: pool } }
      end
      by_pool
    end

    def entity_label(pool, entity)
      case pool
      when 'Experience'
        entity.narrative_text || entity.agent_label || entity.repr_text || "Experience #{entity.id}"
      when 'Practical'
        entity.goal || entity.label || entity.repr_text || "Practical #{entity.id}"
      else
        entity.label || entity.repr_text || "#{pool} #{entity.id}"
      end
    end

    # Very simple sentence split
    def split_sentences(text)
      text.to_s.split(/(?<=[\.!?])\s+/).first(500)
    end

    # Find up to 3 sentences that co-mention s and t labels (case-insensitive)
    def evidence_for_pair(sentences, s, t)
      # Safely truncate labels before escaping to avoid breaking escape sequences
      sl = Regexp.escape(s[:label].to_s.strip[0, 40])  # Truncate raw string first
      tl = Regexp.escape(t[:label].to_s.strip[0, 40])  # Then escape the result
      return [] if sl.blank? || tl.blank?
      pattern = /(#{sl}).{0,160}(#{tl})|(#{tl}).{0,160}(#{sl})/i
      hits = []
      sentences.each do |sent|
        if sent&.match?(pattern)
          hits << sent.strip
          break if hits.size >= 3
        end
      end
      hits
    end
  end
end

