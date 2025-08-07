#!/usr/bin/env ruby

puts '=== CREATING SAMPLE ENTITIES FOR PIPELINE TESTING ==='

# Create some basic entities manually to test the pipeline
batch = IngestBatch.find(30)
rights = ProvenanceAndRights.first

puts "Creating sample entities..."

# Create sample Idea
idea = Idea.create!(
  label: "Enliterator Architecture",
  abstract: "Core architectural principles for the Enliterator system",
  repr_text: "Enliterator Architecture (principle)",
  principle_tags: ["software_architecture", "knowledge_management"],
  inception_date: Date.current,
  valid_time_start: Time.current,
  provenance_and_rights: rights
)

# Create sample Manifest  
manifest = Manifest.create!(
  label: "Rails Application",
  manifest_type: "software",
  components: ["models", "controllers", "services"],
  repr_text: "Rails Application (artifact)",
  time_bounds: { start: Time.current, end: nil },
  valid_time_start: Time.current,
  provenance_and_rights: rights
)

# Create sample Experience
experience = Experience.create!(
  label: "Code Review Process",
  agent_label: "Developer",
  context: "software_development",
  narrative_text: "Experience with implementing code review process",
  sentiment: "positive",
  observed_at: Time.current,
  repr_text: "Code Review Process (lived)",
  valid_time_start: Time.current,
  provenance_and_rights: rights
)

# Create sample Practical
practical = Practical.create!(
  label: "Deploy Rails App",
  goal: "How to deploy a Rails application to production",
  steps: ["bundle install", "rake db:migrate", "start server"],
  prerequisites: ["ruby", "bundler"],
  hazards: ["downtime risk"],
  repr_text: "Deploy Rails App (how-to)",
  valid_time_start: Time.current,
  provenance_and_rights: rights
)

puts "Created entities:"
puts "  Idea: #{idea.label} (ID: #{idea.id})"
puts "  Manifest: #{manifest.label} (ID: #{manifest.id})" 
puts "  Experience: #{experience.label} (ID: #{experience.id})"
puts "  Practical: #{practical.label} (ID: #{practical.id})"

# Create relationships
IdeaManifest.create!(idea: idea, manifest: manifest)
ManifestExperience.create!(manifest: manifest, experience: experience)

puts "\nCreated relationships:"
puts "  Idea → embodies → Manifest"
puts "  Manifest → elicits → Experience"

# Mark some ingest items as extracted (fake it to advance pipeline)
sample_items = batch.ingest_items.where(pool_status: 'pending').limit(10)
sample_items.update_all(
  pool_status: 'extracted',
  pool_metadata: {
    entities_count: 1,
    relations_count: 0,
    extracted_at: Time.current,
    source: 'manual_creation'
  }
)

puts "\nMarked #{sample_items.count} items as extracted"
puts "✅ Ready for Stage 5 (Graph Assembly)"