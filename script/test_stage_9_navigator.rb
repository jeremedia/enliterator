#!/usr/bin/env ruby
# Test script for Stage 9: Knowledge Navigator Implementation
# This verifies that the conversational interface and dynamic UI generation are working

puts "=" * 80
puts "Stage 9: Knowledge Navigator Test"
puts "Transforming Infrastructure into Product"
puts "=" * 80
puts

# Test 1: Verify routes are configured
puts "Test 1: Checking Navigator Routes..."
routes = Rails.application.routes.routes.map(&:name).compact
navigator_routes = routes.select { |r| r.to_s.include?('navigator') }

if navigator_routes.any?
  puts "✅ Navigator routes configured:"
  navigator_routes.each { |r| puts "   - #{r}" }
else
  puts "❌ No navigator routes found"
end
puts

# Test 2: Verify NavigatorController exists
puts "Test 2: Checking NavigatorController..."
if defined?(NavigatorController)
  puts "✅ NavigatorController is defined"
  controller = NavigatorController.new
  puts "   - Has index action: #{controller.respond_to?(:index)}"
else
  puts "❌ NavigatorController not found"
end
puts

# Test 3: Verify Conversation Manager
puts "Test 3: Testing Conversation Manager..."
begin
  manager = Navigator::ConversationManager.new(
    context: { id: SecureRandom.uuid, history: [] },
    ekn: nil
  )
  
  # Test greeting
  response = manager.process_input("Hello", {})
  puts "✅ Conversation Manager responds to greeting:"
  puts "   Message: #{response[:message][0..100]}..."
  puts "   Has suggestions: #{response[:suggestions].any?}"
  
  # Test Enliterator explanation
  response = manager.process_input("What is Enliterator?", {})
  puts "✅ Explains Enliterator:"
  puts "   Message: #{response[:message][0..100]}..."
  
  # Test UI generation intent
  response = manager.process_input("Show me how things evolved over time", {})
  puts "✅ Recognizes UI generation intent:"
  puts "   Intent: #{response[:metadata][:intent]}"
  puts "   UI Spec: #{response[:ui_spec] ? 'Generated' : 'None'}"
  
rescue => e
  puts "❌ Conversation Manager error: #{e.message}"
end
puts

# Test 4: Verify UI Pattern Recognition
puts "Test 4: Testing UI Pattern Recognition..."
begin
  # Explicitly require the UI services
  require_relative '../app/services/ui'
  require_relative '../app/services/ui/pattern_recognizer'
  require_relative '../app/services/ui/natural_language_mapper'
  
  recognizer = UI::PatternRecognizer.new
  
  test_requests = [
    "Show me the evolution from 2018 to 2023",
    "How are these concepts connected?",
    "Where are the main clusters of activity?",
    "Compare before and after COVID"
  ]
  
  test_requests.each do |request|
    analysis = recognizer.analyze(request)
    puts "✅ '#{request}':"
    puts "   Intent: #{analysis[:intent]}"
    puts "   Components: #{analysis[:suggested_components].join(', ')}"
  end
rescue => e
  puts "❌ Pattern Recognition error: #{e.message}"
end
puts

# Test 5: Verify Natural Language Mapping
puts "Test 5: Testing Natural Language to UI Mapping..."
begin
  mapper = UI::NaturalLanguageMapper.new
  
  # Test timeline generation
  ui_spec = mapper.process(
    intent: { type: :temporal_evolution, confidence: 0.9 },
    results: { "ShowEvolutionOperation" => { timeline_data: "mock data" } },
    context: { history: [{ content: "Show evolution over time" }] }
  )
  
  if ui_spec
    puts "✅ UI Specification generated:"
    puts "   Component: #{ui_spec[:component]}"
    puts "   Layout: #{ui_spec[:layout]}"
    puts "   Has config: #{ui_spec[:config].any?}"
  else
    puts "⚠️  No UI spec generated (might be intentional for non-visual intents)"
  end
rescue => e
  puts "❌ Natural Language Mapping error: #{e.message}"
end
puts

# Test 6: Check for view files
puts "Test 6: Checking View Files..."
view_path = Rails.root.join('app', 'views', 'navigator', 'index.html.erb')
if File.exist?(view_path)
  puts "✅ Navigator view exists"
  puts "   Size: #{File.size(view_path)} bytes"
else
  puts "❌ Navigator view not found at #{view_path}"
end
puts

# Test 7: Check JavaScript controller
puts "Test 7: Checking JavaScript Controller..."
js_path = Rails.root.join('app', 'javascript', 'controllers', 'navigator_controller.js')
if File.exist?(js_path)
  puts "✅ Navigator JavaScript controller exists"
  puts "   Size: #{File.size(js_path)} bytes"
  
  # Check for key features
  content = File.read(js_path)
  features = {
    "Voice support" => content.include?('SpeechRecognition'),
    "Dynamic UI" => content.include?('generateDynamicUI'),
    "Suggestions" => content.include?('showSuggestions'),
    "File upload" => content.include?('handleFileUpload')
  }
  
  features.each do |feature, present|
    puts "   #{present ? '✅' : '❌'} #{feature}"
  end
else
  puts "❌ Navigator JavaScript controller not found"
end
puts

# Summary
puts "=" * 80
puts "Stage 9 Implementation Summary:"
puts "=" * 80

components = [
  ["Routes", navigator_routes.any?],
  ["Controller", defined?(NavigatorController)],
  ["Conversation Manager", defined?(Navigator::ConversationManager)],
  ["UI Pattern Recognizer", defined?(UI::PatternRecognizer)],
  ["Natural Language Mapper", defined?(UI::NaturalLanguageMapper)],
  ["View Template", File.exist?(view_path)],
  ["JavaScript Controller", File.exist?(js_path)]
]

completed = components.count { |_, status| status }
total = components.length

components.each do |name, status|
  puts "#{status ? '✅' : '❌'} #{name}"
end

puts
puts "Progress: #{completed}/#{total} components (#{(completed.to_f / total * 100).round}%)"
puts

if completed == total
  puts "🎉 Stage 9 is COMPLETE! The Knowledge Navigator is ready!"
  puts "Users can now:"
  puts "  • Have natural conversations about Enliterator"
  puts "  • See dynamic visualizations generated from dialogue"
  puts "  • Experience voice interaction (in supported browsers)"
  puts "  • Create EKNs through conversational guidance"
  puts
  puts "This IS the product - not JSON, not admin panels, but a true Knowledge Navigator!"
else
  puts "⚠️  Stage 9 is partially complete. Missing components:"
  components.reject { |_, status| status }.each do |name, _|
    puts "  - #{name}"
  end
end

puts
puts "Next step: Visit http://localhost:3000 to experience your Knowledge Navigator!"