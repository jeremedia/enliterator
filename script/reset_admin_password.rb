#!/usr/bin/env ruby
# Reset admin password

user = User.find_by(email: "j@zinod.com")
if user
  user.update!(password: "password123", password_confirmation: "password123")
  puts "Password reset successfully!"
  puts "Email: #{user.email}"
  puts "Password: password123"
else
  user = User.create!(
    email: "j@zinod.com",
    name: "Jeremy Roush",
    password: "password123",
    password_confirmation: "password123",
    admin: true
  )
  puts "User created!"
  puts "Email: j@zinod.com"
  puts "Password: password123"
end

# Also fix auto-login
puts "\nAuto-login status:"
puts "Rails.env.development? = #{Rails.env.development?}"
puts "User exists? = #{User.exists?(email: 'j@zinod.com')}"