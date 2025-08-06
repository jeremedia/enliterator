# frozen_string_literal: true

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
    get(key) || ENV.fetch("OPENAI_MODEL", "gpt-4o-2024-08-06")
  end
  
  def self.temperature_for(task)
    key = "temperature_#{task}"
    value = get(key)
    value ? value.to_f : Rails.application.config.openai[:temperature][task.to_sym]
  end
  
  def self.supported_models
    {
      extraction: ["gpt-4o-2024-08-06", "gpt-4o-mini-2024-07-18"],
      answer: ["gpt-4o-2024-08-06", "gpt-4o-mini-2024-07-18", "gpt-4-turbo-preview"],
      routing: ["gpt-4o-mini-2024-07-18", "gpt-3.5-turbo"],
      fine_tune: ["gpt-4o-mini-2024-07-18", "gpt-3.5-turbo"]
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