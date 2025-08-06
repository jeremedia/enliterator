# lib/tasks/meta_enliteration.rake
# Tasks for meta-enliteration: creating the Enliterator Knowledge Navigator

namespace :meta_enliteration do
  desc "Create a self-referential bundle of the Enliterator codebase"
  task :create_bundle => :environment do
    puts Rainbow("\n🔄 META-ENLITERATION: Creating Self-Bundle").bright.cyan
    puts Rainbow("=" * 60).cyan
    
    creator = MetaEnliteration::BundleCreator.new
    result = creator.call
    
    if result[:success]
      puts Rainbow("\n✅ Bundle created successfully!").green
      puts "\n📦 Bundle Details:"
      puts "   Path: #{result[:bundle_path]}"
      puts "   Size: #{result[:stats][:size_human]}"
      puts "   Files: #{result[:stats][:total_files]}"
      
      if result[:stats][:categories]
        puts "\n📊 Content Breakdown:"
        puts "   Code files: #{result[:stats][:categories][:code_files]}"
        puts "   Documentation: #{result[:stats][:categories][:doc_files]}"
        puts "   Tests: #{result[:stats][:categories][:test_files]}"
        puts "   Operational: #{result[:stats][:categories][:operational_files]}"
      end
      
      puts Rainbow("\n🎯 Expected Outcomes:").yellow
      puts "   Enliteracy Score: #{result[:manifest][:expected_enliteracy_score]}"
      puts "   Target Maturity: #{result[:manifest][:target_maturity]}"
      
      puts Rainbow("\n🚀 Next Step:").cyan
      puts "   Run: rails meta_enliteration:process_bundle"
      puts "   Or manually: rails enliterator:ingest[#{result[:bundle_path]}]"
    else
      puts Rainbow("\n❌ Bundle creation failed!").red
      puts "Error: #{result[:error]}"
      puts "\nBacktrace:" if ENV['DEBUG']
      puts result[:backtrace].first(10).join("\n") if ENV['DEBUG'] && result[:backtrace]
    end
  end
  
  desc "Process the self-bundle through the pipeline"
  task :process_bundle => :environment do
    puts Rainbow("\n🔄 Processing Self-Bundle Through Pipeline").bright.cyan
    puts Rainbow("=" * 60).cyan
    
    # Find the most recent self-bundle
    bundle_pattern = Rails.root.join('tmp', 'bundles', 'enliterator_self_*.zip')
    bundles = Dir.glob(bundle_pattern).sort_by { |f| File.mtime(f) }
    
    if bundles.empty?
      puts Rainbow("❌ No self-bundle found!").red
      puts "Run: rails meta_enliteration:create_bundle"
      exit 1
    end
    
    bundle_path = bundles.last
    puts "📦 Using bundle: #{File.basename(bundle_path)}"
    
    # Create ingest batch
    batch = IngestBatch.create!(
      name: "meta_enliteration_#{Time.current.strftime('%Y%m%d')}",
      source_type: 'zip_bundle',
      metadata: {
        type: 'meta_enliteration',
        purpose: 'Create Enliterator Knowledge Navigator',
        source_path: bundle_path
      }
    )
    
    puts "\n📥 Created batch: #{batch.name} (ID: #{batch.id})"
    
    # Run through pipeline stages
    stages = [
      { name: "Stage 1: Intake", task: "enliterator:ingest", args: [batch.metadata['source_path']] },
      { name: "Stage 2: Graph Assembly", task: "enliterator:graph:sync", args: [batch.id] },
      { name: "Stage 3: Embeddings", task: "enliterator:embed:generate", args: [batch.id] },
      { name: "Stage 4: Literacy Scoring", task: "enliterator:literacy:score", args: [batch.id] },
      { name: "Stage 5: Deliverables", task: "enliterator:deliverables:generate", args: [batch.id] }
    ]
    
    stages.each_with_index do |stage, index|
      puts Rainbow("\n▶️  #{stage[:name]}").yellow
      
      begin
        # Invoke the rake task with appropriate arguments
        if stage[:args]
          Rake::Task[stage[:task]].invoke(*stage[:args])
        else
          Rake::Task[stage[:task]].invoke
        end
        puts Rainbow("   ✅ Complete").green
      rescue => e
        puts Rainbow("   ❌ Failed: #{e.message}").red
        puts Rainbow("\n⚠️  Pipeline stopped at #{stage[:name]}").yellow
        
        # Don't exit - let's continue with other stages to see what works
        puts Rainbow("   ⏭️  Continuing with next stage...").yellow
      end
    end
    
    puts Rainbow("\n🎉 Meta-Enliteration Complete!").bright.green
    puts "\n📊 Results:"
    puts "   Batch ID: #{batch.id}"
    puts "   Status: #{batch.status}"
    
    # Check literacy score
    if batch.literacy_score
      puts "   Enliteracy Score: #{batch.literacy_score}"
      
      if batch.literacy_score >= 70
        puts Rainbow("   ✅ Ready for Knowledge Navigator creation!").green
      else
        puts Rainbow("   ⚠️  Score below threshold (70)").yellow
      end
    end
    
    puts Rainbow("\n🚀 Next Steps:").cyan
    puts "1. Generate training data: rails meta_enliteration:generate_training_data[#{batch.id}]"
    puts "2. Fine-tune model: rails meta_enliteration:create_ekn[#{batch.id}]"
  end
  
  desc "Generate training data from the enliterated knowledge graph"
  task :generate_training_data, [:batch_id] => :environment do |t, args|
    batch_id = args[:batch_id]
    
    unless batch_id
      puts Rainbow("❌ Please provide a batch ID").red
      puts "Usage: rails meta_enliteration:generate_training_data[batch_id]"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    puts Rainbow("\n📚 Generating Training Data from Batch: #{batch.name}").bright.cyan
    puts Rainbow("=" * 60).cyan
    
    extractor = MetaEnliteration::TrainingDataExtractor.new(batch)
    result = extractor.call
    
    if result[:success]
      puts Rainbow("\n✅ Training data generated!").green
      puts "\n📊 Statistics:"
      puts "   Conversations: #{result[:conversation_count]}"
      puts "   Total messages: #{result[:message_count]}"
      puts "   File path: #{result[:output_path]}"
      puts "   File size: #{result[:file_size]}"
      
      puts Rainbow("\n🎯 Coverage:").yellow
      result[:coverage].each do |pool, count|
        puts "   #{pool.capitalize}: #{count} examples"
      end
      
      puts Rainbow("\n🚀 Next Step:").cyan
      puts "   Fine-tune model: rails meta_enliteration:create_ekn[#{batch.id}]"
    else
      puts Rainbow("\n❌ Training data generation failed!").red
      puts "Error: #{result[:error]}"
    end
  end
  
  desc "Create the Enliterated Knowledge Navigator through fine-tuning"
  task :create_ekn, [:batch_id] => :environment do |t, args|
    batch_id = args[:batch_id]
    
    unless batch_id
      puts Rainbow("❌ Please provide a batch ID").red
      puts "Usage: rails meta_enliteration:create_ekn[batch_id]"
      exit 1
    end
    
    batch = IngestBatch.find(batch_id)
    puts Rainbow("\n🧠 Creating Enliterated Knowledge Navigator").bright.cyan
    puts Rainbow("=" * 60).cyan
    
    deployer = MetaEnliteration::EKNDeployer.new(batch)
    result = deployer.call
    
    if result[:success]
      puts Rainbow("\n✅ EKN Created Successfully!").bright.green
      puts "\n🤖 Model Details:"
      puts "   Model ID: #{result[:model_id]}"
      puts "   Base Model: #{result[:base_model]}"
      puts "   Training Status: #{result[:status]}"
      
      puts Rainbow("\n🧪 Test the EKN:").yellow
      puts "   rails meta_enliteration:test_ekn"
      
      puts Rainbow("\n🚀 Use the EKN:").cyan
      puts "   rails console"
      puts "   conversation = Conversation.create(model_name: '#{result[:model_id]}')"
      puts "   engine = Literate::Engine.new(conversation)"
      puts "   response = engine.process('What is enliteration?')"
    else
      puts Rainbow("\n❌ EKN creation failed!").red
      puts "Error: #{result[:error]}"
    end
  end
  
  desc "Test the Enliterated Knowledge Navigator"
  task :test_ekn => :environment do
    puts Rainbow("\n🧪 Testing Enliterated Knowledge Navigator").bright.cyan
    puts Rainbow("=" * 60).cyan
    
    # Find the fine-tuned model
    model_name = ENV['EKN_MODEL'] || 'ft:gpt-4o-mini:enliterator-ekn-v1'
    
    # Create conversation with the EKN model
    conversation = Conversation.create!(
      model_name: model_name,
      context: {
        domain_context: 'enliterator_system',
        current_dataset: 'self_knowledge'
      }
    )
    
    engine = Literate::Engine.new(conversation)
    
    # Test questions
    test_questions = [
      "What is enliteration?",
      "How do I start the pipeline?",
      "What are the Ten Pools?",
      "My literacy score is 65, what should I do?",
      "How do I create a Knowledge Navigator?"
    ]
    
    puts "\n" + Rainbow("Testing with #{test_questions.count} questions:").yellow
    puts Rainbow("-" * 40).cyan
    
    test_questions.each_with_index do |question, index|
      puts "\n#{Rainbow("Q#{index + 1}:").yellow} #{question}"
      
      response = engine.process(question)
      
      # Truncate response for display
      display_response = response.length > 200 ? response[0..197] + "..." : response
      puts "#{Rainbow("A:").green} #{display_response}"
      
      # Basic validation
      if response.length > 10 && !response.include?("error")
        puts Rainbow("   ✅ Response generated").green
      else
        puts Rainbow("   ⚠️  Response may have issues").yellow
      end
    end
    
    puts "\n" + Rainbow("-" * 40).cyan
    puts Rainbow("\n✅ EKN Testing Complete!").bright.green
    puts "\nConversation ID: #{conversation.id}"
    puts "View full responses: rails console -> Conversation.find(#{conversation.id}).messages"
  end
  
  desc "Full meta-enliteration pipeline (all steps)"
  task :full_pipeline => :environment do
    puts Rainbow("\n🔄 FULL META-ENLITERATION PIPELINE").bright.cyan.underline
    puts Rainbow("=" * 60).cyan
    puts "\nThis will:"
    puts "1. Create self-bundle"
    puts "2. Process through pipeline"
    puts "3. Generate training data"
    puts "4. Create EKN"
    puts "5. Test the navigator"
    
    print "\n#{Rainbow('Continue? (y/n): ').yellow}"
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y'
      puts Rainbow("Cancelled").red
      exit
    end
    
    # Execute all steps
    Rake::Task['meta_enliteration:create_bundle'].invoke
    Rake::Task['meta_enliteration:process_bundle'].invoke
    
    # Get the batch ID from the most recent meta-enliteration
    batch = IngestBatch.where("metadata->>'type' = ?", 'meta_enliteration')
                      .order(created_at: :desc)
                      .first
    
    if batch
      Rake::Task['meta_enliteration:generate_training_data'].invoke(batch.id)
      Rake::Task['meta_enliteration:create_ekn'].invoke(batch.id)
      Rake::Task['meta_enliteration:test_ekn'].invoke
      
      puts Rainbow("\n🎉 META-ENLITERATION COMPLETE!").bright.green.underline
      puts "\nThe Enliterator now understands itself."
      puts "The first Enliterated Knowledge Navigator has been born."
    else
      puts Rainbow("\n❌ Could not find processed batch").red
    end
  end
end