# frozen_string_literal: true

# Actor Pool - Represents agents/actors who perform actions or have agency
# Part of the optional pools that may or may not have content depending on the domain
class Actor < ApplicationRecord
  belongs_to :provenance_and_rights
  
  # Relationships to core pools
  has_many :actor_experiences, dependent: :destroy
  has_many :experiences, through: :actor_experiences
  
  has_many :actor_manifests, dependent: :destroy
  has_many :manifests, through: :actor_manifests
  
  # Validations
  validates :name, presence: true
  validates :repr_text, presence: true
  validates :valid_time_start, presence: true
  
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
end