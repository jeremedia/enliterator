#!/usr/bin/env ruby

puts "Updating OpenAI configuration to use GPT-5 models..."
puts

# Update extraction model to GPT-5 nano for speed
extraction_setting = OpenaiSetting.find_by(key: "extraction_model")
if extraction_setting
  old_value = extraction_setting.value
  extraction_setting.update!(value: "gpt-5-nano")
  puts "✅ Extraction: #{old_value} → gpt-5-nano"
else
  OpenaiSetting.create!(key: "extraction_model", value: "gpt-5-nano", active: true)
  puts "✅ Created extraction setting: gpt-5-nano"
end

# Update answer model to GPT-5 for capability
answer_setting = OpenaiSetting.find_by(key: "answer_model")
if answer_setting
  old_value = answer_setting.value
  answer_setting.update!(value: "gpt-5")
  puts "✅ Answer: #{old_value} → gpt-5"
else
  OpenaiSetting.create!(key: "answer_model", value: "gpt-5", active: true)
  puts "✅ Created answer setting: gpt-5"
end

# Update routing model to GPT-5 nano for speed
routing_setting = OpenaiSetting.find_by(key: "routing_model")
if routing_setting
  old_value = routing_setting.value
  routing_setting.update!(value: "gpt-5-nano")
  puts "✅ Routing: #{old_value} → gpt-5-nano"
else
  OpenaiSetting.create!(key: "routing_model", value: "gpt-5-nano", active: true)
  puts "✅ Created routing setting: gpt-5-nano"
end

# Update fine-tune base to GPT-5 mini
fine_tune_setting = OpenaiSetting.find_by(key: "fine_tune_base_model")
if fine_tune_setting
  old_value = fine_tune_setting.value
  fine_tune_setting.update!(value: "gpt-5-mini")
  puts "✅ Fine-tune base: #{old_value} → gpt-5-mini"
else
  OpenaiSetting.create!(key: "fine_tune_base_model", value: "gpt-5-mini", active: true)
  puts "✅ Created fine-tune setting: gpt-5-mini"
end

puts
puts "New configuration:"
puts "="*40

config = OpenaiConfig::SettingsManager.current_configuration
puts "Models:"
config[:models].each do |key, value|
  puts "  #{key}: #{value}"
end

puts
puts "🎉 Successfully upgraded to GPT-5!"
puts "New extraction jobs will use the faster GPT-5 models."
puts
puts "Note: Currently running jobs will continue with their original models."
puts "The Lexicon job in progress will complete with GPT-4.1, but subsequent"
puts "stages (Pools, Graph, etc.) will use GPT-5 for much faster processing."