# frozen_string_literal: true

# Symbolic Pool - Symbols, meanings, representations, metaphors  
# Part of the Ten Pool Canon for representing abstract significance
class Symbolic < ApplicationRecord
  # Relationships
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :symbol_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Enums for symbol types
  enum :symbol_type, {
    metaphor: 'metaphor',        # "ice as memory of ancestors"
    cultural: 'cultural',        # Cultural symbols and meanings
    representation: 'representation', # Abstract representations
    meaning: 'meaning',          # Deeper significance beyond literal
    symbol: 'symbol',           # Traditional symbols
    archetype: 'archetype'      # Archetypal patterns
  }
  
  # Scopes
  scope :by_symbol_type, ->(type) { where(symbol_type: type) }
  scope :cultural_symbols, -> { where(symbol_type: ['cultural', 'archetype']) }
  scope :metaphorical, -> { where(symbol_type: 'metaphor') }
  
  # Instance methods
  def interpretation_text
    [meaning, cultural_context].compact.join(' - ')
  end
  
  def full_symbolism
    "#{label}: #{meaning}#{cultural_context ? " (#{cultural_context})" : ""}"
  end
  
  # Class methods
  def self.search_by_meaning(query)
    where('label ILIKE ? OR meaning ILIKE ? OR cultural_context ILIKE ?', 
          "%#{query}%", "%#{query}%", "%#{query}%")
  end
end