#!/usr/bin/env ruby
# Ensure user has admin privileges

user = User.find_by(email: 'j@zinod.com')
if user
  puts "User found: #{user.email}"
  puts "Current admin status: #{user.admin}"
  
  unless user.admin
    user.update!(admin: true)
    puts "Updated admin status to: #{user.admin}"
  end
  
  puts "\nUser details:"
  puts "  ID: #{user.id}"
  puts "  Name: #{user.name}"
  puts "  Email: #{user.email}"
  puts "  Admin: #{user.admin}"
  puts "  Created: #{user.created_at}"
else
  puts "User not found. Creating..."
  user = User.create!(
    email: "j@zinod.com",
    name: "Jeremy Roush",
    password: "password123",
    password_confirmation: "password123",
    admin: true
  )
  puts "Admin user created successfully!"
end