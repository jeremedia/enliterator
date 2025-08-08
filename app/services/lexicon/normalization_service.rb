# frozen_string_literal: true

module Lexicon
  # Service to normalize and deduplicate extracted terms
  # Handles casing normalization, deduplication, and conflict resolution
  class NormalizationService < ApplicationService

    attr_reader :extracted_terms

    def initialize(extracted_terms)
      @extracted_terms = extracted_terms
    end

    def normalize_and_deduplicate
      # Group terms by normalized canonical form
      grouped_terms = group_by_normalized_canonical

      # Merge and deduplicate each group
      normalized_terms = grouped_terms.map do |normalized_key, term_group|
        merge_term_group(normalized_key, term_group)
      end

      # Sort by canonical term for consistency
      normalized_terms.sort_by { |term| term[:canonical_term] }
    end

    private

    def group_by_normalized_canonical
      extracted_terms.group_by do |term|
        normalize_key(term[:canonical_term])
      end
    end

    def normalize_key(term)
      # Normalize for comparison: lowercase, remove punctuation, collapse whitespace
      term.to_s
          .downcase
          .gsub(/[^\w\s-]/, '')
          .gsub(/\s+/, ' ')
          .strip
    end

    def merge_term_group(normalized_key, term_group)
      # Select the best canonical form (prefer proper casing)
      canonical_term = select_best_canonical_form(term_group)

      # Merge all surface forms
      all_surface_forms = term_group.flat_map { |t| t[:surface_forms] || [] }
      unique_surface_forms = deduplicate_surface_forms(all_surface_forms, canonical_term)

      # Merge all negative surface forms
      all_negative_forms = term_group.flat_map { |t| t[:negative_surface_forms] || [] }
      unique_negative_forms = all_negative_forms.uniq { |form| normalize_key(form) }

      # Select the best description (longest, most detailed)
      canonical_description = select_best_description(term_group)

      # Determine term type (most common or most specific)
      term_type = determine_term_type(term_group)

      # Merge metadata
      metadata = merge_metadata(term_group)
      
      # Choose provenance_and_rights_id deterministically
      # Select the most frequent rights_id among the term_group
      rights_ids = term_group.map { |t| t[:provenance_and_rights_id] }.compact
      chosen_rights_id = if rights_ids.any?
        # Group by ID and count occurrences, then pick the most frequent
        rights_ids.group_by(&:itself)
                  .max_by { |_id, occurrences| occurrences.size }
                  &.first
      end
      
      # Collect all contributing source item IDs
      source_item_ids = term_group.map { |t| t[:source_item_id] }.compact.uniq

      {
        canonical_term: canonical_term,
        surface_forms: unique_surface_forms,
        negative_surface_forms: unique_negative_forms,
        canonical_description: canonical_description,
        term_type: term_type,
        metadata: metadata,
        provenance_and_rights_id: chosen_rights_id,
        source_item_ids: source_item_ids
      }
    end

    def select_best_canonical_form(term_group)
      # Prefer forms with proper casing (has uppercase letters)
      # Then prefer the most common form
      # Then prefer the longest form
      
      candidates = term_group.map { |t| t[:canonical_term] }
      
      # Score each candidate
      scored_candidates = candidates.map do |candidate|
        score = 0
        score += 10 if candidate =~ /[A-Z]/  # Has uppercase
        score += 5 if candidate.include?(' ') # Multi-word term
        score += candidates.count(candidate)  # Frequency
        score += candidate.length / 10.0      # Length bonus
        
        { term: candidate, score: score }
      end

      # Return the highest scoring candidate
      scored_candidates.max_by { |c| c[:score] }[:term]
    end

    def deduplicate_surface_forms(surface_forms, canonical_term)
      # Remove duplicates while preserving case variations
      normalized_canonical = normalize_key(canonical_term)
      
      # Group by normalized form
      grouped = surface_forms.group_by { |form| normalize_key(form) }
      
      # Select best form from each group (prefer proper casing)
      unique_forms = grouped.map do |normalized, forms|
        # Skip if it's the same as canonical term
        next if normalized == normalized_canonical
        
        # Prefer forms with capitals or special formatting
        forms.max_by { |f| [f =~ /[A-Z]/ ? 1 : 0, f.length] }
      end.compact

      unique_forms
    end

    def select_best_description(term_group)
      descriptions = term_group.map { |t| t[:canonical_description] }.compact

      return nil if descriptions.empty?

      # Score descriptions by quality
      scored_descriptions = descriptions.map do |desc|
        score = 0
        score += desc.length  # Longer is usually more detailed
        score += 10 if desc =~ /\. /  # Multiple sentences
        score -= 20 if desc.length > 300  # Too long
        score -= 10 if desc =~ /\b(maybe|perhaps|possibly|unknown)\b/i  # Uncertain
        
        { description: desc, score: score }
      end

      # Return the highest scoring description
      scored_descriptions.max_by { |d| d[:score] }[:description]
    end

    def determine_term_type(term_group)
      # Count occurrences of each type
      type_counts = term_group
        .map { |t| t[:term_type] }
        .compact
        .tally

      return 'general' if type_counts.empty?

      # Prefer more specific types over 'general'
      if type_counts.size > 1 && type_counts['general']
        type_counts.delete('general')
      end

      # Return most common type
      type_counts.max_by { |_type, count| count }&.first || 'general'
    end

    def merge_metadata(term_group)
      all_metadata = term_group.map { |t| t[:metadata] || {} }

      {
        sources: all_metadata.flat_map { |m| Array(m[:source_type]) }.uniq.compact,
        confidence: all_metadata.map { |m| m[:confidence] || 0.5 }.sum / all_metadata.size,
        extraction_count: term_group.size,
        first_extracted_at: all_metadata.map { |m| m[:extracted_at] }.compact.min,
        source_metadata: all_metadata.flat_map { |m| Array(m[:source_metadata]) }.uniq
      }
    end
  end
end