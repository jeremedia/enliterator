#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to check which OpenAI calls are tracked vs untracked
# Run with: rails runner script/check_api_tracking_coverage.rb

puts "\n" + "=" * 80
puts "API TRACKING COVERAGE ANALYSIS"
puts "=" * 80

puts "\n✅ CURRENTLY TRACKED (will appear in admin interface):"
puts "-" * 40
puts "1. Lexicon::TermExtractionService - Term extraction"
puts "2. Pools::EntityExtractionService - Entity extraction" 
puts "3. Pools::RelationExtractionService - Relation extraction"
puts "4. MCP::ExtractAndLinkService - MCP extract and link"
puts "5. ImageGenerationService - Image generation"
puts "   (All inherit from BaseExtractionService or have custom tracking)"

puts "\n❌ NOT TRACKED (won't appear in admin interface):"
puts "-" * 40
puts "1. Embedding::SearchService - Creating embeddings for search"
puts "2. Embedding::SynchronousFallbackJob - Fallback embedding creation"
puts "3. Embedding::BatchMonitorJob - Batch API monitoring"
puts "4. FineTune::Trainer - Fine-tuning job creation/management"
puts "5. Literate::Engine - Chat completions for Q&A"
puts "6. Webhooks::Handlers::ResponseHandler - Webhook response retrieval"
puts "7. Admin::OpenaiSettingsController - Model testing/verification"

puts "\n📊 IMPACT ON PIPELINE:"
puts "-" * 40
puts "When you run a pipeline (rake enliterator:process:bundle):"
puts ""
puts "Stage 3 (Lexicon Bootstrap): ✅ TRACKED"
puts "  - TermExtractionService calls are tracked"
puts ""
puts "Stage 4 (Pool Filling): ✅ TRACKED"
puts "  - EntityExtractionService calls are tracked"
puts "  - RelationExtractionService calls are tracked"
puts ""
puts "Stage 6 (Embeddings): ❌ NOT TRACKED"
puts "  - Embedding creation calls are NOT tracked"
puts "  - This could be significant cost/usage!"
puts ""
puts "Stage 9 (Runtime Q&A): ❌ NOT TRACKED"
puts "  - Chat completion calls are NOT tracked"

puts "\n💰 COST IMPLICATIONS:"
puts "-" * 40
puts "You're missing tracking for:"
puts "- Embeddings: ~$0.00002 per 1K tokens (ada-002)"
puts "- Chat completions: ~$0.01-0.03 per 1K tokens (GPT-4)"
puts "- Fine-tuning: Can be expensive!"
puts ""
puts "Estimated tracking coverage: ~60% of API calls"

puts "\n" + "=" * 80
puts "RECOMMENDATION: Add tracking to remaining services"
puts "for complete cost and usage visibility!"
puts "=" * 80