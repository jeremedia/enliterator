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
