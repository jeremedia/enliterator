# frozen_string_literal: true

module Acceptance
  # Lightweight acceptance gate runner for pipeline verification
  # Returns a rubric of checks with pass/fail and details
  class GateRunner
    def initialize(batch_id)
      @batch = IngestBatch.find(batch_id)
      @ekn = @batch.ekn
      @rubric = []
    end

    def run_all
      add_check('items_present') { @batch.ingest_items.count.positive? }

      # Stage 1–2: id + time + rights pointer
      add_check('rights_pointer_present') do
        items = @batch.ingest_items.count
        with_rights = @batch.ingest_items.joins(:provenance_and_rights).distinct.count rescue 0
        @last_details = { items: items, with_rights: with_rights }
        items.zero? ? false : (with_rights.to_f / items >= 0.8)
      end

      # Stage 3: Lexicon extracted
      add_check('lexicon_extracted') do
        extracted = @batch.ingest_items.where(lexicon_status: 'extracted').count
        total = @batch.ingest_items.count
        @last_details = { extracted: extracted, total: total }
        total.zero? ? false : extracted == total
      end

      # Stage 4: Pools extracted
      add_check('pools_extracted') do
        extracted = @batch.ingest_items.where(pool_status: 'extracted').count
        total = @batch.ingest_items.count
        @last_details = { extracted: extracted, total: total }
        total.zero? ? false : extracted == total
      end

      # Stage 5: Graph assembled (basic stats)
      add_check('graph_assembled') do
        stats = graph_stats
        @last_details = stats
        (stats[:total_nodes].to_i > 0) && (stats[:total_relationships].to_i > 0)
      end

      # Stage 6: Embeddings present (Neo4j GenAI)
      add_check('embeddings_present') do
        svc = Neo4j::EmbeddingService.new(@batch.id)
        stats = svc.verify_embeddings
        @last_details = stats
        stats[:status].to_s == 'verified' && stats[:total_embeddings].to_i > 0
      end

      # Retrieval smoke (optional): semantic search returns something
      add_check('retrieval_smoke') do
        begin
          svc = Neo4j::EmbeddingService.new(@batch.id)
          results = svc.semantic_search('pipeline', limit: 3)
          @last_details = { results: results.first(3) }
          results.is_a?(Array) && results.any?
        rescue => e
          @last_details = { error: e.message }
          false
        end
      end

      # Stage 7: Literacy score threshold
      add_check('literacy_threshold') do
        score = @batch.literacy_score.to_f
        @last_details = { literacy_score: score }
        score >= 70.0
      end

      summarize
    end

    private

    def graph_stats
      svc = Graph::QueryService.new(@ekn.neo4j_database_name)
      svc.get_statistics rescue { total_nodes: 0, total_relationships: 0 }
    end

    def add_check(name)
      passed = yield
      @rubric << { name: name, passed: !!passed, details: @last_details }
      @last_details = nil
    end

    def summarize
      passed = @rubric.all? { |c| c[:passed] }
      { passed: passed, checks: @rubric, summary: summary_text(passed) }
    end

    def summary_text(passed)
      status = passed ? 'PASS' : 'FAIL'
      "Acceptance Gates: #{status} — #{Time.current.iso8601}"
    end
  end
end

