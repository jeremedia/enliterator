# frozen_string_literal: true

# == Schema Information
#
# Table name: provenance_and_rights
#
#  id                   :bigint           not null, primary key
#  source_ids           :jsonb            not null
#  source_owner         :string
#  collectors           :jsonb
#  collection_method    :string           not null
#  consent_status       :integer          default("unknown"), not null
#  license_type         :integer          default("unspecified"), not null
#  custom_terms         :jsonb
#  publishability       :boolean          default(FALSE), not null
#  training_eligibility :boolean          default(FALSE), not null
#  embargo_until        :datetime
#  quarantined          :boolean          default(FALSE), not null
#  quarantine_reason    :string
#  valid_time_start     :datetime         not null
#  valid_time_end       :datetime
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  idx_on_valid_time_start_valid_time_end_afad4edcbc    (valid_time_start,valid_time_end)
#  index_p_and_r_on_publish_and_train                   (publishability,training_eligibility)
#  index_provenance_and_rights_on_embargo_until         (embargo_until)
#  index_provenance_and_rights_on_publishability        (publishability)
#  index_provenance_and_rights_on_quarantined           (quarantined)
#  index_provenance_and_rights_on_source_ids            (source_ids) USING gin
#  index_provenance_and_rights_on_training_eligibility  (training_eligibility)
#
class ProvenanceAndRights < ApplicationRecord
  include TimeTrackable
  
  # Associations
  has_many :ideas
  has_many :manifests
  has_many :experiences
  has_many :practicals
  has_many :emanations
  
  # Enums
  enum :consent_status, {
    unknown: 0,
    explicit_consent: 1,
    implicit_consent: 2,
    no_consent: 3,
    withdrawn: 4
  }, prefix: true
  
  enum :license_type, {
    unspecified: 0,
    cc0: 1,
    cc_by: 2,
    cc_by_sa: 3,
    cc_by_nc: 4,
    cc_by_nc_sa: 5,
    cc_by_nd: 6,
    cc_by_nc_nd: 7,
    proprietary: 8,
    public_domain: 9,
    fair_use: 10,
    custom: 11
  }, prefix: true
  
  # Validations
  validates :source_ids, presence: true
  validates :collection_method, presence: true
  validates :consent_status, presence: true
  validates :license_type, presence: true
  
  # Scopes
  scope :publishable, -> { where(publishability: true) }
  scope :training_eligible, -> { where(training_eligibility: true) }
  scope :quarantined, -> { where(quarantined: true) }
  scope :embargoed, -> { where("embargo_until > ?", Time.current) }
  
  # Callbacks
  before_validation :derive_rights
  
  # JSON fields
  # source_ids: Array of source identifiers
  # collectors: Array of collector names/ids
  # custom_terms: Hash of custom license terms
  
  def embargoed?
    embargo_until.present? && embargo_until > Time.current
  end
  
  def rights_summary
    {
      source: source_owner,
      license: license_display_name,
      consent: consent_status,
      publishable: publishability?,
      training_eligible: training_eligibility?,
      embargoed: embargoed?,
      attribution: attribution_text
    }
  end
  
  def license_display_name
    case license_type
    when "cc0" then "CC0 1.0 Universal"
    when "cc_by" then "CC BY 4.0"
    when "cc_by_sa" then "CC BY-SA 4.0"
    when "cc_by_nc" then "CC BY-NC 4.0"
    when "cc_by_nc_sa" then "CC BY-NC-SA 4.0"
    when "cc_by_nd" then "CC BY-ND 4.0"
    when "cc_by_nc_nd" then "CC BY-NC-ND 4.0"
    when "proprietary" then "Proprietary"
    when "public_domain" then "Public Domain"
    when "fair_use" then "Fair Use"
    when "custom" then custom_terms["name"] || "Custom License"
    else "Unspecified"
    end
  end
  
  def attribution_text
    return nil unless requires_attribution?
    
    parts = []
    parts << source_owner if source_owner.present?
    parts << license_display_name
    parts << custom_terms["attribution"] if custom_terms&.dig("attribution")
    
    parts.compact.join(" - ")
  end
  
  # Convenience methods for boolean attributes
  def publishable?
    publishability
  end
  
  def training_eligible?
    training_eligibility
  end
  
  def license
    license_display_name
  end
  
  private
  
  def derive_rights
    self.publishability = calculate_publishability
    self.training_eligibility = calculate_training_eligibility
  end
  
  def calculate_publishability
    return false if quarantined?
    return false if embargoed?
    return false if consent_status_no_consent? || consent_status_withdrawn?
    
    case license_type
    when "cc0", "cc_by", "cc_by_sa", "public_domain"
      true
    when "cc_by_nc", "cc_by_nc_sa", "cc_by_nd", "cc_by_nc_nd"
      # Non-commercial licenses - check intended use
      custom_terms&.dig("allow_public_display") == true
    when "proprietary", "custom"
      custom_terms&.dig("allow_public_display") == true
    else
      false
    end
  end
  
  def calculate_training_eligibility
    return false if quarantined?
    return false if consent_status_no_consent? || consent_status_withdrawn?
    
    case license_type
    when "cc0", "cc_by", "cc_by_sa", "public_domain"
      true
    when "cc_by_nc", "cc_by_nc_sa"
      # Non-commercial but allows derivative works
      true
    when "cc_by_nd", "cc_by_nc_nd"
      # No derivatives - cannot use for training
      false
    when "proprietary", "custom"
      custom_terms&.dig("allow_training") == true
    else
      false
    end
  end
  
  def requires_attribution?
    !["cc0", "public_domain"].include?(license_type)
  end
end
