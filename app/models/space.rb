# frozen_string_literal: true

# Space Pool - Locations, places, geographic entities, spatial relationships
# Part of the Ten Pool Canon for representing spatial concepts
class Space < ApplicationRecord
  # Relationships
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :spatial_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Enums for spatial types
  enum :spatial_type, {
    geographic: 'geographic',     # Physical locations (Beaufort Sea, Alaska)
    administrative: 'administrative', # Political boundaries (North Slope Borough)
    conceptual: 'conceptual',     # Abstract spaces (research area, domain)
    facility: 'facility',        # Buildings, stations (research station)
    region: 'region',            # Areas (Arctic region, northern Alaska)
    coordinate: 'coordinate'     # Specific coordinates (GPS locations)
  }
  
  # Scopes
  scope :by_spatial_type, ->(type) { where(spatial_type: type) }
  scope :within_bounds, ->(lat_min, lat_max, lng_min, lng_max) {
    where('latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?', 
          lat_min, lat_max, lng_min, lng_max)
  }
  
  # Instance methods
  def coordinates_text
    return nil unless latitude && longitude
    "#{latitude.round(4)}, #{longitude.round(4)}"
  end
  
  def full_location
    [label, region, country].compact.join(', ')
  end
  
  # Class methods
  def self.search_by_location(query)
    where('label ILIKE ? OR region ILIKE ? OR country ILIKE ?', 
          "%#{query}%", "%#{query}%", "%#{query}%")
  end
end