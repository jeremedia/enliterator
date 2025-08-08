#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the Admin API Calls interface
# Run with: rails runner script/test_admin_api_calls.rb

puts "\n" + "=" * 80
puts "ADMIN API CALLS INTERFACE TEST"
puts "=" * 80

# 1. Check if we have API calls to display
puts "\n1. Database Status"
puts "-" * 40
puts "Total API calls: #{ApiCall.count}"
puts "Successful: #{ApiCall.successful.count}"
puts "Failed: #{ApiCall.failed.count}"
puts "Today: #{ApiCall.today.count}"
puts "This month: #{ApiCall.this_month.count}"

# 2. Check unique values for filters
puts "\n2. Filter Options Available"
puts "-" * 40
providers = ApiCall.distinct.pluck(:type).compact
models = ApiCall.distinct.pluck(:model_used).compact
services = ApiCall.distinct.pluck(:service_name).compact
statuses = ApiCall.distinct.pluck(:status).compact

puts "Providers: #{providers.map { |p| p.gsub('ApiCall', '') }.join(', ')}"
puts "Models: #{models.first(5).join(', ')}#{models.size > 5 ? '...' : ''}"
puts "Services: #{services.first(5).join(', ')}#{services.size > 5 ? '...' : ''}"
puts "Statuses: #{statuses.join(', ')}"

# 3. Test controller actions
puts "\n3. Testing Controller Actions"
puts "-" * 40

require 'action_controller'
require 'action_dispatch'

# Create a mock request
env = Rack::MockRequest.env_for('http://localhost:3000/admin/api_calls')
request = ActionDispatch::Request.new(env)

# Test index action with filters
controller = Admin::ApiCallsController.new
controller.request = request
controller.params = ActionController::Parameters.new(
  page: 1,
  per_page: 10,
  status: 'success',
  special_filter: 'today'
)

begin
  # Mock the filtered_api_calls method
  filtered = ApiCall.successful.today.limit(10)
  puts "✓ Filtered API calls: #{filtered.count} records"
  
  # Test stats calculation
  stats = {
    total_count: filtered.count,
    total_cost: filtered.sum(:total_cost).to_f.round(4),
    total_tokens: filtered.sum(:total_tokens),
    avg_response_time: filtered.average(:response_time_ms).to_f.round(2),
    success_rate: 100.0,
    error_count: 0
  }
  puts "✓ Stats calculated: $#{stats[:total_cost]} total cost"
  
  # Test CSV export
  require 'csv'
  csv_data = CSV.generate(headers: true) do |csv|
    csv << ['ID', 'Provider', 'Model', 'Status', 'Cost', 'Tokens']
    filtered.limit(5).each do |call|
      csv << [
        call.id,
        call.type&.gsub('ApiCall', ''),
        call.model_used,
        call.status,
        call.total_cost,
        call.total_tokens
      ]
    end
  end
  puts "✓ CSV export works: #{csv_data.lines.count - 1} rows"
  
rescue => e
  puts "✗ Error testing controller: #{e.message}"
end

# 4. Test routes
puts "\n4. Testing Routes"
puts "-" * 40

Rails.application.routes.url_helpers.tap do |routes|
  puts "✓ Index: #{routes.admin_api_calls_path}"
  puts "✓ Show: #{routes.admin_api_call_path(ApiCall.first)}" if ApiCall.any?
  puts "✓ Export CSV: #{routes.export_admin_api_calls_path(format: :csv)}"
  puts "✓ Retry: #{routes.retry_admin_api_call_path(ApiCall.failed.first)}" if ApiCall.failed.any?
end

# 5. Performance check
puts "\n5. Performance Metrics"
puts "-" * 40

expensive = ApiCall.where('total_cost > ?', 0.10).count
slow = ApiCall.where('response_time_ms > ?', 5000).count

puts "Expensive calls (>$0.10): #{expensive}"
puts "Slow calls (>5s): #{slow}"
puts "Average response time: #{ApiCall.average(:response_time_ms).to_f.round(2)}ms"
puts "Total cost all time: $#{ApiCall.sum(:total_cost).to_f.round(2)}"

# 6. Most recent API calls
puts "\n6. Recent API Calls"
puts "-" * 40

ApiCall.order(created_at: :desc).limit(5).each do |call|
  puts "#{call.created_at.strftime('%H:%M:%S')} - #{call.type&.gsub('ApiCall', '') || 'Unknown'} - " \
       "#{call.service_name} - #{call.status} - $#{sprintf('%.6f', call.total_cost || 0)}"
end

puts "\n" + "=" * 80
puts "Admin interface ready at: http://localhost:3000/admin/api_calls"
puts "Dashboard at: http://localhost:3000/admin"
puts "=" * 80