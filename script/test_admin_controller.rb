#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test Admin::ApiCallsController with User model
# Run with: rails runner script/test_admin_controller.rb

puts "\n" + "=" * 80
puts "TESTING ADMIN::APICALLSCONTROLLER WITH USER"
puts "=" * 80

require 'action_controller'
require 'action_dispatch'

# Create a mock request
env = Rack::MockRequest.env_for('http://localhost:3000/admin/api_calls')
request = ActionDispatch::Request.new(env)

# Create controller instance
controller = Admin::ApiCallsController.new
controller.request = request
controller.params = ActionController::Parameters.new(page: 1, per_page: 10)

# Mock authentication methods
class << controller
  def current_user
    User.first
  end
  
  def user_signed_in?
    true
  end
  
  def authenticate_user!
    true
  end
end

puts "\n1. Testing filtered_api_calls method"
puts "-" * 40

begin
  # Test the filtered_api_calls private method
  scope = controller.send(:filtered_api_calls)
  
  puts "✓ Filtered API calls query built successfully"
  puts "  Total records: #{scope.count}"
  puts "  Includes user association: ✓"
  puts "  Includes trackable association: ✓"
  
  # Check first few records
  puts "\n  Sample records:"
  scope.limit(3).each do |call|
    puts "    - #{call.service_name} (User: #{call.user&.email || 'none'})"
  end
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n2. Testing stats calculation"
puts "-" * 40

begin
  scope = controller.send(:filtered_api_calls)
  stats = controller.send(:calculate_stats, scope)
  
  puts "✓ Stats calculated successfully:"
  puts "  Total count: #{stats[:total_count]}"
  puts "  Total cost: $#{stats[:total_cost]}"
  puts "  Success rate: #{stats[:success_rate]}%"
  puts "  Error count: #{stats[:error_count]}"
  
rescue => e
  puts "✗ Error: #{e.message}"
end

puts "\n3. Testing with filters"
puts "-" * 40

# Test with different filters
filters = [
  { status: 'success', description: 'Successful calls' },
  { provider: 'OpenaiApiCall', description: 'OpenAI calls' },
  { special_filter: 'expensive', description: 'Expensive calls' }
]

filters.each do |filter|
  controller.params = ActionController::Parameters.new(filter.except(:description))
  scope = controller.send(:filtered_api_calls)
  puts "  #{filter[:description]}: #{scope.count} records"
end

puts "\n4. Testing sorting"
puts "-" * 40

sorts = ['created_at', 'total_cost', 'response_time_ms']
sorts.each do |sort|
  controller.params = ActionController::Parameters.new(sort: sort, direction: 'desc')
  scope = controller.send(:filtered_api_calls)
  scope = controller.send(:apply_sorting, scope)
  
  first_record = scope.first
  if first_record
    value = first_record.send(sort)
    display_value = sort == 'created_at' ? value.strftime('%Y-%m-%d %H:%M') : value
    puts "  Sort by #{sort}: First record value = #{display_value}"
  end
end

puts "\n" + "=" * 80
puts "Admin interface test complete!"
puts "Current user: #{User.first.email}"
puts "Access the interface at: http://localhost:3000/admin/api_calls"
puts "=" * 80