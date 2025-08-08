#!/usr/bin/env ruby

# Update the correct keys that SettingsManager expects

extraction = OpenaiSetting.find_by(key: "model_extraction")
if extraction
  extraction.update!(value: "gpt-5-nano")
  puts "✅ Updated model_extraction to gpt-5-nano"
end

answer = OpenaiSetting.find_by(key: "model_answer")
if answer
  answer.update!(value: "gpt-5")
  puts "✅ Updated model_answer to gpt-5"
end

routing = OpenaiSetting.find_by(key: "model_routing")
if routing
  routing.update!(value: "gpt-5-nano")
  puts "✅ Updated model_routing to gpt-5-nano"
end

fine_tune = OpenaiSetting.find_by(key: "model_fine_tune")
if fine_tune
  fine_tune.update!(value: "gpt-5-mini")
  puts "✅ Updated model_fine_tune to gpt-5-mini"
end

base = OpenaiSetting.find_by(key: "model_fine_tune_base")
if base
  base.update!(value: "gpt-5-mini")
  puts "✅ Updated model_fine_tune_base to gpt-5-mini"
end

# Force reload
OpenaiConfig::SettingsManager.instance_variable_set(:@cached_config, nil)

puts
puts "New configuration:"
config = OpenaiConfig::SettingsManager.current_configuration
config[:models].each do |key, value|
  puts "  #{key}: #{value}"
end

puts
puts "🎉 Successfully upgraded to GPT-5!"
puts "Future pipeline stages will use GPT-5 for much faster processing."