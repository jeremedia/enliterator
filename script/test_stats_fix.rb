#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the stats calculation fix
# Run with: rails runner script/test_stats_fix.rb

require 'action_controller'

puts "\nTesting Admin::ApiCallsController stats calculation..."
puts "-" * 50

controller = Admin::ApiCallsController.new
controller.params = ActionController::Parameters.new(page: 1)

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

# Test the fixed methods
begin
  scope = controller.send(:filtered_api_calls)
  puts "✓ Filtered API calls: #{scope.count} records"
  
  stats = controller.send(:calculate_stats, scope)
  puts "✓ Stats calculated successfully!"
  puts "  Total: #{stats[:total_count]} calls"
  puts "  Cost: $#{stats[:total_cost]}"
  puts "  Success rate: #{stats[:success_rate]}%"
  puts "  Providers: #{stats[:providers].keys.map { |p| p&.gsub('ApiCall', '') || 'Unknown' }.join(', ')}"
  puts "  Models: #{stats[:models].keys.first(3).join(', ')}..."
  
  # Test with sorting applied
  sorted_scope = controller.send(:apply_sorting, scope)
  puts "✓ Sorting applied successfully"
  
  # Test pagination
  paginated = sorted_scope.page(1).per(10)
  puts "✓ Pagination applied: #{paginated.count} of #{scope.count} total"
  
  puts "\n✅ All tests passed! The admin interface should work now."
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(3)
end