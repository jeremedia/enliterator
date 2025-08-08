# frozen_string_literal: true

# Spatial Pool - Represents location and spatial information
# Used for domains that have physical or conceptual spatial dimensions
class Spatial < ApplicationRecord
  belongs_to :provenance_and_rights
  
  # Relationships
  has_many :manifest_spatials, dependent: :destroy
  has_many :manifests, through: :manifest_spatials
  
  # Validations
  validates :location_name, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Scopes
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :by_portal, ->(portal) { where(portal: portal) }
  scope :by_year, ->(year) { where(year: year) }
  scope :active_during, ->(time) { where('valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end >= ?)', time, time) }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def location_description
    parts = [location_name]
    parts << "Sector #{sector}" if sector.present?
    parts << "Portal #{portal}" if portal.present?
    parts << "Year #{year}" if year.present?
    parts.join(", ")
  end
  
  def has_coordinates?
    coordinates.present? && coordinates['lat'].present? && coordinates['lng'].present?
  end
  
  def neighbor_count
    neighbors.is_a?(Array) ? neighbors.size : 0
  end
  
  private
  
  def generate_repr_text
    self.repr_text = "Spatial: #{location_description}" +
                     (description.present? ? " - #{description}" : "") +
                     (neighbor_count > 0 ? " [#{neighbor_count} neighbors]" : "")
  end
end