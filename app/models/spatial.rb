# frozen_string_literal: true

# == Schema Information
#
# Table name: spatials
#
#  id                       :bigint           not null, primary key
#  location_name            :string           not null
#  sector                   :string
#  portal                   :string
#  year                     :integer
#  coordinates              :jsonb
#  neighbors                :jsonb
#  placement_type           :string
#  description              :text
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_spatials_on_location_name                        (location_name)
#  index_spatials_on_portal                               (portal)
#  index_spatials_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_spatials_on_sector                               (sector)
#  index_spatials_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#  index_spatials_on_year                                 (year)
#
class Spatial < ApplicationRecord
  include EknPoolEntity
  
  # Placement type enum for spatial classification
  enum :placement_type, {
    point: 0,        # Specific locations, landmarks, stations
    region: 1,       # Large areas like "Arctic Ocean", "Beaufort Sea"  
    area: 2,         # Defined zones, camps, research areas
    route: 3,        # Paths, transects, shipping routes
    boundary: 4      # Borders, limits, boundaries
  }
  
  # Relationships (EknPoolEntity provides provenance_and_rights)
  has_many :manifest_spatials, dependent: :destroy
  has_many :manifests, through: :manifest_spatials
  
  # Additional validations (EknPoolEntity provides common ones)
  validates :location_name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "Spatial"
    description "Places, regions, geometries, spatial hierarchies - geographic entities"
    
    field :location_name, type: :string, required: true,
      examples: [
        "Beaufort Sea region",
        "Anchorage, Alaska", 
        "Arctic Research Station",
        "Bering Strait",
        "Point Barrow"
      ],
      hints: "Look for specific place names, geographic regions, landmarks, research stations, bodies of water"
      
    field :placement_type, type: :enum,
      values: -> { placement_types.keys },  # Live from model enum!
      default: 'region',
      hints: "point: specific coordinates/landmarks; region: large areas like seas/states; area: defined zones; route: paths/transects; boundary: borders/limits"
      
    field :sector, type: :string, required: false,
      examples: ["North", "Northeast", "Central", "Outer"],
      hints: "Sector designation for Arctic research areas, compass directions"
      
    field :portal, type: :string, required: false,
      examples: ["3:30", "6:00", "9:00", "12:00"],
      hints: "Portal designation using clock positions (e.g., 3:30, 6:00)"
      
    field :year, type: :integer, required: false,
      examples: [2019, 2020, 2021, 2022, 2023],
      hints: "Year when this spatial entity was relevant or observed"
      
    field :description, type: :text, required: false,
      examples: [
        "Major Arctic sea region with seasonal ice coverage",
        "Primary research station for climate monitoring", 
        "Strategic shipping route through Arctic waters"
      ],
      hints: "Additional context about the location, its significance, or characteristics"
  end
  
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
