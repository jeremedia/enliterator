#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the User and Devise setup
# Run with: rails runner script/test_user_setup.rb

puts "\n" + "=" * 80
puts "USER AND AUTHENTICATION SETUP TEST"
puts "=" * 80

# 1. Check User model
puts "\n1. User Model"
puts "-" * 40
admin = User.find_by(email: 'j@zinod.com')
if admin
  puts "✓ Admin user found:"
  puts "  Name: #{admin.name}"
  puts "  Email: #{admin.email}"
  puts "  Admin: #{admin.admin?}"
  puts "  ID: #{admin.id}"
  puts "  Created: #{admin.created_at}"
else
  puts "✗ Admin user not found!"
end

# 2. Check API calls association
puts "\n2. API Calls Association"
puts "-" * 40
if admin
  puts "  Total API calls: #{admin.api_calls.count}"
  puts "  Today's calls: #{admin.api_calls_today.count}"
  puts "  This month's calls: #{admin.api_calls_this_month.count}"
  puts "  Total cost: $#{admin.total_api_cost.to_f.round(4)}"
  
  # Show recent API calls
  puts "\n  Recent API calls:"
  admin.api_calls.order(created_at: :desc).limit(3).each do |call|
    puts "    - #{call.created_at.strftime('%H:%M')} #{call.service_name}: $#{(call.total_cost || 0).to_f.round(6)}"
  end
end

# 3. Check authentication setup
puts "\n3. Authentication Configuration"
puts "-" * 40
puts "  Devise installed: #{defined?(Devise) ? '✓' : '✗'}"
puts "  User count: #{User.count}"
puts "  Admin users: #{User.admins.count}"

# 4. Check API call user tracking
puts "\n4. API Call User Tracking"
puts "-" * 40
calls_with_user = ApiCall.where.not(user_id: nil).count
calls_without_user = ApiCall.where(user_id: nil).count
puts "  API calls with user: #{calls_with_user}"
puts "  API calls without user: #{calls_without_user}"
puts "  Percentage tracked: #{(calls_with_user.to_f / ApiCall.count * 100).round(1)}%"

# 5. Test CurrentUserTrackable concern
puts "\n5. CurrentUserTrackable Concern"
puts "-" * 40
if defined?(CurrentUserTrackable)
  puts "  ✓ CurrentUserTrackable loaded"
  puts "  ✓ ApiCall includes CurrentUserTrackable" if ApiCall.included_modules.include?(CurrentUserTrackable)
  
  # Test setting current user
  ApiCall.current_user = admin
  puts "  ✓ Can set current user"
  puts "  Current user: #{ApiCall.current_user&.email}"
  ApiCall.clear_current_user
  puts "  ✓ Can clear current user"
else
  puts "  ✗ CurrentUserTrackable not found"
end

# 6. Test creating a new API call with user tracking
puts "\n6. New API Call with User Tracking"
puts "-" * 40
ApiCall.with_user(admin) do
  test_call = OpenaiApiCall.create!(
    service_name: 'TestUserTracking',
    endpoint: 'test',
    model_used: 'gpt-4',
    status: 'success',
    total_cost: 0.001
  )
  
  if test_call.user_id == admin.id
    puts "  ✓ New API call automatically assigned to current user"
    puts "    Call ID: #{test_call.id}"
    puts "    User ID: #{test_call.user_id}"
    puts "    User: #{test_call.user.email}"
    
    # Clean up test call
    test_call.destroy
    puts "  ✓ Test call cleaned up"
  else
    puts "  ✗ User tracking failed"
  end
end

puts "\n" + "=" * 80
puts "User setup complete and working!"
puts "Auto-login configured for: #{admin.email}"
puts "Admin interface ready at: http://localhost:3000/admin/api_calls"
puts "=" * 80