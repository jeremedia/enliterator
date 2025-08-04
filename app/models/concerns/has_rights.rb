# frozen_string_literal: true

# Concern for models that need rights and provenance tracking
module HasRights
  extend ActiveSupport::Concern
  
  included do
    belongs_to :provenance_and_rights, optional: false
    
    delegate :publishable?, :training_eligible?, :source_owner, 
             :license, :consent_status, to: :provenance_and_rights
    
    scope :publishable, -> { joins(:provenance_and_rights).where(provenance_and_rights: { publishability: true }) }
    scope :training_eligible, -> { joins(:provenance_and_rights).where(provenance_and_rights: { training_eligibility: true }) }
    scope :with_rights, -> { includes(:provenance_and_rights) }
    
    validates :provenance_and_rights, presence: true
  end
  
  class_methods do
    def require_rights(level = :public)
      case level
      when :public
        publishable
      when :internal
        training_eligible
      when :any
        all
      else
        raise ArgumentError, "Unknown rights level: #{level}"
      end
    end
  end
  
  def rights_summary
    {
      publishable: publishable?,
      training_eligible: training_eligible?,
      source: source_owner,
      license: license
    }
  end
  
  def check_rights_for(intended_use)
    case intended_use
    when :public_display
      publishable?
    when :training
      training_eligible?
    when :internal_use
      true
    else
      false
    end
  end
end