#!/usr/bin/env ruby

# Fetch all available models from OpenAI API
client = OPENAI
response = client.models.list

puts "=== Available OpenAI Models ==="
puts

# Get all models - handle pagination
all_models = []
response.each_page do |page|
  page.data.each { |model| all_models << model }
end

# Filter for GPT and O1 models
gpt_models = all_models.select { |m| m.id.start_with?('gpt') }.map(&:id).sort
o1_models = all_models.select { |m| m.id.start_with?('o1') }.map(&:id).sort
other_relevant = all_models.select { |m| m.id.include?('turbo') || m.id.include?('davinci') }.map(&:id).sort

# Identify fine-tunable models
fine_tunable = all_models.select { |m| 
  m.id.include?('gpt-3.5-turbo') || 
  m.id.include?('gpt-4o-mini') ||
  m.id.include?('davinci-002') ||
  m.id.include?('babbage-002')
}.map(&:id).sort

puts "GPT Models:"
gpt_models.each { |m| puts "  #{m}#{fine_tunable.include?(m) ? ' (Fine-tunable)' : ''}" }

if o1_models.any?
  puts "\nO1 Models:"
  o1_models.each { |m| puts "  #{m}" }
end

if fine_tunable.any?
  puts "\nFine-tunable Models:"
  fine_tunable.each { |m| puts "  #{m}" }
end

puts "\n=== Model List for Edit View ==="
puts "options_for_select(["

# Generate options array for the view
model_options = []

# Add GPT models
gpt_models.each do |model|
  label = model
  label += " (Fine-tunable)" if fine_tunable.include?(model)
  model_options << "  ['#{label}', '#{model}']"
end

# Add O1 models
o1_models.each do |model|
  model_options << "  ['#{model.upcase.gsub('-', ' ')}', '#{model}']"
end

puts model_options.join(",\n")
puts "])"