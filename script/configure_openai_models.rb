#!/usr/bin/env ruby
# Configure OpenAI models with current gpt-4.1 family

puts "Configuring OpenAI settings with gpt-4.1 models..."

# Configure models for each task type
OpenaiSetting.set(
  'model_extraction',
  'gpt-4.1',
  category: 'model',
  model_type: 'extraction',
  description: 'Model for entity and term extraction (August 2025)'
)

OpenaiSetting.set(
  'model_answer',
  'gpt-4.1',
  category: 'model',
  model_type: 'answer',
  description: 'Model for generating answers and responses (August 2025)'
)

OpenaiSetting.set(
  'model_routing',
  'gpt-4.1-nano',
  category: 'model',
  model_type: 'routing',
  description: 'Ultra-fast model for routing decisions (August 2025)'
)

OpenaiSetting.set(
  'model_fine_tune',
  'gpt-4.1-mini',
  category: 'model',
  model_type: 'fine_tune',
  description: 'Model for fine-tuning tasks (August 2025)'
)

# Configure temperatures
OpenaiSetting.set(
  'temperature_extraction',
  '0.0',
  category: 'temperature',
  description: 'Zero temperature for deterministic extraction'
)

OpenaiSetting.set(
  'temperature_answer',
  '0.7',
  category: 'temperature',
  description: 'Moderate temperature for conversational responses'
)

OpenaiSetting.set(
  'temperature_routing',
  '0.0',
  category: 'temperature',
  description: 'Zero temperature for deterministic routing'
)

# Verify settings
puts "\nConfigured models:"
puts "  Extraction: #{OpenaiConfig::SettingsManager.model_for(:extraction)}"
puts "  Answer: #{OpenaiConfig::SettingsManager.model_for(:answer)}"
puts "  Routing: #{OpenaiConfig::SettingsManager.model_for(:routing)}"
puts "  Fine-tune: #{OpenaiConfig::SettingsManager.model_for(:fine_tune)}"

puts "\nConfigured temperatures:"
puts "  Extraction: #{OpenaiConfig::SettingsManager.temperature_for(:extraction)}"
puts "  Answer: #{OpenaiConfig::SettingsManager.temperature_for(:answer)}"
puts "  Routing: #{OpenaiConfig::SettingsManager.temperature_for(:routing)}"

puts "\n✅ OpenAI settings configured with current gpt-4.1 models"