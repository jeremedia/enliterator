# frozen_string_literal: true

# == Schema Information
#
# Table name: openai_settings
#
#  id          :bigint           not null, primary key
#  key         :string           not null
#  category    :string
#  value       :text
#  description :text
#  model_type  :string
#  metadata    :jsonb
#  active      :boolean          default(TRUE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_openai_settings_on_active      (active)
#  index_openai_settings_on_category    (category)
#  index_openai_settings_on_key         (key) UNIQUE
#  index_openai_settings_on_model_type  (model_type)
#
class OpenaiSetting < ApplicationRecord
  CATEGORIES = %w[model prompt temperature config].freeze
  MODEL_TYPES = %w[extraction answer routing fine_tune].freeze
  
  validates :key, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :model_type, inclusion: { in: MODEL_TYPES }, allow_nil: true
  
  scope :active, -> { where(active: true) }
  scope :models, -> { where(category: 'model') }
  scope :prompts, -> { where(category: 'prompt') }
  scope :temperatures, -> { where(category: 'temperature') }
  scope :configs, -> { where(category: 'config') }
  
  scope :for_extraction, -> { where(model_type: 'extraction') }
  scope :for_answers, -> { where(model_type: 'answer') }
  scope :for_routing, -> { where(model_type: 'routing') }
  scope :for_fine_tuning, -> { where(model_type: 'fine_tune') }
  
  def self.get(key, default = nil)
    setting = active.find_by(key: key)
    setting&.value || default
  end
  
  def self.set(key, value, category: nil, model_type: nil, description: nil)
    setting = find_or_initialize_by(key: key)
    setting.update!(
      value: value,
      category: category,
      model_type: model_type,
      description: description,
      active: true
    )
    setting
  end
  
  def self.model_for(task)
    key = "model_#{task}"
    get(key) || ENV.fetch("OPENAI_MODEL")
  end
  
  def self.temperature_for(task)
    key = "temperature_#{task}"
    value = get(key)
    value ? value.to_f : Rails.application.config.openai[:temperature][task.to_sym]
  end
  
  def self.supported_models
    {
      extraction: ["gpt-4.1", "gpt-4.1-mini"],
      answer: ["gpt-4.1", "gpt-4.1-mini"],
      routing: ["gpt-4.1-nano", "gpt-4.1-mini"],
      fine_tune: ["gpt-4.1-mini", "gpt-4.1-nano"]
    }
  end
  
  def value_as_float
    value.to_f if value.present?
  end
  
  def value_as_json
    JSON.parse(value) if value.present?
  rescue JSON::ParserError
    nil
  end
end
