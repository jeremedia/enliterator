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
  include EknPoolEntity
  
  # Associations (EknPoolEntity is itself belonged_to by other entities)
  has_many :ideas
  has_many :manifests
  has_many :experiences
  has_many :practicals
  has_many :emanations
  has_many :actors
  has_many :spatials  
  has_many :method_pools
  has_many :evidences
  has_many :risks
  has_many :relationals
  
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
  
  # Model-driven extraction configuration
  extraction_config do
    canonical_name "ProvenanceAndRights"
    description "Source, attribution, consent, license, lineage - data provenance and rights management"
    
    field :source_ids, type: :json, required: true,
      examples: [
        ["2e94ea4c07ae6377db3365a8fe5f11455a3ad63196effa566d27bfa6604b4589"],
        ["abc123def456", "789ghi012jkl"]
      ],
      hints: "Array of source identifiers, file hashes, URLs, or document IDs for tracking data lineage"
      
    field :source_owner, type: :string, required: false,
      examples: ["Dr. Sarah Johnson", "Arctic Research Institute", "NOAA Climate Data", "Anonymous"],
      hints: "Name of the data owner, author, or originating organization"
      
    field :collection_method, type: :string, required: true,
      examples: ["automated_ingestion", "manual_upload", "survey_response", "interview_transcription", "sensor_data"],
      hints: "How this data was collected or obtained"
      
    field :consent_status, type: :enum,
      values: -> { consent_statuses.keys },  # Live from model enum!
      default: 'unknown',
      hints: "explicit_consent: clear permission given; implicit_consent: reasonable to assume; no_consent: permission denied; withdrawn: consent revoked; unknown: status unclear"
      
    field :license_type, type: :enum,
      values: -> { license_types.keys },  # Live from model enum!
      default: 'unspecified',
      hints: "cc0: public domain; cc_by: attribution required; cc_by_sa: share-alike; cc_by_nc: non-commercial; proprietary: restricted use; custom: see custom_terms"
      
    field :custom_terms, type: :json, required: false,
      examples: [
        {"attribution": "Source: Arctic Research Project 2023", "allow_public_display": true},
        {"restrictions": "Internal use only", "contact": "data-owner@example.org"}
      ],
      hints: "Custom license terms, attribution requirements, or usage restrictions"
      
    field :collectors, type: :json, required: false,
      examples: [
        ["Dr. Johnson", "Research Assistant Adams"],
        ["Automated sensor system", "Field team Alpha"]
      ],
      hints: "Array of people, systems, or organizations involved in data collection"
  end
  
  # Validations (EknPoolEntity provides common ones)
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
