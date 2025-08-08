#!/usr/bin/env ruby

client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
response = client.models.list
models = response.data

puts "\n" + "="*60
puts "GPT-5 AVAILABILITY CHECK"
puts "="*60
puts "Timestamp: #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
puts "Total models in API: #{models.count}"

# Check for GPT-5 models
puts "\n🔍 Searching for GPT-5 models:"
gpt5_models = models.select { |m| 
  m.id.downcase.include?("gpt-5") || 
  m.id.downcase.include?("gpt5") ||
  m.id.downcase == "gpt-5" ||
  m.id.downcase == "gpt-5-mini" ||
  m.id.downcase == "gpt-5-nano"
}

if gpt5_models.any?
  puts "✅ GPT-5 MODELS FOUND IN API!"
  gpt5_models.sort_by { |m| m.id }.each do |m|
    puts "\n  Model ID: #{m.id}"
    puts "  Created: #{Time.at(m.created).strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Owned by: #{m.owned_by if m.respond_to?(:owned_by)}"
  end
else
  puts "❌ GPT-5 models NOT YET available in API"
  puts "\nAccording to the website announcement:"
  puts "  • gpt-5 - Flagship model ($1.25 input / $10 output per 1M tokens)"
  puts "  • gpt-5-mini - Faster, cost-efficient ($0.25 input / $2 output per 1M tokens)"
  puts "  • gpt-5-nano - Fastest, most cost-efficient ($0.05 input / $0.40 output per 1M tokens)"
  puts "\n⚠️  Models may be rolling out gradually to API access"
end

# Show any very recent model additions (last 24 hours)
puts "\n📅 Models added in last 24 hours:"
recent_cutoff = Time.now.to_i - (24 * 60 * 60)
recent_models = models.select { |m| m.created > recent_cutoff }
if recent_models.any?
  recent_models.sort_by { |m| m.created }.reverse.each do |m|
    puts "  • #{m.id} (#{Time.at(m.created).strftime('%H:%M:%S %Z today')})"
  end
else
  puts "  None"
end

puts "\n" + "="*60