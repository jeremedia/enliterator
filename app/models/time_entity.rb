# frozen_string_literal: true

# TimeEntity Pool - Temporal entities, periods, chronologies, schedules
# Part of the Ten Pool Canon for representing temporal concepts
# Note: Named TimeEntity to avoid conflict with Ruby's Time class
class TimeEntity < ApplicationRecord
  # Relationships
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :temporal_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Callbacks for Neo4j synchronization (maps to Method pool)
  after_commit :sync_to_graph, on: [:create, :update]
  after_commit :remove_from_graph, on: :destroy
  
  # Enums for temporal types
  enum :temporal_type, {
    period: 'period',           # Time spans (2020-2023, Arctic Summer)
    event: 'event',            # Specific moments (the 2019 expedition)
    schedule: 'schedule',      # Recurring patterns (daily monitoring)
    season: 'season',          # Seasonal concepts (winter conditions)
    chronology: 'chronology',  # Sequential timing (Phase 1, Phase 2)
    duration: 'duration'       # Length concepts (3-year study)
  }
  
  # Scopes
  scope :by_temporal_type, ->(type) { where(temporal_type: type) }
  scope :in_range, ->(start_time, end_time) { 
    where('start_time >= ? AND end_time <= ?', start_time, end_time) 
  }
  
  # Instance methods
  def duration_text
    return nil unless start_time && end_time
    "#{start_time.strftime('%Y-%m-%d')} to #{end_time.strftime('%Y-%m-%d')}"
  end
  
  def is_current?
    return false unless start_time && end_time
    now = Time.current
    now >= start_time && now <= end_time
  end
  
  # Class methods
  def self.search_by_period(query)
    where('label ILIKE ? OR description ILIKE ?', "%#{query}%", "%#{query}%")
  end
  
  private
  
  def sync_to_graph
    return unless defined?(Graph::MethodWriter)
    Graph::MethodWriter.new(self).sync
  rescue StandardError => e
    Rails.logger.error "Failed to sync TimeEntity #{id} to graph: #{e.message}"
  end
  
  def remove_from_graph
    return unless defined?(Graph::MethodRemover)
    Graph::MethodRemover.new(self).remove
  rescue StandardError => e
    Rails.logger.error "Failed to remove TimeEntity #{id} from graph: #{e.message}"
  end
end