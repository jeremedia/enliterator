#!/usr/bin/env ruby
# Test admin access setup

puts "Testing Admin Access Setup"
puts "=" * 50

# Check user exists
user = User.find_by(email: 'j@zinod.com')
if user
  puts "✅ User exists: #{user.email}"
  puts "✅ Admin flag: #{user.admin}"
  puts "✅ Valid password: #{user.valid_password?('password123')}"
else
  puts "❌ User not found!"
  exit 1
end

# Check Rails environment
puts "\nEnvironment:"
puts "  Rails.env: #{Rails.env}"
puts "  Development?: #{Rails.env.development?}"

# Test auto-login condition
if Rails.env.development?
  puts "\n✅ Auto-login should be active in development"
else
  puts "\n⚠️  Auto-login only works in development"
end

puts "\nAccess Instructions:"
puts "1. Go to http://localhost:3077/admin"
puts "2. You should be auto-logged in"
puts "3. If not, manually login with:"
puts "   Email: j@zinod.com"
puts "   Password: password123"
puts "\nNote: The login form now has 'data-turbo: false' to prevent CSRF issues"