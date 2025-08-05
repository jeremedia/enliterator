# app/services/interview/dataset_builder.rb
module Interview
  class DatasetBuilder
    attr_reader :sources, :entities, :relationships, :metadata

    def initialize
      @sources = []
      @entities = {}
      @relationships = []
      @metadata = {
        created_at: Time.current,
        last_modified: Time.current
      }
      @temporal_fields = {}
      @spatial_fields = {}
      @descriptions = {}
    end

    def add_file(path)
      raise "File not found: #{path}" unless File.exist?(path)
      
      source = {
        type: :file,
        path: path,
        filename: File.basename(path),
        size: File.size(path),
        mime_type: detect_mime_type(path),
        added_at: Time.current
      }
      
      @sources << source
      process_file(path)
      update_metadata
    end

    def add_directory(path)
      raise "Directory not found: #{path}" unless Dir.exist?(path)
      
      files = Dir.glob(File.join(path, '**/*')).select { |f| File.file?(f) }
      files.each { |file| add_file(file) }
    end

    def add_url(url)
      source = {
        type: :url,
        url: url,
        added_at: Time.current
      }
      
      @sources << source
      # In production, would fetch and process URL content
      update_metadata
    end

    def add_text(text)
      source = {
        type: :text,
        content: text,
        size: text.bytesize,
        added_at: Time.current
      }
      
      @sources << source
      process_text(text)
      update_metadata
    end

    def add_api(endpoint, params = {})
      source = {
        type: :api,
        endpoint: endpoint,
        params: params,
        added_at: Time.current
      }
      
      @sources << source
      # In production, would fetch from API
      update_metadata
    end

    def entity_count
      @entities.values.flatten.count
    end

    def relationship_count
      @relationships.count
    end

    def has_temporal?
      @temporal_fields.any?
    end

    def has_spatial?
      @spatial_fields.any?
    end

    def has_descriptions?
      @descriptions.any?
    end

    def temporal_range
      return "No temporal data" unless has_temporal?
      
      dates = @temporal_fields.values.flatten.compact
      return "No valid dates" if dates.empty?
      
      min_date = dates.min
      max_date = dates.max
      
      if min_date == max_date
        min_date.to_s
      else
        "#{min_date} to #{max_date}"
      end
    end

    def spatial_coverage
      return "No spatial data" unless has_spatial?
      
      locations = @spatial_fields.values.flatten.compact
      "#{locations.count} locations"
    end

    def to_h
      {
        sources: @sources,
        entities: @entities,
        relationships: @relationships,
        metadata: @metadata,
        temporal_fields: @temporal_fields,
        spatial_fields: @spatial_fields,
        descriptions: @descriptions,
        statistics: statistics
      }
    end

    def self.from_hash(hash)
      builder = new
      builder.instance_variable_set(:@sources, hash[:sources])
      builder.instance_variable_set(:@entities, hash[:entities])
      builder.instance_variable_set(:@relationships, hash[:relationships])
      builder.instance_variable_set(:@metadata, hash[:metadata])
      builder.instance_variable_set(:@temporal_fields, hash[:temporal_fields])
      builder.instance_variable_set(:@spatial_fields, hash[:spatial_fields])
      builder.instance_variable_set(:@descriptions, hash[:descriptions])
      builder
    end

    def statistics
      {
        source_count: @sources.count,
        entity_count: entity_count,
        relationship_count: relationship_count,
        entity_types: @entities.keys,
        has_temporal: has_temporal?,
        temporal_range: temporal_range,
        has_spatial: has_spatial?,
        spatial_coverage: spatial_coverage,
        has_descriptions: has_descriptions?,
        description_coverage: description_coverage
      }
    end

    def validate_structure
      issues = []
      
      issues << "No entities detected" if @entities.empty?
      issues << "No temporal data found" unless has_temporal?
      issues << "Limited relationship data" if relationship_count < 5
      
      {
        valid: issues.empty?,
        issues: issues
      }
    end

    def merge_with(other_builder)
      @sources.concat(other_builder.sources)
      
      other_builder.entities.each do |type, entities|
        @entities[type] ||= []
        @entities[type].concat(entities)
      end
      
      @relationships.concat(other_builder.relationships)
      
      other_builder.instance_variable_get(:@temporal_fields).each do |field, values|
        @temporal_fields[field] ||= []
        @temporal_fields[field].concat(values)
      end
      
      other_builder.instance_variable_get(:@spatial_fields).each do |field, values|
        @spatial_fields[field] ||= []
        @spatial_fields[field].concat(values)
      end
      
      @descriptions.merge!(other_builder.instance_variable_get(:@descriptions))
      
      update_metadata
    end

    private

    def detect_mime_type(path)
      extension = File.extname(path).downcase
      
      case extension
      when '.csv'
        'text/csv'
      when '.json'
        'application/json'
      when '.xml'
        'application/xml'
      when '.txt', '.md'
        'text/plain'
      when '.pdf'
        'application/pdf'
      when '.zip'
        'application/zip'
      else
        'application/octet-stream'
      end
    end

    def process_file(path)
      case detect_mime_type(path)
      when 'text/csv'
        process_csv(path)
      when 'application/json'
        process_json(path)
      when 'text/plain'
        process_text(File.read(path))
      end
    end

    def process_csv(path)
      require 'csv'
      
      rows = CSV.read(path, headers: true)
      return if rows.empty?
      
      # Detect entity type from filename or content
      entity_type = detect_entity_type_from_csv(path, rows)
      
      @entities[entity_type] ||= []
      
      rows.each do |row|
        entity = row.to_h
        @entities[entity_type] << entity
        
        # Detect temporal fields
        detect_temporal_fields(entity)
        
        # Detect spatial fields
        detect_spatial_fields(entity)
        
        # Detect descriptions
        detect_descriptions(entity)
      end
    rescue CSV::MalformedCSVError => e
      Rails.logger.error "Failed to parse CSV #{path}: #{e.message}"
    end

    def process_json(path)
      data = JSON.parse(File.read(path))
      
      if data.is_a?(Array)
        entity_type = detect_entity_type_from_json(path, data)
        @entities[entity_type] ||= []
        @entities[entity_type].concat(data)
      elsif data.is_a?(Hash)
        data.each do |key, value|
          if value.is_a?(Array)
            @entities[key] ||= []
            @entities[key].concat(value)
          end
        end
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse JSON #{path}: #{e.message}"
    end

    def process_text(text)
      # Basic text processing - in production would use NLP
      lines = text.split("\n").reject(&:blank?)
      
      @entities[:text_content] ||= []
      @entities[:text_content] << {
        content: text,
        line_count: lines.count,
        word_count: text.split.count
      }
    end

    def detect_entity_type_from_csv(path, rows)
      filename = File.basename(path, '.*').downcase
      
      # Check filename hints
      return :camps if filename.include?('camp')
      return :events if filename.include?('event')
      return :people if filename.include?('person') || filename.include?('people')
      return :locations if filename.include?('location') || filename.include?('place')
      
      # Check column names
      headers = rows.headers.map(&:to_s).map(&:downcase)
      
      return :camps if headers.any? { |h| h.include?('camp') }
      return :events if headers.any? { |h| h.include?('event') }
      return :people if headers.any? { |h| h.include?('name') && h.include?('email') }
      
      :entities  # Generic fallback
    end

    def detect_entity_type_from_json(path, data)
      filename = File.basename(path, '.*').downcase
      
      # Similar detection logic as CSV
      return :camps if filename.include?('camp')
      return :events if filename.include?('event')
      
      # Check first item's keys if array
      if data.is_a?(Array) && data.first.is_a?(Hash)
        keys = data.first.keys.map(&:to_s).map(&:downcase)
        return :camps if keys.any? { |k| k.include?('camp') }
        return :events if keys.any? { |k| k.include?('event') }
      end
      
      :entities
    end

    def detect_temporal_fields(entity)
      entity.each do |key, value|
        next unless value.is_a?(String)
        
        # Check for date patterns
        if key.to_s.match?(/date|time|year|month|day|created|updated|when/i)
          @temporal_fields[key] ||= []
          @temporal_fields[key] << parse_date(value)
        elsif value.match?(/^\d{4}$/)  # Year only
          @temporal_fields[key] ||= []
          @temporal_fields[key] << value.to_i
        elsif parsed_date = parse_date(value)
          @temporal_fields[key] ||= []
          @temporal_fields[key] << parsed_date
        end
      end
    end

    def detect_spatial_fields(entity)
      entity.each do |key, value|
        next unless value.is_a?(String)
        
        # Check for location patterns
        if key.to_s.match?(/location|address|place|coordinate|lat|lng|lon|street|clock/i)
          @spatial_fields[key] ||= []
          @spatial_fields[key] << value
        elsif value.match?(/^\d+:\d+\s*&?\s*[A-Z]$/i)  # Burning Man address format
          @spatial_fields[key] ||= []
          @spatial_fields[key] << value
        end
      end
    end

    def detect_descriptions(entity)
      entity.each do |key, value|
        next unless value.is_a?(String)
        
        # Check for description fields
        if key.to_s.match?(/description|about|bio|summary|theme|detail/i)
          entity_id = entity[:id] || entity[:name] || entity.values.first
          @descriptions[entity_id] = value if value.length > 20
        end
      end
    end

    def parse_date(value)
      return nil unless value.is_a?(String)
      
      Date.parse(value) rescue nil
    end

    def update_metadata
      @metadata[:last_modified] = Time.current
      @metadata[:source_count] = @sources.count
      @metadata[:entity_count] = entity_count
    end

    def description_coverage
      return "0%" if @entities.empty?
      
      total_entities = entity_count
      entities_with_descriptions = @descriptions.count
      
      percentage = (entities_with_descriptions.to_f / total_entities * 100).round(1)
      "#{percentage}%"
    end
  end
end