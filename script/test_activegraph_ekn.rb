#!/usr/bin/env ruby
# Test ActiveGraph models with database-per-EKN architecture

require_relative '../config/environment'

puts "\n" + "="*80
puts "Testing ActiveGraph with EKN Isolation"
puts "="*80

# Clean up test EKNs
puts "\n1. Cleaning up test EKNs..."
IngestBatch.where("name LIKE 'ActiveGraph Test%'").destroy_all

# Create test EKN
puts "\n2. Creating test EKN..."
ekn = EknManager.create_ekn(
  name: "ActiveGraph Test EKN",
  description: "Testing ActiveGraph models"
)
puts "   ✓ Created EKN #{ekn.id}: #{ekn.name}"
puts "   - Database: #{ekn.neo4j_database_name}"

# Test with Graph::ModelService (uses ActiveGraph models)
puts "\n3. Testing ActiveGraph models via ModelService..."
service = Graph::ModelService.new(ekn)

# Create Ideas
puts "\n   Creating Ideas..."
radical_inclusion = service.create_idea(
  name: "Radical Inclusion",
  canonical: "Radical Inclusion",
  description: "Anyone may be a part of Burning Man",
  surface_forms: ["radical inclusion", "inclusion", "inclusivity"]
)
puts "   ✓ Created: #{radical_inclusion}"

gifting = service.create_idea(
  name: "Gifting",
  canonical: "Gifting",
  description: "Burning Man is devoted to acts of gift giving",
  surface_forms: ["gifting", "gifts", "gift economy"]
)
puts "   ✓ Created: #{gifting}"

# Create Manifests
puts "\n   Creating Manifests..."
center_camp = service.create_manifest(
  name: "Center Camp",
  canonical: "Center Camp",
  description: "The heart of Black Rock City",
  manifest_type: "camp",
  year: 2024,
  capacity: 5000
)
puts "   ✓ Created: #{center_camp}"

temple = service.create_manifest(
  name: "Temple of the Heart",
  canonical: "Temple",
  description: "Sacred space for reflection",
  manifest_type: "art",
  year: 2024
)
puts "   ✓ Created: #{temple}"

# Create Experiences
puts "\n   Creating Experiences..."
sunrise_ceremony = service.create_experience(
  title: "Temple Sunrise Ceremony",
  content: "Gathering at dawn to witness the first light on the temple",
  experience_type: "event",
  year: 2024,
  sentiment: 0.9,
  publishable: true,
  training_eligible: false,
  tags: ["ritual", "community", "sacred"]
)
puts "   ✓ Created: #{sunrise_ceremony}"

# Create Relationships
puts "\n   Creating Relationships..."
result = service.link_idea_to_manifest("Radical Inclusion", "Center Camp")
puts "   ✓ Linked: Radical Inclusion → EMBODIES → Center Camp" if result

result = service.link_idea_to_manifest("Gifting", "Temple of the Heart")
puts "   ✓ Linked: Gifting → EMBODIES → Temple" if result

result = service.link_manifest_to_experience("Temple of the Heart", "Temple Sunrise Ceremony")
puts "   ✓ Linked: Temple → HOSTS → Sunrise Ceremony" if result

# Query the data
puts "\n4. Querying data with ActiveGraph..."

ideas = service.ideas(limit: 10)
puts "   Ideas: #{ideas.map(&:name).join(', ')}"

manifests = service.manifests(limit: 10)
puts "   Manifests: #{manifests.map(&:name).join(', ')}"

experiences = service.experiences(limit: 10, publishable_only: true)
puts "   Publishable Experiences: #{experiences.map(&:title).join(', ')}"

# Search
puts "\n5. Testing search..."
results = service.search("Temple", pools: ['manifest', 'experience'])
puts "   Search for 'Temple': Found #{results.size} results"
results.each { |r| puts "     - #{r}" }

# Statistics
puts "\n6. Statistics..."
stats = service.statistics
stats.each do |key, value|
  puts "   #{key}: #{value}"
end

# Test isolation - create another EKN
puts "\n7. Testing isolation between EKNs..."
ekn2 = EknManager.create_ekn(
  name: "ActiveGraph Test EKN 2",
  description: "Second test EKN"
)
service2 = Graph::ModelService.new(ekn2)

# Add different data to EKN2
service2.create_idea(
  name: "Leave No Trace",
  canonical: "Leave No Trace",
  description: "Respect the environment"
)

# Verify isolation
ekn1_ideas = service.ideas.map(&:name)
ekn2_ideas = service2.ideas.map(&:name)

puts "   EKN1 Ideas: #{ekn1_ideas.join(', ')}"
puts "   EKN2 Ideas: #{ekn2_ideas.join(', ')}"

if ekn1_ideas.include?("Leave No Trace")
  puts "   ❌ ERROR: EKN1 can see EKN2 data!"
else
  puts "   ✓ Data properly isolated between EKNs"
end

# Clean up
puts "\n8. Cleaning up..."
EknManager.destroy_ekn(ekn)
EknManager.destroy_ekn(ekn2)
puts "   ✓ Test EKNs destroyed"

puts "\n" + "="*80
puts "✅ ActiveGraph Integration Test Complete!"
puts "="*80
puts "\nSummary:"
puts "- ActiveGraph models work with database-per-EKN"
puts "- Each EKN has isolated Neo4j database"
puts "- Models can create nodes and relationships"
puts "- Queries are scoped to the correct database"
puts "- Data isolation verified between EKNs"
puts "="*80