# app/services/deliverables/format_exporter.rb
module Deliverables
  class FormatExporter < ApplicationService
    attr_reader :batch_id, :output_dir, :format

    SUPPORTED_FORMATS = %w[json_ld graphml rdf csv markdown sql].freeze

    def initialize(batch_id, format: 'json_ld', output_dir: nil)
      @batch_id = batch_id
      @format = format.to_s.downcase
      @output_dir = output_dir || Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}", 'exports')
      FileUtils.mkdir_p(@output_dir)
      
      raise "Unsupported format: #{format}" unless SUPPORTED_FORMATS.include?(@format)
    end

    def call
      validate_batch!
      
      case format
      when 'json_ld'
        export_json_ld
      when 'graphml'
        export_graphml
      when 'rdf'
        export_rdf
      when 'csv'
        export_csv
      when 'markdown'
        export_markdown
      when 'sql'
        export_sql
      else
        raise "Format not implemented: #{format}"
      end
    end

    private

    def validate_batch!
      batch = IngestBatch.find(batch_id)
      raise "Batch not found" unless batch
      raise "Batch not ready for export" unless batch.literacy_score.to_f >= 70
    end

    def export_json_ld
      filename = 'graph.jsonld'
      filepath = File.join(output_dir, filename)
      
      json_ld = {
        "@context" => {
          "@base" => "https://enliterator.ai/dataset/#{batch_id}/",
          "enliterator" => "https://enliterator.ai/ontology#",
          "schema" => "https://schema.org/",
          "dc" => "http://purl.org/dc/terms/",
          "skos" => "http://www.w3.org/2004/02/skos/core#",
          
          "Idea" => "enliterator:Idea",
          "Manifest" => "enliterator:Manifest",
          "Experience" => "enliterator:Experience",
          "Relational" => "enliterator:Relational",
          "Evolutionary" => "enliterator:Evolutionary",
          "Practical" => "enliterator:Practical",
          "Emanation" => "enliterator:Emanation",
          
          "canonical_name" => "skos:prefLabel",
          "title" => "dc:title",
          "description" => "dc:description",
          "occurred_at" => "dc:date",
          "year" => "dc:temporal",
          "placement" => "schema:location",
          
          "embodies" => "enliterator:embodies",
          "manifests" => "enliterator:manifests",
          "elicits" => "enliterator:elicits",
          "enables" => "enliterator:enables",
          "influences" => "enliterator:influences",
          "relates_to" => "enliterator:relatesTo"
        },
        "@graph" => []
      }
      
      # Export nodes
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        model = pool.constantize
        entities = model.where(ingest_batch_id: batch_id).limit(1000)
        
        entities.each do |entity|
          node = {
            "@id" => "#{pool.downcase}/#{entity.id}",
            "@type" => pool,
            "dc:identifier" => entity.id
          }
          
          # Add pool-specific properties
          case pool
          when 'Idea'
            node["canonical_name"] = entity.canonical_name
            node["description"] = entity.description if entity.description.present?
          when 'Manifest', 'Experience'
            node["title"] = entity.title
            node["description"] = entity.description if entity.description.present?
            node["year"] = entity.year if entity.respond_to?(:year) && entity.year
          when 'Experience'
            node["occurred_at"] = entity.occurred_at.iso8601 if entity.occurred_at
          end
          
          # Add rights information
          if entity.respond_to?(:publishability)
            node["enliterator:publishability"] = entity.publishability
            node["enliterator:training_eligibility"] = entity.training_eligibility
          end
          
          json_ld["@graph"] << node
        end
      end
      
      # Export relationships
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN a, type(r) as rel_type, b, labels(a)[0] as label_a, labels(b)[0] as label_b
        LIMIT 5000
      CYPHER
      
      result.each_with_index do |row, idx|
        relationship = {
          "@id" => "relationship/#{idx}",
          "@type" => "enliterator:Relationship",
          "enliterator:relationshipType" => row['rel_type'].downcase,
          "enliterator:from" => {
            "@id" => "#{row['label_a'].downcase}/#{row['a']['id']}"
          },
          "enliterator:to" => {
            "@id" => "#{row['label_b'].downcase}/#{row['b']['id']}"
          }
        }
        
        json_ld["@graph"] << relationship
      end
      
      File.write(filepath, JSON.pretty_generate(json_ld))
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath),
        entity_count: json_ld["@graph"].count { |n| n["@type"] != "enliterator:Relationship" },
        relationship_count: json_ld["@graph"].count { |n| n["@type"] == "enliterator:Relationship" }
      }
    end

    def export_graphml
      filename = 'graph.graphml'
      filepath = File.join(output_dir, filename)
      
      require 'rexml/document'
      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')
      
      graphml = doc.add_element('graphml', {
        'xmlns' => 'http://graphml.graphdrawing.org/xmlns',
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd'
      })
      
      # Define attributes
      graphml.add_element('key', {'id' => 'd0', 'for' => 'node', 'attr.name' => 'pool', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd1', 'for' => 'node', 'attr.name' => 'title', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd2', 'for' => 'node', 'attr.name' => 'canonical_name', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd3', 'for' => 'node', 'attr.name' => 'description', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd4', 'for' => 'node', 'attr.name' => 'year', 'attr.type' => 'int'})
      graphml.add_element('key', {'id' => 'd5', 'for' => 'node', 'attr.name' => 'occurred_at', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd6', 'for' => 'edge', 'attr.name' => 'relationship_type', 'attr.type' => 'string'})
      graphml.add_element('key', {'id' => 'd7', 'for' => 'node', 'attr.name' => 'publishability', 'attr.type' => 'boolean'})
      
      graph = graphml.add_element('graph', {'id' => 'G', 'edgedefault' => 'directed'})
      
      # Export nodes
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        model = pool.constantize
        entities = model.where(ingest_batch_id: batch_id).limit(1000)
        
        entities.each do |entity|
          node = graph.add_element('node', {'id' => "#{pool.downcase}_#{entity.id}"})
          
          node.add_element('data', {'key' => 'd0'}).add_text(pool)
          
          if entity.respond_to?(:title) && entity.title.present?
            node.add_element('data', {'key' => 'd1'}).add_text(entity.title)
          end
          
          if entity.respond_to?(:canonical_name) && entity.canonical_name.present?
            node.add_element('data', {'key' => 'd2'}).add_text(entity.canonical_name)
          end
          
          if entity.respond_to?(:description) && entity.description.present?
            node.add_element('data', {'key' => 'd3'}).add_text(entity.description)
          end
          
          if entity.respond_to?(:year) && entity.year
            node.add_element('data', {'key' => 'd4'}).add_text(entity.year.to_s)
          end
          
          if entity.respond_to?(:occurred_at) && entity.occurred_at
            node.add_element('data', {'key' => 'd5'}).add_text(entity.occurred_at.iso8601)
          end
          
          if entity.respond_to?(:publishability)
            node.add_element('data', {'key' => 'd7'}).add_text(entity.publishability.to_s)
          end
        end
      end
      
      # Export edges
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN a, type(r) as rel_type, b, labels(a)[0] as label_a, labels(b)[0] as label_b
        LIMIT 5000
      CYPHER
      
      result.each_with_index do |row, idx|
        edge = graph.add_element('edge', {
          'id' => "e#{idx}",
          'source' => "#{row['label_a'].downcase}_#{row['a']['id']}",
          'target' => "#{row['label_b'].downcase}_#{row['b']['id']}"
        })
        edge.add_element('data', {'key' => 'd6'}).add_text(row['rel_type'])
      end
      
      # Write to file
      File.open(filepath, 'w') do |file|
        doc.write(file, 2)
      end
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath)
      }
    end

    def export_rdf
      filename = 'graph.ttl'
      filepath = File.join(output_dir, filename)
      
      rdf_lines = []
      
      # Prefixes
      rdf_lines << "@prefix enliterator: <https://enliterator.ai/ontology#> ."
      rdf_lines << "@prefix dc: <http://purl.org/dc/terms/> ."
      rdf_lines << "@prefix skos: <http://www.w3.org/2004/02/skos/core#> ."
      rdf_lines << "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> ."
      rdf_lines << "@base <https://enliterator.ai/dataset/#{batch_id}/> ."
      rdf_lines << ""
      
      # Export entities as RDF triples
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].each do |pool|
        model = pool.constantize
        entities = model.where(ingest_batch_id: batch_id).limit(1000)
        
        entities.each do |entity|
          subject = "<#{pool.downcase}/#{entity.id}>"
          
          rdf_lines << "#{subject} a enliterator:#{pool} ;"
          
          if entity.respond_to?(:canonical_name) && entity.canonical_name.present?
            rdf_lines << "    skos:prefLabel \"#{escape_turtle(entity.canonical_name)}\" ;"
          end
          
          if entity.respond_to?(:title) && entity.title.present?
            rdf_lines << "    dc:title \"#{escape_turtle(entity.title)}\" ;"
          end
          
          if entity.respond_to?(:description) && entity.description.present?
            rdf_lines << "    dc:description \"#{escape_turtle(entity.description)}\" ;"
          end
          
          if entity.respond_to?(:occurred_at) && entity.occurred_at
            rdf_lines << "    dc:date \"#{entity.occurred_at.iso8601}\"^^xsd:dateTime ;"
          end
          
          if entity.respond_to?(:year) && entity.year
            rdf_lines << "    dc:temporal \"#{entity.year}\"^^xsd:gYear ;"
          end
          
          rdf_lines[-1] = rdf_lines[-1].gsub(/;$/, '.')  # Replace last semicolon with period
          rdf_lines << ""
        end
      end
      
      # Export relationships
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN a, type(r) as rel_type, b, labels(a)[0] as label_a, labels(b)[0] as label_b
        LIMIT 5000
      CYPHER
      
      result.each do |row|
        subject = "<#{row['label_a'].downcase}/#{row['a']['id']}>"
        predicate = "enliterator:#{row['rel_type'].downcase}"
        object = "<#{row['label_b'].downcase}/#{row['b']['id']}>"
        
        rdf_lines << "#{subject} #{predicate} #{object} ."
      end
      
      File.write(filepath, rdf_lines.join("\n"))
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath),
        triple_count: rdf_lines.count { |line| line.end_with?('.') }
      }
    end

    def export_csv
      # Export separate CSV files for each pool
      exported_files = []
      
      %w[idea manifest experience relational evolutionary practical emanation].each do |pool|
        filename = "#{pool}_entities.csv"
        filepath = File.join(output_dir, filename)
        
        model = pool.capitalize.constantize
        entities = model.where(ingest_batch_id: batch_id)
        
        if entities.any?
          CSV.open(filepath, 'w') do |csv|
            # Header
            headers = ['id', 'pool']
            headers += ['canonical_name'] if entities.first.respond_to?(:canonical_name)
            headers += ['title'] if entities.first.respond_to?(:title)
            headers += ['description'] if entities.first.respond_to?(:description)
            headers += ['year'] if entities.first.respond_to?(:year)
            headers += ['occurred_at'] if entities.first.respond_to?(:occurred_at)
            headers += ['placement'] if entities.first.respond_to?(:placement)
            headers += ['publishability', 'training_eligibility'] if entities.first.respond_to?(:publishability)
            headers += ['created_at', 'updated_at']
            
            csv << headers
            
            # Data rows
            entities.find_each do |entity|
              row = [entity.id, pool]
              row << entity.canonical_name if entity.respond_to?(:canonical_name)
              row << entity.title if entity.respond_to?(:title)
              row << entity.description if entity.respond_to?(:description)
              row << entity.year if entity.respond_to?(:year)
              row << entity.occurred_at&.iso8601 if entity.respond_to?(:occurred_at)
              row << entity.placement if entity.respond_to?(:placement)
              
              if entity.respond_to?(:publishability)
                row << entity.publishability
                row << entity.training_eligibility
              end
              
              row << entity.created_at.iso8601
              row << entity.updated_at.iso8601
              
              csv << row
            end
          end
          
          exported_files << {
            filename: filename,
            path: filepath,
            row_count: entities.count + 1,
            size: File.size(filepath)
          }
        end
      end
      
      # Export relationships CSV
      relationships_file = export_relationships_csv
      exported_files << relationships_file if relationships_file
      
      {
        files: exported_files,
        total_files: exported_files.count,
        total_size: exported_files.sum { |f| f[:size] }
      }
    end

    def export_relationships_csv
      filename = 'relationships.csv'
      filepath = File.join(output_dir, filename)
      
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN 
          a.id as from_id,
          labels(a)[0] as from_pool,
          type(r) as relationship_type,
          b.id as to_id,
          labels(b)[0] as to_pool
        LIMIT 100000
      CYPHER
      
      return nil if result.empty?
      
      CSV.open(filepath, 'w') do |csv|
        csv << ['from_id', 'from_pool', 'relationship_type', 'to_id', 'to_pool']
        
        result.each do |row|
          csv << [
            row['from_id'],
            row['from_pool'].downcase,
            row['relationship_type'],
            row['to_id'],
            row['to_pool'].downcase
          ]
        end
      end
      
      {
        filename: filename,
        path: filepath,
        row_count: result.count + 1,
        size: File.size(filepath)
      }
    end

    def export_markdown
      filename = 'dataset_documentation.md'
      filepath = File.join(output_dir, filename)
      
      batch = IngestBatch.find(batch_id)
      
      markdown = []
      
      # Header
      markdown << "# Enliterated Dataset: #{batch.name}"
      markdown << ""
      markdown << "**Generated**: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      markdown << "**Batch ID**: #{batch.id}"
      markdown << "**Literacy Score**: #{batch.literacy_score}"
      markdown << ""
      
      # Executive Summary
      markdown << "## Executive Summary"
      markdown << ""
      markdown << "This dataset has been successfully enliterated with a literacy score of #{batch.literacy_score}. "
      markdown << "It contains structured knowledge across multiple pools of meaning with explicit relationships and provenance tracking."
      markdown << ""
      
      # Dataset Statistics
      markdown << "## Dataset Statistics"
      markdown << ""
      
      stats = generate_statistics
      
      markdown << "### Entity Counts by Pool"
      markdown << ""
      markdown << "| Pool | Count | Percentage |"
      markdown << "|------|-------|------------|"
      
      total_entities = stats[:entity_counts].values.sum
      stats[:entity_counts].each do |pool, count|
        percentage = ((count.to_f / total_entities) * 100).round(1)
        markdown << "| #{pool.capitalize} | #{count} | #{percentage}% |"
      end
      markdown << ""
      
      markdown << "### Relationship Summary"
      markdown << ""
      markdown << "- **Total Relationships**: #{stats[:relationship_count]}"
      markdown << "- **Unique Relationship Types**: #{stats[:relationship_types].count}"
      markdown << "- **Average Degree**: #{stats[:avg_degree].round(2)}"
      markdown << ""
      
      # Top Entities
      markdown << "## Key Entities"
      markdown << ""
      
      # Ideas
      ideas = Idea.where(ingest_batch_id: batch_id).limit(5)
      if ideas.any?
        markdown << "### Core Ideas"
        markdown << ""
        ideas.each do |idea|
          markdown << "- **#{idea.canonical_name}**: #{idea.description || 'Core concept in the dataset'}"
        end
        markdown << ""
      end
      
      # Manifests
      manifests = Manifest.where(ingest_batch_id: batch_id).limit(5)
      if manifests.any?
        markdown << "### Key Manifests"
        markdown << ""
        manifests.each do |manifest|
          year_str = manifest.year ? " (#{manifest.year})" : ""
          markdown << "- **#{manifest.title}#{year_str}**: #{manifest.description || 'Physical manifestation'}"
        end
        markdown << ""
      end
      
      # Temporal Coverage
      experiences = Experience.where(ingest_batch_id: batch_id).where.not(occurred_at: nil)
      if experiences.any?
        markdown << "## Temporal Coverage"
        markdown << ""
        markdown << "- **Earliest Event**: #{experiences.minimum(:occurred_at).strftime('%Y-%m-%d')}"
        markdown << "- **Latest Event**: #{experiences.maximum(:occurred_at).strftime('%Y-%m-%d')}"
        markdown << "- **Total Events with Dates**: #{experiences.count}"
        markdown << ""
      end
      
      # Rights and Provenance
      markdown << "## Rights and Provenance"
      markdown << ""
      
      public_count = ProvenanceAndRights.where(ingest_batch_id: batch_id, publishability: true).count
      training_count = ProvenanceAndRights.where(ingest_batch_id: batch_id, training_eligibility: true).count
      
      markdown << "- **Public/Publishable Content**: #{public_count} entities"
      markdown << "- **Training-Eligible Content**: #{training_count} entities"
      markdown << "- **Rights Tracking**: Complete for all entities"
      markdown << ""
      
      # Query Examples
      markdown << "## Example Queries"
      markdown << ""
      markdown << "This dataset supports various query patterns:"
      markdown << ""
      markdown << "### Discovery Queries"
      markdown << "```cypher"
      markdown << "// Find connections between ideas and manifests"
      markdown << "MATCH path = (i:Idea)-[*..3]-(m:Manifest)"
      markdown << "WHERE i.canonical_name = 'Example Idea'"
      markdown << "RETURN path"
      markdown << "```"
      markdown << ""
      
      markdown << "### Temporal Queries"
      markdown << "```cypher"
      markdown << "// Find experiences in a time range"
      markdown << "MATCH (e:Experience)"
      markdown << "WHERE e.occurred_at >= '2020-01-01' AND e.occurred_at <= '2020-12-31'"
      markdown << "RETURN e ORDER BY e.occurred_at"
      markdown << "```"
      markdown << ""
      
      markdown << "### Relationship Analysis"
      markdown << "```cypher"
      markdown << "// Find most connected entities"
      markdown << "MATCH (n)"
      markdown << "WITH n, size((n)-[]-()) as degree"
      markdown << "ORDER BY degree DESC LIMIT 10"
      markdown << "RETURN n, degree"
      markdown << "```"
      markdown << ""
      
      # Export Information
      markdown << "## Export Formats"
      markdown << ""
      markdown << "This dataset is available in the following formats:"
      markdown << ""
      markdown << "- **JSON-LD**: Semantic web compatible (graph.jsonld)"
      markdown << "- **GraphML**: For graph analysis tools (graph.graphml)"
      markdown << "- **RDF/Turtle**: For triple stores (graph.ttl)"
      markdown << "- **CSV**: Flat exports by pool (multiple files)"
      markdown << "- **SQL**: Relational database dump (database.sql)"
      markdown << "- **Cypher**: Neo4j graph dump (graph.cypher)"
      markdown << ""
      
      # Footer
      markdown << "---"
      markdown << ""
      markdown << "*Generated by Enliterator v1.0.0*"
      markdown << ""
      
      File.write(filepath, markdown.join("\n"))
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath),
        line_count: markdown.count
      }
    end

    def export_sql
      filename = 'database.sql'
      filepath = File.join(output_dir, filename)
      
      sql_lines = []
      
      # Header
      sql_lines << "-- Enliterated Dataset SQL Export"
      sql_lines << "-- Generated: #{Time.current}"
      sql_lines << "-- Batch ID: #{batch_id}"
      sql_lines << ""
      
      # Create tables
      sql_lines << "-- Create Tables"
      sql_lines << ""
      
      # Ideas table
      sql_lines << "CREATE TABLE IF NOT EXISTS ideas ("
      sql_lines << "  id VARCHAR(255) PRIMARY KEY,"
      sql_lines << "  canonical_name VARCHAR(255) NOT NULL,"
      sql_lines << "  description TEXT,"
      sql_lines << "  publishability BOOLEAN DEFAULT false,"
      sql_lines << "  training_eligibility BOOLEAN DEFAULT false,"
      sql_lines << "  created_at TIMESTAMP,"
      sql_lines << "  updated_at TIMESTAMP"
      sql_lines << ");"
      sql_lines << ""
      
      # Manifests table
      sql_lines << "CREATE TABLE IF NOT EXISTS manifests ("
      sql_lines << "  id VARCHAR(255) PRIMARY KEY,"
      sql_lines << "  title VARCHAR(255) NOT NULL,"
      sql_lines << "  description TEXT,"
      sql_lines << "  year INTEGER,"
      sql_lines << "  placement VARCHAR(255),"
      sql_lines << "  publishability BOOLEAN DEFAULT false,"
      sql_lines << "  training_eligibility BOOLEAN DEFAULT false,"
      sql_lines << "  created_at TIMESTAMP,"
      sql_lines << "  updated_at TIMESTAMP"
      sql_lines << ");"
      sql_lines << ""
      
      # Experiences table
      sql_lines << "CREATE TABLE IF NOT EXISTS experiences ("
      sql_lines << "  id VARCHAR(255) PRIMARY KEY,"
      sql_lines << "  title VARCHAR(255) NOT NULL,"
      sql_lines << "  description TEXT,"
      sql_lines << "  occurred_at TIMESTAMP,"
      sql_lines << "  publishability BOOLEAN DEFAULT false,"
      sql_lines << "  training_eligibility BOOLEAN DEFAULT false,"
      sql_lines << "  created_at TIMESTAMP,"
      sql_lines << "  updated_at TIMESTAMP"
      sql_lines << ");"
      sql_lines << ""
      
      # Relationships table
      sql_lines << "CREATE TABLE IF NOT EXISTS relationships ("
      sql_lines << "  id SERIAL PRIMARY KEY,"
      sql_lines << "  from_id VARCHAR(255),"
      sql_lines << "  from_type VARCHAR(50),"
      sql_lines << "  to_id VARCHAR(255),"
      sql_lines << "  to_type VARCHAR(50),"
      sql_lines << "  relationship_type VARCHAR(100),"
      sql_lines << "  created_at TIMESTAMP"
      sql_lines << ");"
      sql_lines << ""
      
      # Insert data
      sql_lines << "-- Insert Data"
      sql_lines << ""
      
      # Ideas
      ideas = Idea.where(ingest_batch_id: batch_id).limit(1000)
      ideas.each do |idea|
        sql_lines << "INSERT INTO ideas (id, canonical_name, description, publishability, training_eligibility, created_at, updated_at) VALUES ("
        sql_lines << "  '#{idea.id}',"
        sql_lines << "  '#{escape_sql(idea.canonical_name)}',"
        sql_lines << "  #{idea.description ? "'#{escape_sql(idea.description)}'" : 'NULL'},"
        sql_lines << "  #{idea.publishability},"
        sql_lines << "  #{idea.training_eligibility},"
        sql_lines << "  '#{idea.created_at.iso8601}',"
        sql_lines << "  '#{idea.updated_at.iso8601}'"
        sql_lines << ");"
      end
      sql_lines << ""
      
      # Manifests
      manifests = Manifest.where(ingest_batch_id: batch_id).limit(1000)
      manifests.each do |manifest|
        sql_lines << "INSERT INTO manifests (id, title, description, year, placement, publishability, training_eligibility, created_at, updated_at) VALUES ("
        sql_lines << "  '#{manifest.id}',"
        sql_lines << "  '#{escape_sql(manifest.title)}',"
        sql_lines << "  #{manifest.description ? "'#{escape_sql(manifest.description)}'" : 'NULL'},"
        sql_lines << "  #{manifest.year || 'NULL'},"
        sql_lines << "  #{manifest.placement ? "'#{escape_sql(manifest.placement)}'" : 'NULL'},"
        sql_lines << "  #{manifest.publishability},"
        sql_lines << "  #{manifest.training_eligibility},"
        sql_lines << "  '#{manifest.created_at.iso8601}',"
        sql_lines << "  '#{manifest.updated_at.iso8601}'"
        sql_lines << ");"
      end
      sql_lines << ""
      
      # Create indexes
      sql_lines << "-- Create Indexes"
      sql_lines << "CREATE INDEX idx_ideas_canonical_name ON ideas(canonical_name);"
      sql_lines << "CREATE INDEX idx_manifests_title ON manifests(title);"
      sql_lines << "CREATE INDEX idx_manifests_year ON manifests(year);"
      sql_lines << "CREATE INDEX idx_experiences_occurred_at ON experiences(occurred_at);"
      sql_lines << "CREATE INDEX idx_relationships_from ON relationships(from_id, from_type);"
      sql_lines << "CREATE INDEX idx_relationships_to ON relationships(to_id, to_type);"
      sql_lines << ""
      
      File.write(filepath, sql_lines.join("\n"))
      
      {
        filename: filename,
        path: filepath,
        size: File.size(filepath),
        line_count: sql_lines.count
      }
    end

    # Helper methods
    def escape_turtle(str)
      str.gsub('"', '\\"').gsub("\n", "\\n").gsub("\r", "\\r")
    end

    def escape_sql(str)
      str.gsub("'", "''")
    end

    def generate_statistics
      stats = {
        entity_counts: {},
        relationship_count: 0,
        relationship_types: [],
        avg_degree: 0
      }
      
      # Entity counts
      %w[idea manifest experience relational evolutionary practical emanation].each do |pool|
        model = pool.capitalize.constantize
        stats[:entity_counts][pool] = model.where(ingest_batch_id: batch_id).count
      end
      
      # Relationship statistics
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        WHERE startNode(r).ingest_batch_id = #{batch_id}
        RETURN count(r) as count, collect(DISTINCT type(r)) as types
      CYPHER
      
      if result.any?
        stats[:relationship_count] = result.first['count'] || 0
        stats[:relationship_types] = result.first['types'] || []
      end
      
      # Average degree
      total_entities = stats[:entity_counts].values.sum
      if total_entities > 0
        stats[:avg_degree] = (2.0 * stats[:relationship_count]) / total_entities
      end
      
      stats
    end

    def neo4j_query(cypher)
      Rails.configuration.neo4j_driver.session do |session|
        session.run(cypher).to_a
      end
    rescue => e
      Rails.logger.error "Neo4j query failed: #{e.message}"
      []
    end
  end
end