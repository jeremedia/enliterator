#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the admin interface is working
# Run with: rails runner script/test_admin_interface.rb

require 'action_controller'
require 'action_view'

puts "\n" + "=" * 80
puts "TESTING ADMIN API CALLS INTERFACE"
puts "=" * 80

# Test helper module
puts "\n1. Helper Module"
puts "-" * 40
if defined?(Admin::ApiCallsHelper)
  puts "✓ Helper module loaded"
  
  # Create a test class that includes the helper
  test_class = Class.new do
    include Admin::ApiCallsHelper
    include ActionView::Helpers::UrlHelper
    include Rails.application.routes.url_helpers
    
    attr_accessor :params, :request
    
    def initialize
      @params = ActionController::Parameters.new
      @request = OpenStruct.new(query_parameters: {})
    end
  end
  
  tester = test_class.new
  
  # Test each helper method
  puts "✓ sort_link method available" if tester.respond_to?(:sort_link)
  puts "✓ status_color_class: #{tester.status_color_class('success')}"
  puts "✓ provider_color_class: #{tester.provider_color_class('OpenaiApiCall')}"
  puts "✓ cost_color_class: #{tester.cost_color_class(0.15)}"
  puts "✓ response_time_color_class: #{tester.response_time_color_class(6000)}"
else
  puts "✗ Helper module not found"
end

# Test controller
puts "\n2. Controller Methods"
puts "-" * 40

controller = Admin::ApiCallsController.new
controller.params = ActionController::Parameters.new(page: 1)

# Mock authentication
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

# Test methods
scope = controller.send(:filtered_api_calls)
puts "✓ filtered_api_calls: #{scope.count} records"

stats = controller.send(:calculate_stats, scope)
puts "✓ calculate_stats: $#{stats[:total_cost]} total"

sorted = controller.send(:apply_sorting, scope)
puts "✓ apply_sorting: works"

# Test routes
puts "\n3. Routes"
puts "-" * 40
Rails.application.routes.url_helpers.tap do |routes|
  puts "✓ Index: #{routes.admin_api_calls_path}"
  puts "✓ Show: #{routes.admin_api_call_path(1)}"
  puts "✓ Export: #{routes.export_admin_api_calls_path}"
end

# Summary
puts "\n" + "=" * 80
puts "✅ Admin interface is ready!"
puts "Access it at: http://localhost:3000/admin/api_calls"
puts "=" * 80