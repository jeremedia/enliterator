#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to create admin user and assign all API calls
# Run with: rails runner script/setup_admin_user.rb

puts "\n" + "=" * 80
puts "SETTING UP ADMIN USER"
puts "=" * 80

# Create or find admin user
admin = User.find_or_initialize_by(email: 'j@zinod.com') do |user|
  user.name = 'Jeremy Roush'
  user.password = 'temporary_password_change_me'
  user.password_confirmation = 'temporary_password_change_me'
  user.admin = true
end

if admin.new_record?
  admin.save!
  puts "\n✓ Created admin user:"
else
  admin.update!(name: 'Jeremy Roush', admin: true)
  puts "\n✓ Updated existing admin user:"
end

puts "  Name: #{admin.name}"
puts "  Email: #{admin.email}"
puts "  Admin: #{admin.admin?}"
puts "  ID: #{admin.id}"

# Assign all API calls to this user
puts "\n" + "-" * 40
puts "Assigning API calls to admin user..."

api_calls_without_user = ApiCall.where(user_id: nil).count
if api_calls_without_user > 0
  ApiCall.where(user_id: nil).update_all(user_id: admin.id)
  puts "✓ Assigned #{api_calls_without_user} API calls to admin user"
else
  puts "✓ All API calls already have a user assigned"
end

# Show summary
puts "\n" + "-" * 40
puts "Summary:"
puts "  Total users: #{User.count}"
puts "  Admin users: #{User.where(admin: true).count}"
puts "  Total API calls: #{ApiCall.count}"
puts "  Admin's API calls: #{ApiCall.where(user_id: admin.id).count}"

puts "\n" + "=" * 80
puts "Admin user setup complete!"
puts "Auto-login is configured for development environment."
puts "=" * 80