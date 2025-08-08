#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to clear test API calls if desired
# Run with: rails runner script/clear_test_api_calls.rb

puts "\nCurrent API calls:"
puts "-" * 40
ApiCall.group(:service_name).count.each do |service, count|
  puts "#{service}: #{count}"
end
puts "-" * 40
puts "Total: #{ApiCall.count} (Total cost: $#{ApiCall.sum(:total_cost).to_f.round(4)})"

puts "\nThese are all test/demo data created during development."
puts "Would you like to clear them? (y/n)"

if ARGV[0] == '--force' || STDIN.gets.chomp.downcase == 'y'
  count = ApiCall.count
  ApiCall.destroy_all
  puts "\n✓ Cleared #{count} test API calls"
  puts "The tracking system will now only show real API calls going forward."
else
  puts "\n✓ Test data preserved"
  puts "You can run this script again with --force to clear without prompting"
end