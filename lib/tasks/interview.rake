# lib/tasks/interview.rake
namespace :interview do
  desc "Start an interactive interview session to prepare data for enliteration"
  task :start => :environment do
    puts "\n🎤 " + Rainbow("Welcome to Enliterator Interview!").bright.cyan
    puts "   I'll help you prepare your data for enliteration.\n\n"
    
    engine = Interview::Engine.new
    response = engine.start
    
    puts Rainbow(response).green
    puts "\n"
    
    # Interactive loop
    loop do
      print Rainbow("> ").yellow
      input = STDIN.gets.chomp
      
      break if input.match?(/^(exit|quit|bye)$/i)
      
      # Handle file paths
      context = {}
      if File.exist?(input)
        context[:files] = [input]
        puts Rainbow("📁 Processing file: #{input}").blue
      elsif Dir.exist?(input)
        context[:files] = Dir.glob(File.join(input, '**/*')).select { |f| File.file?(f) }
        puts Rainbow("📂 Processing directory: #{input} (#{context[:files].count} files)").blue
      end
      
      response = engine.process_input(input, context: context)
      
      puts "\n" + Rainbow(response).green
      puts "\n"
      
      # Check if complete
      if engine.state == :complete
        puts Rainbow("✨ Interview complete! Thank you for using Enliterator.").bright.green
        break
      end
    end
    
    # Save session before exiting
    if engine.state != :initial
      puts Rainbow("\n💾 Saving session...").blue
      session = engine.save_session
      puts Rainbow("Session saved: #{engine.session_id}").green
      puts Rainbow("Resume with: rails interview:resume[#{engine.session_id}]").cyan
    end
  end

  desc "Resume a previous interview session"
  task :resume, [:session_id] => :environment do |t, args|
    session_id = args[:session_id]
    
    unless session_id
      puts Rainbow("❌ Please provide a session ID").red
      puts "Usage: rails interview:resume[session_id]"
      exit 1
    end
    
    begin
      engine = Interview::Engine.resume(session_id)
      puts Rainbow("\n✅ Session resumed successfully!").green
      puts Rainbow("State: #{engine.state}").cyan
      
      # Show current status
      report = engine.validation_report
      puts "\n📊 Current Status:"
      puts "   Ready for pipeline: #{report[:ready] ? '✅' : '❌'}"
      puts "   Dataset items: #{engine.dataset.entity_count}"
      
      if report[:missing].any?
        puts "\n⚠️  Missing items:"
        report[:missing].each { |item| puts "   - #{item}" }
      end
      
      puts "\n" + Rainbow("Continue where you left off:").green
      puts "\n"
      
      # Resume interactive loop
      loop do
        print Rainbow("> ").yellow
        input = STDIN.gets.chomp
        
        break if input.match?(/^(exit|quit|bye)$/i)
        
        response = engine.process_input(input)
        puts "\n" + Rainbow(response).green
        puts "\n"
        
        if engine.state == :complete
          puts Rainbow("✨ Interview complete!").bright.green
          break
        end
      end
      
    rescue ActiveRecord::RecordNotFound
      puts Rainbow("❌ Session not found: #{session_id}").red
      puts "Available sessions:"
      
      InterviewSession.order(created_at: :desc).limit(5).each do |session|
        puts "  #{session.session_id} - #{session.created_at}"
      end
    end
  end

  desc "Use a template to structure your dataset"
  task :from_template, [:template_name] => :environment do |t, args|
    template = args[:template_name]
    
    unless template
      puts Rainbow("\n📚 Available templates:").cyan
      puts "  - event_data      : Events, festivals, gatherings"
      puts "  - organization    : Companies, communities, groups"
      puts "  - creative_works  : Art, media, literature"
      puts "  - knowledge_base  : Documentation, research, wikis"
      puts "\nUsage: rails interview:from_template[template_name]"
      exit
    end
    
    engine = Interview::Engine.new
    response = engine.start(template: template.to_sym)
    
    puts "\n" + Rainbow(response).green
    puts "\n"
    
    # Continue with interactive loop
    Rake::Task['interview:start'].invoke
  end

  desc "Validate an existing dataset for pipeline readiness"
  task :validate, [:path] => :environment do |t, args|
    path = args[:path]
    
    unless path && (File.exist?(path) || Dir.exist?(path))
      puts Rainbow("❌ Please provide a valid file or directory path").red
      exit 1
    end
    
    puts Rainbow("\n🔍 Validating dataset...").cyan
    
    engine = Interview::Engine.new
    
    if File.directory?(path)
      engine.add_data(source: path, type: :directory)
    else
      engine.add_data(source: path, type: :file)
    end
    
    report = engine.validation_report
    
    puts "\n📊 Validation Report:"
    puts "─" * 50
    
    # Overall status
    status = report[:ready] ? Rainbow("✅ READY").green : Rainbow("❌ NOT READY").red
    puts "Status: #{status}"
    
    # Detailed validations
    puts "\nValidations:"
    report[:validations].each do |key, validation|
      symbol = validation[:passed] ? "✅" : "❌"
      color = validation[:passed] ? :green : :red
      puts Rainbow("  #{symbol} #{key.to_s.humanize}: #{validation[:message]}").color(color)
    end
    
    # Missing items
    if report[:missing].any?
      puts Rainbow("\n⚠️  Missing items:").yellow
      report[:missing].each do |item|
        puts "  - #{item[:name]}: #{item[:description]}"
      end
    end
    
    # Suggestions
    if report[:suggestions].any?
      puts Rainbow("\n💡 Suggestions:").cyan
      report[:suggestions].each do |suggestion|
        puts "  - #{suggestion}"
      end
    end
    
    # Statistics
    stats = engine.dataset.statistics
    puts "\n📈 Dataset Statistics:"
    puts "  Entities: #{stats[:entity_count]}"
    puts "  Types: #{stats[:entity_types].join(', ')}"
    puts "  Temporal: #{stats[:temporal_range]}" if stats[:has_temporal]
    puts "  Spatial: #{stats[:spatial_coverage]}" if stats[:has_spatial]
    puts "  Descriptions: #{stats[:description_coverage]}" if stats[:has_descriptions]
    
    puts "\n" + Rainbow("─" * 50).cyan
    
    if report[:ready]
      puts Rainbow("✅ This dataset is ready for the Enliterator pipeline!").bright.green
      puts "Run: rails enliterator:ingest[#{path}]"
    else
      puts Rainbow("⚠️  This dataset needs additional preparation.").yellow
      puts "Run: rails interview:start"
    end
  end

  desc "List recent interview sessions"
  task :sessions => :environment do
    sessions = InterviewSession.order(created_at: :desc).limit(10)
    
    if sessions.empty?
      puts Rainbow("No interview sessions found.").yellow
      puts "Start a new session with: rails interview:start"
      exit
    end
    
    puts Rainbow("\n📚 Recent Interview Sessions:").cyan
    puts "─" * 60
    
    sessions.each do |session|
      data = session.data
      status = data[:state] == 'complete' ? Rainbow("✅").green : Rainbow("🔄").yellow
      
      puts "\n#{status} Session: #{session.session_id}"
      puts "   Created: #{session.created_at}"
      puts "   State: #{data[:state]}"
      puts "   Entities: #{data.dig(:dataset, :statistics, :entity_count) || 0}"
      puts "   Type: #{data.dig(:metadata, :dataset_type) || 'unknown'}"
      
      if data[:state] != 'complete'
        puts Rainbow("   Resume: rails interview:resume[#{session.session_id}]").cyan
      end
    end
    
    puts "\n" + Rainbow("─" * 60).cyan
  end

  desc "Generate a sample dataset for testing"
  task :sample, [:type] => :environment do |t, args|
    type = args[:type] || 'camps'
    
    puts Rainbow("\n🎲 Generating sample dataset: #{type}").cyan
    
    case type
    when 'camps'
      generate_sample_camps
    when 'events'
      generate_sample_events
    else
      puts Rainbow("Unknown sample type: #{type}").red
      puts "Available types: camps, events"
      exit 1
    end
  end
  
  private
  
  def generate_sample_camps
    require 'csv'
    
    path = Rails.root.join('tmp', 'sample_camps.csv')
    
    CSV.open(path, 'w') do |csv|
      csv << ['name', 'year', 'location', 'theme', 'description']
      
      camps = [
        ['Cosmic Dust', 2023, '7:30 & E', 'Space', 'A journey through the cosmos'],
        ['Time Portal', 2023, '3:00 & C', 'Time Travel', 'Experience past and future'],
        ['Desert Rose', 2023, '9:00 & G', 'Nature', 'An oasis in the dust'],
        ['Neon Dreams', 2022, '4:30 & H', 'Cyberpunk', 'The future is neon'],
        ['Dust Devils', 2022, '2:00 & D', 'Weather', 'Embrace the elements']
      ]
      
      camps.each { |camp| csv << camp }
    end
    
    puts Rainbow("✅ Sample dataset created: #{path}").green
    puts "\nTest with: rails interview:validate[#{path}]"
    puts "Or start interview: rails interview:start"
  end
  
  def generate_sample_events
    require 'json'
    
    path = Rails.root.join('tmp', 'sample_events.json')
    
    events = [
      {
        name: 'Sunrise Ceremony',
        date: '2023-08-28',
        location: 'Temple',
        type: 'ritual',
        description: 'Welcome the dawn together'
      },
      {
        name: 'Fire Conclave',
        date: '2023-09-02', 
        location: 'The Man',
        type: 'performance',
        description: 'Fire performers from around the world'
      }
    ]
    
    File.write(path, JSON.pretty_generate(events))
    
    puts Rainbow("✅ Sample dataset created: #{path}").green
    puts "\nTest with: rails interview:validate[#{path}]"
  end
end