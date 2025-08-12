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
  
  # Callbacks for Neo4j synchronization (maps to Emanation pool)
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
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
  
  private
  
  def sync_to_graph
    return unless defined?(Graph::SymbolicWriter)
    Graph::SymbolicWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync Symbolic #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::SymbolicRemover)
    Graph::SymbolicRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove Symbolic #{id} from graph: #{e.message}"
  end
end