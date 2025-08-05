# app/services/interview/engine.rb
module Interview
  class Engine
    attr_reader :session_id, :state, :dataset, :metadata, :validations

    STATES = %i[
      initial
      discovery
      assessment
      rights_collection
      gap_identification
      structuring
      preparation
      complete
    ].freeze

    def initialize(session_id: nil)
      @session_id = session_id || SecureRandom.uuid
      @state = :initial
      @dataset = DatasetBuilder.new
      @metadata = {}
      @validations = {}
      @conversation_history = []
    end

    def start(domain: nil, template: nil)
      @metadata[:domain] = domain
      @metadata[:template] = template
      @metadata[:started_at] = Time.current
      
      transition_to(:discovery)
      
      if template
        load_template(template)
        "I'll guide you through creating a #{template.humanize} dataset. #{template_intro}"
      else
        discovery_prompt
      end
    end

    def process_input(input, context: {})
      @conversation_history << { role: :user, content: input, timestamp: Time.current }
      
      response = case @state
      when :discovery
        handle_discovery(input, context)
      when :assessment
        handle_assessment(input, context)
      when :rights_collection
        handle_rights(input, context)
      when :gap_identification
        handle_gaps(input, context)
      when :structuring
        handle_structuring(input, context)
      when :preparation
        handle_preparation(input, context)
      else
        "Interview complete. Use `prepare_bundle` to export."
      end
      
      @conversation_history << { role: :assistant, content: response, timestamp: Time.current }
      response
    end

    def add_data(source:, type: :file)
      case type
      when :file
        @dataset.add_file(source)
      when :directory
        @dataset.add_directory(source)
      when :url
        @dataset.add_url(source)
      when :text
        @dataset.add_text(source)
      when :api
        @dataset.add_api(source)
      else
        raise ArgumentError, "Unknown source type: #{type}"
      end
      
      analyze_current_data
    end

    def set_rights(license:, source: nil, training_eligible: nil, publishable: nil)
      @metadata[:rights] = {
        license: license,
        source: source,
        training_eligible: training_eligible,
        publishable: publishable,
        captured_at: Time.current
      }
      
      validate_rights
    end

    def prepare_bundle
      raise "Dataset not ready" unless ready_for_pipeline?
      
      Bundle::Packager.new(
        dataset: @dataset,
        metadata: @metadata,
        session_id: @session_id
      ).package
    end

    def ready_for_pipeline?
      validate_all unless @validations[:completeness]
      
      @validations[:completeness]&.fetch(:passed, false) &&
        @validations[:rights]&.fetch(:passed, false) &&
        @validations[:structure]&.fetch(:passed, false)
    end

    def validation_report
      {
        ready: ready_for_pipeline?,
        validations: validations,
        missing: identify_gaps,
        suggestions: generate_suggestions
      }
    end

    def save_session
      session_data = {
        session_id: @session_id,
        state: @state,
        dataset: @dataset.to_h,
        metadata: @metadata,
        validations: @validations,
        conversation_history: @conversation_history,
        saved_at: Time.current
      }
      
      InterviewSession.create!(
        session_id: @session_id,
        data: session_data
      )
    end

    def self.resume(session_id)
      session = InterviewSession.find_by!(session_id: session_id)
      engine = new(session_id: session_id)
      engine.restore_from(session.data)
      engine
    end

    def restore_from(data)
      @state = data[:state].to_sym
      @dataset = DatasetBuilder.from_hash(data[:dataset])
      @metadata = data[:metadata]
      @validations = data[:validations]
      @conversation_history = data[:conversation_history]
    end

    private

    def transition_to(new_state)
      raise "Invalid state: #{new_state}" unless STATES.include?(new_state)
      @state = new_state
    end

    def discovery_prompt
      <<~PROMPT
        Welcome to Enliterator Interview! I'll help you prepare your data for enliteration.
        
        What type of knowledge would you like to work with?
        1. Event or festival data
        2. Organizational knowledge  
        3. Creative works collection
        4. Research documentation
        5. Something else
        
        You can type a number or describe your dataset.
      PROMPT
    end

    def handle_discovery(input, context)
      # Detect dataset type from input
      dataset_type = detect_dataset_type(input)
      @metadata[:dataset_type] = dataset_type
      
      transition_to(:assessment)
      
      <<~RESPONSE
        #{dataset_type_acknowledgment(dataset_type)}
        
        What data do you currently have? You can:
        - Share file paths or drop files here
        - Provide a directory path
        - Describe what you have
        - Paste a sample
      RESPONSE
    end

    def handle_assessment(input, context)
      # Process data sources
      if context[:files].present?
        context[:files].each { |f| add_data(source: f, type: :file) }
      elsif input.match?(/^\/.*/)  # Path provided
        add_data(source: input.strip, type: detect_path_type(input))
      else
        @metadata[:data_description] = input
      end
      
      analysis = analyze_current_data
      
      if analysis[:sufficient_data]
        transition_to(:rights_collection)
        rights_collection_prompt(analysis)
      else
        request_more_data(analysis)
      end
    end

    def handle_rights(input, context)
      # Parse rights information
      rights_info = parse_rights_input(input)
      set_rights(**rights_info)
      
      if validations[:rights][:passed]
        transition_to(:gap_identification)
        gap_identification_prompt
      else
        clarify_rights(validations[:rights][:issues])
      end
    end

    def handle_gaps(input, context)
      if input.match?(/^(yes|y|add)/i)
        structuring_prompt_for_gaps
      elsif input.match?(/^(no|n|skip)/i)
        transition_to(:preparation)
        preparation_prompt
      else
        # Handle additional data for gaps
        process_gap_data(input, context)
      end
    end

    def handle_structuring(input, context)
      # Guide through structuring decisions
      structuring_result = process_structuring_input(input)
      
      if structuring_result[:complete]
        transition_to(:preparation)
        preparation_prompt
      else
        next_structuring_question(structuring_result)
      end
    end

    def handle_preparation(input, context)
      if input.match?(/^(yes|y|prepare)/i)
        bundle = prepare_bundle
        transition_to(:complete)
        completion_message(bundle)
      else
        "What would you like to adjust before preparing the bundle?"
      end
    end

    def analyze_current_data
      Analyzers::DatasetAnalyzer.new(@dataset).analyze
    end

    def validate_rights
      @validations[:rights] = Validators::Rights.new(@metadata[:rights]).validate
    end
    
    def validate_all
      @validations[:completeness] = Validators::Completeness.new(@dataset, @metadata).validate
      @validations[:rights] = Validators::Rights.new(@metadata[:rights]).validate
      @validations[:structure] = Validators::Structure.new(@dataset).validate
    end

    def identify_gaps
      Analyzers::GapDetector.new(@dataset, @metadata).detect
    end

    def generate_suggestions
      Analyzers::Suggester.new(@dataset, @metadata).suggest
    end

    def detect_dataset_type(input)
      case input
      when /^1|event|festival/i
        :event_data
      when /^2|org|organization/i
        :organization
      when /^3|creative|art|works/i
        :creative_works
      when /^4|research|documentation/i
        :knowledge_base
      else
        :general
      end
    end

    def dataset_type_acknowledgment(type)
      case type
      when :event_data
        "🎪 Great choice! Event data often contains rich temporal and spatial patterns."
      when :organization
        "🏢 Excellent! Organizational knowledge can reveal fascinating evolution and relationships."
      when :creative_works
        "🎨 Wonderful! Creative collections offer unique opportunities for thematic analysis."
      when :knowledge_base
        "📚 Perfect! Documentation can be transformed into a powerful knowledge graph."
      else
        "📊 Interesting dataset! Let's explore what patterns we can discover."
      end
    end

    def rights_collection_prompt(analysis)
      <<~PROMPT
        ✅ I've analyzed your data:
        #{analysis[:summary]}
        
        📋 Now let's establish data rights.
        What's the source of this data and what usage rights apply?
        
        Common options:
        1. Public domain
        2. Creative Commons (CC-BY, CC-BY-SA, etc.)
        3. Internal use only
        4. Custom license
      PROMPT
    end

    def gap_identification_prompt
      gaps = identify_gaps
      return preparation_prompt if gaps.empty?
      
      <<~PROMPT
        🔍 Analysis complete! Your dataset is taking shape.
        
        ⚠️ I've identified opportunities to enhance your dataset:
        #{format_gaps(gaps)}
        
        Would you like to add any of these? (You can say 'skip' to proceed)
      PROMPT
    end

    def preparation_prompt
      report = validation_report
      
      <<~PROMPT
        🎯 Final check before preparation:
        
        Dataset: #{@metadata[:dataset_type].to_s.humanize}
        #{format_dataset_summary}
        
        Validation: #{report[:ready] ? '✅ Ready' : '⚠️ Issues found'}
        #{format_validation_summary(report[:validations])}
        
        Ready to prepare for enliteration? (yes/no)
      PROMPT
    end

    def completion_message(bundle)
      <<~MESSAGE
        ✅ Dataset prepared successfully!
        
        📦 Bundle ID: #{bundle[:id]}
        📍 Location: #{bundle[:path]}
        📊 Statistics: #{bundle[:stats]}
        
        🚀 Ready for pipeline ingestion:
        rails enliterator:ingest[#{bundle[:path]}]
        
        💡 Based on your data structure, your enliterated dataset will excel at:
        #{generate_capability_preview}
        
        Thank you for using Interview!
      MESSAGE
    end

    def format_gaps(gaps)
      gaps.map.with_index(1) do |gap, i|
        "#{i}. #{gap[:name]} (#{gap[:impact]} impact) - #{gap[:description]}"
      end.join("\n")
    end

    def format_dataset_summary
      <<~SUMMARY
        ├── Entities: #{@dataset.entity_count}
        ├── Temporal range: #{@dataset.temporal_range}
        ├── Spatial data: #{@dataset.has_spatial? ? 'Yes' : 'No'}
        ├── Rights: #{@metadata.dig(:rights, :license) || 'Not set'}
        └── Training: #{@metadata.dig(:rights, :training_eligible) ? 'Eligible' : 'Not eligible'}
      SUMMARY
    end

    def format_validation_summary(validations)
      validations.map do |key, validation|
        status = validation[:passed] ? '✅' : '❌'
        "#{status} #{key.to_s.humanize}: #{validation[:message]}"
      end.join("\n")
    end

    def generate_capability_preview
      # Generate preview of what questions the dataset will answer well
      capabilities = []
      
      capabilities << "Temporal evolution patterns" if @dataset.has_temporal?
      capabilities << "Spatial relationships and neighborhoods" if @dataset.has_spatial?
      capabilities << "Entity relationship networks" if @dataset.relationship_count > 10
      capabilities << "Thematic analysis" if @dataset.has_descriptions?
      
      capabilities.map { |c| "• #{c}" }.join("\n")
    end

    def load_template(template_name)
      template_class = "Interview::Templates::#{template_name.to_s.camelize}".constantize
      @template = template_class.new(self)
      @template.apply
    end

    def template_intro
      @template&.introduction || "Let's begin."
    end

    def detect_path_type(path)
      return :directory if File.directory?(path)
      return :file if File.file?(path)
      :unknown
    end

    def parse_rights_input(input)
      # Parse various rights input formats
      rights = {}
      
      if input.match?(/public domain/i)
        rights[:license] = 'Public Domain'
        rights[:training_eligible] = true
        rights[:publishable] = true
      elsif match = input.match(/CC[- ]?BY[- ]?(SA|NC|ND)?/i)
        rights[:license] = "CC-#{match[0].upcase.gsub(/[- ]/, '-')}"
        rights[:training_eligible] = !match[0].match?(/NC/i)
        rights[:publishable] = true
      elsif input.match?(/internal/i)
        rights[:license] = 'Internal Use Only'
        rights[:training_eligible] = false
        rights[:publishable] = false
      else
        rights[:license] = 'Custom'
        rights[:source] = input
      end
      
      rights
    end

    def clarify_rights(issues)
      <<~PROMPT
        ⚠️ I need to clarify the rights information:
        
        #{issues.map { |i| "• #{i}" }.join("\n")}
        
        Please provide:
        - The license type (e.g., CC-BY-SA, Public Domain)
        - Whether this data can be used for AI training (yes/no)
        - Whether this data can be published publicly (yes/no)
      PROMPT
    end

    def process_gap_data(input, context)
      # Handle additional data for filling gaps
      "Processing additional data..."
    end

    def process_structuring_input(input)
      # Process structuring decisions
      { complete: false, next_question: "Next structuring question..." }
    end

    def next_structuring_question(result)
      result[:next_question]
    end

    def structuring_prompt_for_gaps
      transition_to(:structuring)
      "Let's add the missing data. Which enhancement would you like to start with?"
    end

    def request_more_data(analysis)
      "I need more data to proceed. #{analysis[:missing_data_message]}"
    end
  end
end