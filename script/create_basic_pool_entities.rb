#!/usr/bin/env ruby
# Create basic pool entities for meta-enliteration to unblock pipeline

batch = IngestBatch.find(4)

# Create some basic entities representing the Enliterator system
puts "Creating basic pool entities for meta-enliteration..."

# Find a provenance record to attach to entities
rights_record = batch.ingest_items.first.provenance_and_rights

if rights_record
  # Idea entities - core concepts of the system
  idea1 = Idea.create!(
    label: "Enliteration",
    abstract: "The process that makes a dataset literate by modeling it into pools of meaning and explicit flows",
    inception_date: Date.current,
    repr_text: "Enliteration: The process that makes a dataset literate by modeling it into pools of meaning and explicit flows",
    valid_time_start: Time.current,
    provenance_and_rights: rights_record
  )
  
  idea2 = Idea.create!(
    label: "Knowledge Graph",
    abstract: "Neo4j-based graph database storing relationships between pool entities",
    inception_date: Date.current,
    repr_text: "Knowledge Graph: Neo4j-based graph database storing relationships between pool entities",
    valid_time_start: Time.current,
    provenance_and_rights: rights_record
  )
  
  # Manifest entities - concrete implementations
  manifest1 = Manifest.create!(
    label: "Rails Application",
    manifest_type: "software",
    repr_text: "Rails Application: Rails 8 application implementing the enliteration pipeline",
    valid_time_start: Time.current,
    provenance_and_rights: rights_record
  )
  
  manifest2 = Manifest.create!(
    label: "Pipeline Stages",
    manifest_type: "process",
    repr_text: "Pipeline Stages: Eight-stage zero-touch enliteration pipeline",
    valid_time_start: Time.current,
    provenance_and_rights: rights_record
  )
  
  # Experience entities - outcomes and interactions
  experience1 = Experience.create!(
    agent_label: "Meta-enliteration Process",
    context: "Self-referential processing of Enliterator codebase to create EKN",
    narrative_text: "Processing the Enliterator codebase through its own pipeline to create knowledge navigator",
    observed_at: Time.current,
    repr_text: "Meta-enliteration Process: Self-referential processing of Enliterator codebase to create EKN",
    provenance_and_rights: rights_record
  )
  
  # Practical entities - actionable implementations
  practical1 = Practical.create!(
    goal: "EKN Creation",
    steps: ["Extract knowledge graph", "Generate training data", "Fine-tune model", "Deploy navigator"],
    repr_text: "EKN Creation: Fine-tuning process to create Enliterator Knowledge Navigator",
    valid_time_start: Time.current,
    provenance_and_rights: rights_record
  )

  puts "Created entities:"
  puts "  Ideas: #{Idea.count}"
  puts "  Manifests: #{Manifest.count}"
  puts "  Experiences: #{Experience.count}"
  puts "  Practicals: #{Practical.count}"
  puts "  Total pool entities: #{Idea.count + Manifest.count + Experience.count + Practical.count}"

else
  puts "ERROR: No provenance/rights record found. Cannot create entities."
end