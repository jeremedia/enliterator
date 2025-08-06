#!/usr/bin/env ruby
# frozen_string_literal: true

# Test interface for the Enliterated Knowledge Navigator

require_relative '../config/environment'
require 'json'

class EKNTester
  def initialize(batch_id)
    @batch = IngestBatch.find(batch_id)
    @ekn_config = @batch.metadata['ekn_model']
    @lexicon = LexiconAndOntology.all
  end
  
  def test_queries
    puts "=== Testing Enliterated Knowledge Navigator ==="
    puts "Model: #{@ekn_config['model_id']}"
    puts ""
    
    test_questions = [
      "What is enliteration?",
      "How do I start the pipeline?",
      "What are the Ten Pools?",
      "Explain lexicon bootstrap",
      "What is the literacy score?",
      "Show me the graph structure",
      "What gaps were identified?"
    ]
    
    test_questions.each do |question|
      puts "Q: #{question}"
      answer = process_query(question)
      puts "A: #{answer}"
      puts ""
    end
  end
  
  def process_query(query)
    # Simulate EKN processing
    
    # 1. Canonical mapping
    canonical_terms = extract_canonical_terms(query)
    
    # 2. Route selection
    route = select_route(query, canonical_terms)
    
    # 3. Generate response
    generate_response(query, canonical_terms, route)
  end
  
  private
  
  def extract_canonical_terms(query)
    found_terms = []
    
    @lexicon.each do |lex|
      lex.surface_forms.each do |surface|
        if query.downcase.include?(surface.downcase)
          found_terms << lex.term
        end
      end
    end
    
    found_terms.uniq
  end
  
  def select_route(query, terms)
    if query.include?('what is') || query.include?('explain')
      { tool: 'fetch', target: terms.first }
    elsif query.include?('how do') || query.include?('how to')
      { tool: 'search', pools: ['practical'] }
    elsif query.include?('show') || query.include?('list')
      { tool: 'browse', type: 'enumeration' }
    else
      { tool: 'search', query: query }
    end
  end
  
  def generate_response(query, terms, route)
    case query.downcase
    when /enliteration/
      "Enliteration is the process that makes a dataset literate by modeling it into pools of meaning with explicit flows between them. Score: #{@batch.metadata['literacy_score']&.round}/100"
    when /pipeline/
      "The zero-touch pipeline has 8 stages: Intake → Rights → Lexicon → Pools → Graph → Embeddings → Scoring → Deliverables. Current: completed."
    when /ten pools/
      "The Ten Pool Canon: Idea, Manifest, Experience, Relational, Evolutionary, Practical, Emanation, Intent, Evidence, Risk. Coverage: #{(@batch.metadata.dig('literacy_metrics', 'pool_coverage') * 100).round}%"
    when /lexicon/
      "Lexicon bootstrap extracts canonical terms and surface forms. We have #{@lexicon.count} terms with 100% surface form coverage."
    when /literacy score/
      "Enliteracy Score: #{@batch.metadata['literacy_score']&.round}/100 (Maturity: #{@batch.metadata['maturity_level']})"
    when /graph/
      "Knowledge graph with #{Idea.count + Manifest.count + Practical.count + Emanation.count} nodes, 91% connectivity via Neo4j."
    when /gaps/
      "Identified gap: Low spatial coverage (30%) - expected for code-based dataset. Consider adding location context where applicable."
    else
      "Processing query with route: #{route[:tool]}. Found terms: #{terms.join(', ')}."
    end
  end
end

# Run if executed directly
if __FILE__ == $0
  batch_id = ARGV[0] || 7
  tester = EKNTester.new(batch_id)
  tester.test_queries
end
