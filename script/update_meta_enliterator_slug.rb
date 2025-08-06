#!/usr/bin/env ruby

ekn = Ekn.find_by(id: 13)

if ekn
  puts "Found EKN #13: #{ekn.name}"
  ekn.update!(slug: 'meta-enliterator')
  puts "Updated with slug: meta-enliterator"
  
  # Verify it works
  test_by_slug = Ekn.find('meta-enliterator')
  test_by_id = Ekn.find(13)
  
  puts "\nVerification:"
  puts "  Find by slug 'meta-enliterator': #{test_by_slug.name} (ID: #{test_by_slug.id})"
  puts "  Find by ID 13: #{test_by_id.name} (slug: #{test_by_id.slug})"
else
  puts "EKN #13 not found"
end