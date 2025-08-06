#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

r = ProvenanceAndRights.find(3)
puts "Current license: #{r.license_type}"
puts "Current training_eligibility: #{r.training_eligibility}"
puts "Current custom_terms: #{r.custom_terms.inspect}"

# Update to ensure training eligibility
r.custom_terms['allow_training'] = true
r.save!
r.reload

puts "\nAfter update:"
puts "Training eligible: #{r.training_eligibility}"
puts "Publishability: #{r.publishability}"

# Verify all items have training-eligible rights
batch = IngestBatch.find(7)
eligible_count = batch.ingest_items.joins(:provenance_and_rights)
                      .where(provenance_and_rights: { training_eligibility: true })
                      .count

puts "\nItems with training-eligible rights: #{eligible_count} / #{batch.ingest_items.count}"