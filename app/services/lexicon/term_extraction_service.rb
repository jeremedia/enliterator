# frozen_string_literal: true

module Lexicon
  # Model classes for structured term extraction
  class ExtractedTerm < OpenAI::BaseModel
    required :canonical_term, String, doc: "The normalized, properly cased canonical form"
    required :surface_forms, OpenAI::ArrayOf[String], doc: "Alternative forms, aliases, abbreviations"
    required :negative_surface_forms, OpenAI::ArrayOf[String], doc: "Common confusions or what this term is NOT"
    required :canonical_description, String, doc: "Neutral, factual description in 1-2 lines"
    required :term_type, OpenAI::EnumOf[:concept, :entity, :place, :event, :process, :attribute, :general], doc: "The type of term"
    required :confidence, Float, doc: "Extraction confidence (0-1)"
  end

  class ExtractionMetadata < OpenAI::BaseModel
    required :total_terms, Integer
    required :source_length, Integer
    required :language, String
    required :domain_indicators, OpenAI::ArrayOf[String]
  end

  class TermExtractionResult < OpenAI::BaseModel
    required :extracted_terms, OpenAI::ArrayOf[ExtractedTerm]
    required :extraction_metadata, ExtractionMetadata
  end

  # Service to extract canonical terms from content using OpenAI Structured Outputs
  # Uses the Responses API with strict JSON schema for reliable extraction
  class TermExtractionService < ApplicationService

    attr_reader :content, :source_type, :metadata

    def initialize(content:, source_type: nil, metadata: {})
      @content = content
      @source_type = source_type
      @metadata = metadata
    end

    def extract
      return { success: false, error: 'Content is blank' } if content.blank?

      # Prepare the extraction prompt
      messages = build_messages

      # Call OpenAI with Structured Outputs
      response = OPENAI.chat.completions.create(
        messages: messages,
        model: ENV.fetch('OPENAI_MODEL', 'gpt-4o-2024-08-06'),
        response_format: {
          type: "json_schema",
          json_schema: term_extraction_schema
        },
        temperature: 0  # Deterministic extraction
      )

      # Parse the structured response
      extracted_data = JSON.parse(response.choices.first.message.content)
      
      # Transform to our internal format
      terms = transform_extracted_terms(extracted_data)

      {
        success: true,
        terms: terms,
        confidence: calculate_confidence(extracted_data),
        raw_response: extracted_data
      }
    rescue StandardError => e
      Rails.logger.error "Term extraction failed: #{e.message}"
      { success: false, error: e.message }
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

    def term_extraction_schema
      {
        name: "TermExtraction",
        strict: true,  # REQUIRED for guaranteed schema compliance
        schema: {
          type: "object",
          properties: {
            extracted_terms: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  canonical_term: {
                    type: "string",
                    description: "The normalized, properly cased canonical form"
                  },
                  surface_forms: {
                    type: "array",
                    items: { type: "string" },
                    description: "Alternative forms, aliases, abbreviations"
                  },
                  negative_surface_forms: {
                    type: "array",
                    items: { type: "string" },
                    description: "Common confusions or what this term is NOT"
                  },
                  canonical_description: {
                    type: "string",
                    description: "Neutral, factual description in 1-2 lines"
                  },
                  term_type: {
                    type: "string",
                    enum: ["concept", "entity", "place", "event", "process", "attribute", "general"],
                    description: "The type of term"
                  },
                  confidence: {
                    type: "number",
                    minimum: 0,
                    maximum: 1,
                    description: "Extraction confidence (0-1)"
                  }
                },
                required: ["canonical_term", "surface_forms", "negative_surface_forms", "canonical_description", "term_type", "confidence"],
                additionalProperties: false
              }
            },
            extraction_metadata: {
              type: "object",
              properties: {
                total_terms: { type: "integer" },
                source_length: { type: "integer" },
                language: { type: "string" },
                domain_indicators: {
                  type: "array",
                  items: { type: "string" }
                }
              },
              required: ["total_terms", "source_length", "language", "domain_indicators"],
              additionalProperties: false
            }
          },
          required: ["extracted_terms", "extraction_metadata"],
          additionalProperties: false
        }
      }
    end

    def transform_extracted_terms(extracted_data)
      extracted_data['extracted_terms'].map do |term|
        {
          canonical_term: term['canonical_term'],
          surface_forms: term['surface_forms'].reject(&:blank?).uniq,
          negative_surface_forms: term['negative_surface_forms'].reject(&:blank?).uniq,
          canonical_description: term['canonical_description'],
          term_type: term['term_type'],
          metadata: {
            confidence: term['confidence'],
            source_type: source_type,
            extracted_at: Time.current,
            source_metadata: metadata
          }
        }
      end
    end

    def calculate_confidence(extracted_data)
      return 0.0 if extracted_data['extracted_terms'].empty?

      # Average confidence across all extracted terms
      total_confidence = extracted_data['extracted_terms'].sum { |t| t['confidence'] }
      total_confidence / extracted_data['extracted_terms'].size
    end
  end
end