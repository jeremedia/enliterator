#!/usr/bin/env ruby

puts "🚨 CRITICAL DATABASE INVESTIGATION"
puts "=" * 50

# Check critical models that should exist
models_to_check = [
  'PromptTemplate',
  'OpenaiSetting', 
  'ApiCall',
  'Message',
  'Conversation',
  'User',
  'Ekn',
  'IngestBatch',
  'IngestItem',
  'LexiconAndOntology',
  'ProvenanceAndRights'
]

puts "MISSING/PRESENT MODELS:"
models_to_check.each do |model_name|
  begin
    model_class = model_name.constantize
    count = model_class.count
    puts "✅ #{model_name}: #{count} records"
  rescue NameError => e
    puts "❌ #{model_name}: MODEL MISSING - #{e.message}"
  rescue => e
    puts "⚠️  #{model_name}: ERROR - #{e.class}: #{e.message}"
  end
end

puts "\nDATABASE TABLES:"
begin
  tables = ActiveRecord::Base.connection.tables.sort
  puts "Total tables: #{tables.count}"
  puts "All tables: #{tables.join(', ')}"
rescue => e
  puts "❌ Cannot access database tables: #{e.message}"
end

puts "\nSCHEMA VERSION:"
begin
  version = ActiveRecord::Base.connection.schema_version
  puts "Schema version: #{version}"
rescue => e
  puts "❌ Cannot get schema version: #{e.message}"
end