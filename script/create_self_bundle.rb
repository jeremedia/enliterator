#!/usr/bin/env ruby
# frozen_string_literal: true

# Meta-Enliteration: Create a bundle of the Enliterator codebase itself
# This bundle will be processed through the pipeline to create the first EKN

require 'fileutils'
require 'zip'
require 'json'
require 'digest'

class SelfBundleCreator
  BUNDLE_DIR = Rails.root.join('tmp', 'bundles')
  BUNDLE_NAME = "enliterator_self_#{Time.now.strftime('%Y%m%d_%H%M%S')}.zip"
  
  # Files and directories to include in the bundle
  INCLUDE_PATTERNS = [
    'app/**/*.rb',
    'lib/**/*.rb',
    'lib/tasks/**/*.rake',
    'config/**/*.rb',
    'db/migrate/**/*.rb',
    'db/schema.rb',
    'script/**/*.rb',
    'docs/**/*.md',
    'test/**/*.rb',
    'spec/**/*.rb',
    'Gemfile',
    'Gemfile.lock',
    'README.md',
    'CLAUDE.md',
    '.env.example'
  ].freeze
  
  # Patterns to explicitly exclude
  EXCLUDE_PATTERNS = [
    '**/node_modules/**',
    '**/tmp/**',
    '**/log/**',
    '**/.git/**',
    '**/storage/**',
    '**/vendor/**',
    '**/.env',
    '**/*.log'
  ].freeze
  
  def initialize
    @files_to_bundle = []
    @metadata = {
      created_at: Time.now.iso8601,
      source: 'Enliterator Meta-Enliteration',
      version: '1.0.0',
      description: 'Self-bundle of the Enliterator codebase for creating the first EKN',
      statistics: {}
    }
  end
  
  def create_bundle!
    puts "=== Creating Enliterator Self-Bundle ==="
    
    collect_files
    generate_metadata
    create_zip_bundle
    
    bundle_path = BUNDLE_DIR.join(BUNDLE_NAME)
    puts "\n✓ Bundle created: #{bundle_path}"
    puts "  Size: #{(File.size(bundle_path) / 1024.0 / 1024.0).round(2)} MB"
    puts "  Files: #{@files_to_bundle.size}"
    puts "\nReady for ingestion: rails enliterator:ingest[#{bundle_path}]"
    
    bundle_path.to_s
  end
  
  private
  
  def collect_files
    puts "\nCollecting files..."
    
    INCLUDE_PATTERNS.each do |pattern|
      files = Dir.glob(Rails.root.join(pattern), File::FNM_DOTMATCH)
      files.each do |file|
        next if File.directory?(file)
        next if should_exclude?(file)
        
        @files_to_bundle << file
        print "."
      end
    end
    
    puts "\n✓ Collected #{@files_to_bundle.size} files"
  end
  
  def should_exclude?(file)
    EXCLUDE_PATTERNS.any? do |pattern|
      File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_DOTMATCH)
    end
  end
  
  def generate_metadata
    puts "\nGenerating metadata..."
    
    # File type statistics
    extensions = @files_to_bundle.map { |f| File.extname(f).downcase }.tally
    
    # Line count statistics
    total_lines = 0
    total_size = 0
    
    @files_to_bundle.each do |file|
      if File.exist?(file) && File.extname(file) =~ /\.(rb|rake|md|txt|yml|yaml|json|xml|html|erb|haml|slim|css|scss|js|jsx|ts|tsx)$/i
        lines = File.readlines(file).size rescue 0
        total_lines += lines
      end
      total_size += File.size(file)
    end
    
    @metadata[:statistics] = {
      total_files: @files_to_bundle.size,
      total_lines: total_lines,
      total_size_bytes: total_size,
      file_types: extensions,
      top_directories: count_by_directory
    }
    
    # Add bundle manifest
    @metadata[:manifest] = {
      bundle_hash: calculate_bundle_hash,
      files: @files_to_bundle.map do |file|
        relative_path = Pathname.new(file).relative_path_from(Rails.root).to_s
        {
          path: relative_path,
          size: File.size(file),
          modified: File.mtime(file).iso8601,
          hash: Digest::SHA256.file(file).hexdigest
        }
      end
    }
    
    puts "✓ Metadata generated"
  end
  
  def count_by_directory
    dirs = @files_to_bundle.map do |file|
      Pathname.new(file).relative_path_from(Rails.root).dirname.to_s.split('/').first
    end.tally.sort_by { |_, count| -count }.first(10).to_h
  end
  
  def calculate_bundle_hash
    content = @files_to_bundle.sort.map do |file|
      "#{file}:#{File.size(file)}:#{File.mtime(file).to_i}"
    end.join("\n")
    
    Digest::SHA256.hexdigest(content)
  end
  
  def create_zip_bundle
    FileUtils.mkdir_p(BUNDLE_DIR)
    bundle_path = BUNDLE_DIR.join(BUNDLE_NAME)
    
    puts "\nCreating ZIP bundle..."
    
    Zip::File.open(bundle_path, Zip::File::CREATE) do |zipfile|
      # Add metadata
      zipfile.get_output_stream('META-INF/metadata.json') do |f|
        f.write(JSON.pretty_generate(@metadata))
      end
      
      # Add licensing information
      zipfile.get_output_stream('META-INF/LICENSE.txt') do |f|
        f.write(<<~LICENSE)
          Enliterator Codebase Bundle
          ============================
          
          This bundle contains the source code of the Enliterator system.
          
          Purpose: Meta-enliteration to create the first Enliterated Knowledge Navigator (EKN)
          
          Rights: Internal use, training-eligible
          License: MIT (assumed for open source Rails application)
          
          Created: #{Time.now}
          Bundle ID: #{@metadata[:manifest][:bundle_hash][0..7]}
        LICENSE
      end
      
      # Add all collected files
      @files_to_bundle.each do |file|
        relative_path = Pathname.new(file).relative_path_from(Rails.root).to_s
        zipfile.add(relative_path, file)
        print "."
      end
    end
    
    puts "\n✓ ZIP bundle created"
  end
end

# Run if executed directly
if __FILE__ == $0
  require_relative '../config/environment'
  SelfBundleCreator.new.create_bundle!
end