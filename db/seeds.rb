# db/seeds.rb - Enliterator Comprehensive Seeds
# Idempotent seeding for essential data recovery

puts "🌱 ENLITERATOR COMPREHENSIVE SEEDS"
puts "=" * 60

# CRITICAL: Database Protection Check
existing_ekns = Ekn.joins(:ekn_pipeline_runs).where(ekn_pipeline_runs: { status: 'completed' }).count
if existing_ekns > 0
  puts "⚠️  DATABASE PROTECTION WARNING!"
  puts "   Found #{existing_ekns} completed EKN(s) with expensive OpenAI processing"
  puts "   Estimated recreation cost: $#{existing_ekns * 50}+ in OpenAI API calls"
  puts ""
  puts "   This seed is ADDITIVE and will NOT destroy existing data"
  puts "   Press ENTER to continue with safe operations only..."
  STDIN.gets
end

# SECTION 1: Admin User (Essential Recovery)
puts "\n👤 CREATING ADMIN USER"
admin_email = "j@zinod.com"
admin_password = "cheese28"

admin_user = User.find_or_create_by(email: admin_email) do |user|
  user.password = admin_password
  user.password_confirmation = admin_password
  user.name = "Jeremy Admin"  # Required field
  user.admin = true           # Boolean admin field
  puts "✅ Created admin user: #{admin_email}"
end

if admin_user.persisted? && !admin_user.previously_new_record?
  puts "✅ Admin user already exists: #{admin_email}"
end

# SECTION 2: Arctic Research EKN (Complete Knowledge Navigator)
puts "\n🌊 CREATING ARCTIC RESEARCH EKN"
arctic_ekn = Ekn.find_or_create_by(slug: "arctic-research") do |ekn|
  ekn.name = "Arctic Research Navigator"
  ekn.domain_type = "research"
  ekn.description = "An intelligent knowledge navigator for Arctic research, strategy, and geopolitics. Specializes in analyzing Arctic policies, security implications, resource development, climate impacts, and multi-national strategic approaches across the circumpolar north. Built from academic and governmental research covering US, Russian, Chinese, Canadian, and Nordic Arctic strategies."
  ekn.metadata = {
    "focus_areas" => [
      "Arctic geopolitics and strategy",
      "National security and defense in Arctic regions", 
      "Climate change impacts on Arctic territories",
      "Critical mineral and resource development",
      "Maritime and aviation infrastructure",
      "Multi-national Arctic cooperation and competition",
      "Indigenous communities and human security"
    ],
    "geographic_scope" => "Circumpolar Arctic (Alaska, Canada, Russia, Nordic countries, China)",
    "time_period" => "2010-2024",
    "document_types" => ["academic_papers", "government_reports", "congressional_testimonies", "strategic_assessments"],
    "languages" => ["English", "Russian"],
    "demo_purpose" => "Comprehensive Arctic research collection for strategic analysis",
    "target_audience" => "researchers, policy analysts, strategic planners"
  }
  puts "✅ Created Arctic Research EKN"
end

if arctic_ekn.persisted? && !arctic_ekn.previously_new_record?
  puts "✅ Arctic Research EKN already exists: #{arctic_ekn.name}"
end

# SECTION 3: Arctic Research Document Collection (FULL PDF DATASET)
puts "\n📄 CREATING COMPREHENSIVE ARCTIC RESEARCH BATCH"
batch = arctic_ekn.ingest_batches.find_or_create_by(name: "Arctic Research Documents Collection") do |b|
  b.source_type = "upload"
  b.status = "pending"
  b.metadata = {
    "source_directory" => Rails.root.join("arctic_research").to_s,
    "collection_description" => "Comprehensive Arctic research collection covering geopolitical strategies, security implications, climate impacts, and resource development across circumpolar nations",
    "geographic_focus" => "Circumpolar Arctic",
    "time_period" => "2010-2024",
    "nations_covered" => ["United States", "Russia", "China", "Canada", "Nordic countries"],
    "themes" => [
      "Arctic geopolitics and strategy",
      "National security and defense",
      "Climate change impacts", 
      "Critical mineral resources",
      "Transportation infrastructure",
      "International cooperation and competition"
    ]
  }
  puts "✅ Created Arctic research batch"
end

if batch.persisted? && !batch.previously_new_record?
  puts "✅ Arctic research batch already exists: #{batch.name}"
end

# SECTION 4: Add ALL Arctic PDF Documents
arctic_dir = Rails.root.join("arctic_research")
if Dir.exist?(arctic_dir)
  pdf_files = Dir.glob(arctic_dir.join("*.pdf"))
  puts "\n📑 PROCESSING #{pdf_files.length} ARCTIC PDF DOCUMENTS"
  
  added_count = 0
  existing_count = 0
  
  pdf_files.each_with_index do |file_path, index|
    filename = File.basename(file_path)
    
    item = batch.ingest_items.find_or_create_by(file_path: file_path.to_s) do |item|
      item.triage_status = "pending"
      item.media_type = "text"
      item.metadata = {
        "filename" => filename,
        "file_size" => File.size(file_path),
        "document_type" => case filename.downcase
                          when /congress/i, /hearing/i, /testimony/i then "congressional_document"
                          when /strategy/i then "strategic_document" 
                          when /arctic.*mineral/i, /resource/i then "resource_analysis"
                          when /climate/i, /chang/i then "climate_research"
                          when /security/i, /defense/i, /military/i then "security_analysis"
                          else "research_paper"
                          end
      }
      added_count += 1
    end
    
    if item.persisted? && !item.previously_new_record?
      existing_count += 1
    end
    
    status_icon = item.previously_new_record? ? "✅" : "↩️"
    puts "  #{index + 1}. #{filename} #{status_icon}"
  end
  
  puts "\nDocument Summary:"
  puts "  • Total Documents: #{pdf_files.length}"
  puts "  • Newly Added: #{added_count}"
  puts "  • Already Existed: #{existing_count}"
  puts "  • Batch Total Items: #{batch.ingest_items.count}"
  
else
  puts "⚠️ Arctic research directory not found: #{arctic_dir}"
  puts "   Please ensure PDF files are in: #{arctic_dir}"
end

# SECTION 5: Create Arctic Personality Profile
puts "\n🤖 ARCTIC RESEARCH NAVIGATOR PERSONALITY"
personality_profile = arctic_ekn.ekn_personality_profile

if personality_profile.nil?
  personality_profile = arctic_ekn.create_ekn_personality_profile!(
    base_archetype: "domain_specialist",
    
    domain_expertise: {
      "expertise_areas" => [
        "Arctic geopolitics and strategic competition",
        "Climate change impacts on Arctic security",
        "Critical mineral resources and supply chains", 
        "Multi-national Arctic policies and cooperation",
        "Military strategies and defense considerations",
        "Environmental protection and sustainable development",
        "Indigenous rights and traditional knowledge",
        "Economic development and resource extraction"
      ],
      "analytical_approach" => "comprehensive_strategic_analysis",
      "perspective" => "multi_national_balanced",
      "expertise_level" => "senior_policy_analyst"
    },
    
    mcp_tool_preferences: {
      "search" => 0.9,
      "fetch" => 0.8,
      "bridge" => 0.7,
      "extract_and_link" => 0.6
    },
    
    communication_signature: {
      "greeting" => "Welcome to the Arctic Research Navigator. I'm here to provide strategic analysis and insights on Arctic geopolitics, security, and development issues.",
      "response_format" => "structured_analysis",
      "tone" => "expert_professional",
      "detail_level" => "domain_deep"
    }
  )
  puts "✅ Created Arctic personality profile"
else
  puts "✅ Arctic personality profile already exists"
end

# SECTION 6: OpenAI Settings and Prompt Templates (CRITICAL CONFIGURATION)
puts "\n⚙️ CREATING OPENAI SETTINGS & PROMPT TEMPLATES"
puts "Loading critical OpenAI configuration that was lost in database wipe..."

# Load the OpenAI settings seed file
load Rails.root.join('db', 'seeds', 'openai_settings.rb')

puts "✅ OpenAI settings and prompt templates restored"

# SECTION 7: Output Status Summary
puts "\n" + "=" * 60
puts "🎯 ENLITERATOR SEEDS COMPLETED"
puts "=" * 60

puts "\n📊 SEED SUMMARY:"
puts "  Admin User: #{User.find_by(email: admin_email) ? '✅ Ready' : '❌ Failed'}"
puts "  Arctic EKN: #{arctic_ekn.persisted? ? '✅ Ready' : '❌ Failed'}"
puts "  Research Batch: #{batch.persisted? ? '✅ Ready' : '❌ Failed'}"
puts "  PDF Documents: #{batch.ingest_items.count} items"
puts "  Personality Profile: #{arctic_ekn.ekn_personality_profile ? '✅ Ready' : '❌ Failed'}"
puts "  OpenAI Settings: #{OpenaiSetting.count} settings"
puts "  Prompt Templates: #{PromptTemplate.count} templates"
puts "  Neo4j Database: #{arctic_ekn.neo4j_database_name}"

puts "\n🚀 NEXT STEPS:"
puts "1. Run pipeline: rails enliterator:seed:process_arctic"
puts "2. Check status: rails runner 'puts Ekn.find_by(slug: \"arctic-research\")&.status'"
puts "3. Access chat: https://e.dev.domt.app/arctic-research/chat"

puts "\n💡 RECOVERY COMMANDS:"
puts "• Full reset: rails enliterator:seed:reset_arctic"
puts "• Status check: rails enliterator:seed:status"
puts "• Process only: rails enliterator:seed:process_arctic"

puts "\nSeeds completed successfully! 🌱"