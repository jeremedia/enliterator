# frozen_string_literal: true

module Lexicon
  # Model classes for structured term extraction
  class ExtractedTerm < OpenAI::Helpers::StructuredOutput::BaseModel
    required :canonical_term, String, doc: "The normalized, properly cased canonical form"
    required :surface_forms, OpenAI::ArrayOf[String], doc: "Alternative forms, aliases, abbreviations"
    required :negative_surface_forms, OpenAI::ArrayOf[String], doc: "Common confusions or what this term is NOT"
    required :canonical_description, String, doc: "Neutral, factual description in 1-2 lines"
    required :term_type, OpenAI::EnumOf[:concept, :entity, :place, :event, :process, :attribute, :general], doc: "The type of term"
    required :confidence, Float, doc: "Extraction confidence (0-1)"
  end

  class ExtractionMetadata < OpenAI::Helpers::StructuredOutput::BaseModel
    required :total_terms, Integer
    required :source_length, Integer
    required :language, String
    required :domain_indicators, OpenAI::ArrayOf[String]
  end

  class TermExtractionResult < OpenAI::Helpers::StructuredOutput::BaseModel
    required :extracted_terms, OpenAI::ArrayOf[ExtractedTerm]
    required :extraction_metadata, ExtractionMetadata
  end

  # Service to extract canonical terms from content using OpenAI Structured Outputs
  # Uses the Responses API with strict JSON schema for reliable extraction
  class TermExtractionService < OpenaiConfig::BaseExtractionService

    attr_reader :content, :source_type, :metadata

    def initialize(content:, source_type: nil, metadata: {})
      @content = content
      @source_type = source_type
      @metadata = metadata
    end

    def call
      super
    end
    
    # Backward compatibility alias
    alias extract call

    protected

    def response_model_class
      TermExtractionResult
    end

    def content_for_extraction
      content.truncate(8000)
    end

    def variables_for_prompt
      {
        source_type: source_type,
        metadata: metadata.to_json
      }
    end

    def validate_inputs!
      raise ExtractionError, 'Content is blank' if content.blank?
    end

    def transform_result(parsed_result)
      {
        success: true,
        terms: transform_extracted_terms(parsed_result),
        confidence: calculate_confidence(parsed_result),
        raw_response: parsed_result
      }
    end

    private

    def build_messages
      [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: "Extract canonical terms, surface forms, and descriptions from the following content:\n\n#{content.truncate(8000)}"
        }
      ]
    end

    def system_prompt
      <<~PROMPT
        You are a lexicon extraction specialist for the Enliterator system.
        Your task is to extract canonical terms from content and generate:
        1. Canonical terms (normalized, proper casing)
        2. Surface forms (aliases, alternate spellings, abbreviations)
        3. Negative surface forms (common confusions, things this is NOT)
        4. Canonical descriptions (neutral, factual, 1-2 lines)

        Focus on domain-specific terms, proper nouns, concepts, and technical vocabulary.
        For each term, provide multiple surface forms if they exist in the text or are commonly used.
        Canonical descriptions should be informative but neutral in tone.
      PROMPT
    end

    # No longer needed - using response model classes instead

    def transform_extracted_terms(parsed_result)
      return [] unless parsed_result.respond_to?(:extracted_terms)
      
      parsed_result.extracted_terms.map do |term|
        {
          canonical_term: term.canonical_term,
          surface_forms: term.surface_forms.reject(&:blank?).uniq,
          negative_surface_forms: term.negative_surface_forms.reject(&:blank?).uniq,
          canonical_description: term.canonical_description,
          term_type: term.term_type.to_s,
          metadata: {
            confidence: term.confidence,
            source_type: source_type,
            extracted_at: Time.current,
            source_metadata: metadata
          }
        }
      end
    end

    def calculate_confidence(parsed_result)
      return 0.0 unless parsed_result.respond_to?(:extracted_terms) && parsed_result.extracted_terms.any?

      # Average confidence across all extracted terms
      total_confidence = parsed_result.extracted_terms.sum(&:confidence)
      total_confidence / parsed_result.extracted_terms.size
    end
  end
end