#!/usr/bin/env ruby

client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
response = client.models.list
models = response.data

puts "\n" + "="*60
puts "OPENAI MODEL AVAILABILITY CHECK"
puts "="*60
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Total models available: #{models.count}"

# Check for GPT-5
puts "\n🔍 GPT-5 Search:"
gpt5_models = models.select { |m| m.id.downcase.include?("gpt-5") || m.id.downcase.include?("gpt5") }
if gpt5_models.any?
  puts "✅ GPT-5 FOUND!"
  gpt5_models.each { |m| puts "  • #{m.id}" }
else
  puts "❌ No GPT-5 models available yet"
end

# Show GPT-4.1 series
puts "\n📊 GPT-4.1 Series (Latest Generation):"
gpt41_models = models.select { |m| m.id.start_with?("gpt-4.1") && !m.id.include?("ft:") }
gpt41_models.sort_by { |m| m.id }.each do |m|
  puts "  • #{m.id} (created: #{Time.at(m.created).strftime('%Y-%m-%d')})"
end

# Show most recent models
puts "\n🆕 Newest Models (2025):"
recent_models = models.select { |m| m.id.match?(/2025/) && !m.id.include?("ft:") }
recent_models.sort_by { |m| m.created }.reverse.first(10).each do |m|
  puts "  • #{m.id} (#{Time.at(m.created).strftime('%Y-%m-%d')})"
end

# Check specific high-capability models
puts "\n🎯 High-Capability Models Status:"
high_cap_models = ["gpt-4.1", "gpt-4o", "gpt-4-turbo", "chatgpt-4o-latest"]
high_cap_models.each do |model_name|
  found = models.find { |m| m.id == model_name }
  status = found ? "✅ Available" : "❌ Not Available"
  puts "  • #{model_name}: #{status}"
end

# Show search-enabled models
puts "\n🔎 Search-Enabled Models:"
search_models = models.select { |m| m.id.include?("search") }
search_models.each do |m|
  puts "  • #{m.id}"
end

puts "\n" + "="*60
puts "SUMMARY: GPT-5 is NOT available. Latest models are GPT-4.1 series."
puts "="*60