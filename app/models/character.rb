# frozen_string_literal: true

# Character Pool - People, agents, roles, personas
# Part of the Ten Pool Canon for representing human actors and entities with agency
class Character < ApplicationRecord
  # Relationships
  belongs_to :provenance_and_rights
  
  # Validations
  validates :label, presence: true
  validates :role_type, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
  # Enums for role types
  enum :role_type, {
    individual: 'individual',           # Individual person (Dr. Sarah Johnson)
    team: 'team',                      # Research team, community group  
    organization: 'organization',      # University, agency (when acting as agent)
    role_position: 'role',            # Position or function (researcher, elder)
    persona: 'persona'                # Archetypal character or representative
  }
  
  # Scopes
  scope :by_role_type, ->(type) { where(role_type: type) }
  scope :active, -> { where(active: true) }
  scope :with_agency, -> { where(has_agency: true) }
  
  # Instance methods
  def display_name
    [label, title].compact.join(' - ')
  end
  
  def full_description
    [repr_text, biography].compact.join("\n\n")
  end
  
  # Class methods
  def self.search_by_name(query)
    where('label ILIKE ? OR title ILIKE ?', "%#{query}%", "%#{query}%")
  end
end