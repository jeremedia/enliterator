# frozen_string_literal: true

class PromptTemplate < ApplicationRecord
  PURPOSES = %w[extraction conversation routing evaluation fine_tuning].freeze
  
  validates :name, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }, allow_nil: true
  validates :system_prompt, presence: true
  
  scope :active, -> { where(active: true) }
  scope :for_service, ->(service_class) { where(service_class: service_class) }
  scope :for_purpose, ->(purpose) { where(purpose: purpose) }
  
  def self.for(service_class_name)
    active.for_service(service_class_name).first
  end
  
  def render_user_prompt(variables = {})
    return user_prompt_template if user_prompt_template.blank?
    
    rendered = user_prompt_template.dup
    variables.each do |key, value|
      placeholder = "{{#{key}}}"
      rendered.gsub!(placeholder, value.to_s)
    end
    rendered
  end
  
  def build_messages(user_content, variables = {})
    [
      { role: "system", content: system_prompt },
      { role: "user", content: render_user_prompt(variables.merge(content: user_content)) }
    ]
  end
  
  def duplicate!(new_name)
    new_template = dup
    new_template.name = new_name
    new_template.active = false  # Start inactive
    new_template.save!
    new_template
  end
  
  def expected_variables
    return [] if user_prompt_template.blank?
    
    user_prompt_template.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end
  
  def validate_variables(provided_variables)
    expected = expected_variables
    provided = provided_variables.keys.map(&:to_s)
    
    missing = expected - provided
    extra = provided - expected
    
    {
      valid: missing.empty?,
      missing: missing,
      extra: extra
    }
  end
  
  def test_with_sample(sample_content, sample_variables = {})
    validation = validate_variables(sample_variables)
    return { error: "Missing variables: #{validation[:missing].join(', ')}" } unless validation[:valid]
    
    messages = build_messages(sample_content, sample_variables)
    
    {
      messages: messages,
      system_prompt_length: system_prompt.length,
      user_prompt_length: messages.last[:content].length,
      estimated_tokens: estimate_tokens(messages)
    }
  end
  
  private
  
  def estimate_tokens(messages)
    # Rough estimation: 1 token ~= 4 characters
    total_chars = messages.sum { |m| m[:content].length }
    (total_chars / 4.0).ceil
  end
end