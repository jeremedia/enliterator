# frozen_string_literal: true

# == Schema Information
#
# Table name: actors
#
#  id                       :bigint           not null, primary key
#  name                     :string           not null
#  role                     :string
#  description              :text
#  capabilities             :jsonb
#  affiliations             :jsonb
#  repr_text                :text             not null
#  provenance_and_rights_id :bigint           not null
#  valid_time_start         :datetime         not null
#  valid_time_end           :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_actors_on_name                                 (name)
#  index_actors_on_provenance_and_rights_id             (provenance_and_rights_id)
#  index_actors_on_role                                 (role)
#  index_actors_on_valid_time_start_and_valid_time_end  (valid_time_start,valid_time_end)
#
class Actor < ApplicationRecord
  include EknPoolEntity
  
  # Role enum with canonical values matching our extraction expectations
  enum :role, {
    individual: 0,
    organization: 1, 
    team: 2,
    role_position: 3
  }
  
  # Relationships to core pools
  has_many :actor_experiences, dependent: :destroy
  has_many :experiences, through: :actor_experiences
  
  has_many :actor_manifests, dependent: :destroy
  has_many :manifests, through: :actor_manifests
  
  # Additional validations (EknPoolEntity provides common ones)
  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "ActorAndRole"
    description "People and organizations with roles and permissions - entities that ACT"
    
    field :name, type: :string, required: true,
      examples: [
        "Dr. Sarah Johnson",
        "Senator Murkowski", 
        "Arctic Research Institute",
        "Research Team",
        "Community Elders"
      ],
      hints: "Look for individual names, organizations, titles like Dr./Professor, institutions acting as agents"
      
    field :role, type: :enum,
      values: -> { roles.keys },  # Live from model enum!
      default: 'individual',
      hints: "individual: people with titles like Dr./Professor; organization: institutions/agencies; team: groups/collectives; role_position: specific roles like Elder/Leader"
      
    field :description, type: :text, required: false,
      examples: [
        "Climate researcher specializing in Arctic studies",
        "Chairman of Energy and Natural Resources Committee",
        "Leading Arctic research institution"
      ],
      hints: "Brief description of who they are, their role, or expertise"
  end
  
  # Scopes
  scope :active_during, ->(time) { where('valid_time_start <= ? AND (valid_time_end IS NULL OR valid_time_end >= ?)', time, time) }
  scope :by_role, ->(role) { where(role: role) }
  
  # Callbacks
  before_validation :generate_repr_text, if: -> { repr_text.blank? }
  
  def active?
    valid_time_end.nil? || valid_time_end > Time.current
  end
  
  def time_period
    if valid_time_end.present?
      "#{valid_time_start.to_date} to #{valid_time_end.to_date}"
    else
      "Since #{valid_time_start.to_date}"
    end
  end
  
  private
  
  def generate_repr_text
    self.repr_text = "Actor: #{name}" + (role.present? ? " (#{role})" : "") +
                     " - #{description || 'No description'}" +
                     " [Active: #{time_period}]"
  end
  
  # Override display methods for better UX
  def display_name
    name
  end
  
  def full_description
    parts = [name]
    parts << "(#{role.humanize})" if role.present?
    parts << description if description.present?
    parts.join(' ')
  end
end
