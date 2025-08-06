# app/services/meta_enliteration/bundle_creator.rb
# Creates a self-referential bundle of the Enliterator codebase for meta-enliteration
# This bundle will be processed through the pipeline to create the first EKN

module MetaEnliteration
  class BundleCreator < ApplicationService
    
    attr_reader :bundle_path, :manifest
    
    def initialize
      @timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      @bundle_name = "enliterator_self_#{@timestamp}"
      @bundle_path = Rails.root.join('tmp', 'bundles', "#{@bundle_name}.zip")
      @temp_dir = Rails.root.join('tmp', 'meta_enliteration', @bundle_name)
      @manifest = build_manifest
    end
    
    def call
      prepare_directories
      collect_source_files
      collect_documentation
      collect_tests
      collect_git_history
      collect_operational_files
      write_manifest
      create_zip_bundle
      
      {
        success: true,
        bundle_path: @bundle_path.to_s,
        manifest: @manifest,
        stats: bundle_statistics
      }
    rescue => e
      {
        success: false,
        error: e.message,
        backtrace: e.backtrace
      }
    end
    
    private
    
    def prepare_directories
      FileUtils.mkdir_p(@temp_dir)
      FileUtils.mkdir_p(File.dirname(@bundle_path))
      
      # Create subdirectories for organization
      %w[code docs tests history operations].each do |dir|
        FileUtils.mkdir_p(@temp_dir.join(dir))
      end
    end
    
    def collect_source_files
      # Collect all Ruby source files - these become Manifest entities
      source_patterns = [
        'app/**/*.rb',
        'lib/**/*.rb',
        'db/migrate/*.rb',
        'config/**/*.rb'
      ]
      
      source_patterns.each do |pattern|
        Dir.glob(Rails.root.join(pattern)).each do |file|
          next if file.include?('tmp/') || file.include?('vendor/')
          
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          dest_path = @temp_dir.join('code', relative_path)
          
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(file, dest_path)
        end
      end
    end
    
    def collect_documentation
      # Collect documentation - these become Idea entities
      doc_files = [
        'CLAUDE.md',
        'README.md',
        'docs/**/*.md'
      ]
      
      doc_files.each do |pattern|
        Dir.glob(Rails.root.join(pattern)).each do |file|
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          dest_path = @temp_dir.join('docs', relative_path)
          
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(file, dest_path)
        end
      end
    end
    
    def collect_tests
      # Collect test files - these become Experience entities
      test_patterns = [
        'spec/**/*_spec.rb',
        'script/test_*.rb'
      ]
      
      test_patterns.each do |pattern|
        Dir.glob(Rails.root.join(pattern)).each do |file|
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          dest_path = @temp_dir.join('tests', relative_path)
          
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(file, dest_path)
        end
      end
    end
    
    def collect_git_history
      # Extract git history - becomes Evolutionary entities
      history_file = @temp_dir.join('history', 'git_log.json')
      
      git_log = extract_git_commits
      File.write(history_file, JSON.pretty_generate(git_log))
    end
    
    def collect_operational_files
      # Collect operational files - become Practical entities
      operational_files = [
        'Gemfile',
        'Gemfile.lock',
        'Rakefile',
        'lib/tasks/**/*.rake',
        'bin/**/*',
        '.env.example'
      ]
      
      operational_files.each do |pattern|
        Dir.glob(Rails.root.join(pattern)).each do |file|
          next if File.directory?(file)
          
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          dest_path = @temp_dir.join('operations', relative_path)
          
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(file, dest_path)
        end
      end
    end
    
    def extract_git_commits(limit = 100)
      commits = []
      
      # Use git log to extract commit history
      git_output = `git log --format='%H|%an|%ae|%at|%s' -n #{limit}`
      
      git_output.each_line do |line|
        parts = line.strip.split('|')
        next if parts.length < 5
        
        commits << {
          sha: parts[0],
          author: parts[1],
          email: parts[2],
          timestamp: Time.at(parts[3].to_i).iso8601,
          message: parts[4]
        }
      end
      
      # Also extract file changes for key commits
      important_commits = commits.first(20)
      important_commits.each do |commit|
        files_changed = `git diff-tree --no-commit-id --name-only -r #{commit[:sha]}`.split("\n")
        commit[:files_changed] = files_changed
      end
      
      commits
    end
    
    def build_manifest
      {
        version: '1.0',
        generator: 'MetaEnliteration::BundleCreator',
        created_at: Time.current.iso8601,
        
        # Bundle metadata
        title: 'Enliterator System Knowledge',
        source_owner: 'Enliterator Project',
        intended_use: 'public',
        default_rights: 'MIT License',
        
        # Domain hints for processing
        domain: 'software_engineering',
        subdomains: ['ruby', 'rails', 'knowledge_graphs', 'nlp'],
        
        # Temporal bounds
        temporal_start: '2025-01-01',
        temporal_end: Time.current.to_date.to_s,
        
        # Expected pools to be populated
        expected_pools: {
          idea: 'Core concepts and principles',
          manifest: 'Source files and artifacts',
          experience: 'Test results and usage',
          relational: 'Dependencies and connections',
          evolutionary: 'Git history and versions',
          practical: 'Commands and procedures',
          emanation: 'Generated outputs',
          intent: 'Design goals and user stories',
          lexicon: 'Technical vocabulary',
          spatial: 'File and module structure'
        },
        
        # Processing hints
        processing_hints: {
          primary_language: 'ruby',
          framework: 'rails',
          test_framework: 'rspec',
          documentation_format: 'markdown'
        },
        
        # Expected outcomes
        expected_enliteracy_score: 85,
        target_maturity: 'M4'
      }
    end
    
    def write_manifest
      manifest_path = @temp_dir.join('manifest.json')
      File.write(manifest_path, JSON.pretty_generate(@manifest))
    end
    
    def create_zip_bundle
      require 'zip'
      
      # Remove existing bundle if present
      FileUtils.rm_f(@bundle_path)
      
      # Create zip file
      Zip::File.open(@bundle_path, Zip::File::CREATE) do |zipfile|
        Dir.glob(@temp_dir.join('**', '*')).each do |file|
          next if File.directory?(file)
          
          relative_path = Pathname.new(file).relative_path_from(@temp_dir)
          zipfile.add(relative_path.to_s, file)
        end
      end
      
      # Clean up temp directory
      FileUtils.rm_rf(@temp_dir)
    end
    
    def bundle_statistics
      {
        total_files: count_files_in_zip,
        size_bytes: File.size(@bundle_path),
        size_human: human_filesize(File.size(@bundle_path)),
        categories: {
          code_files: Dir.glob(@temp_dir.join('code', '**', '*.rb')).count,
          doc_files: Dir.glob(@temp_dir.join('docs', '**', '*.md')).count,
          test_files: Dir.glob(@temp_dir.join('tests', '**', '*_spec.rb')).count,
          operational_files: Dir.glob(@temp_dir.join('operations', '**', '*')).count
        }
      }
    rescue
      # If temp dir is already cleaned up, estimate from patterns
      {
        estimated: true,
        total_files: 'unknown',
        size_bytes: File.size(@bundle_path),
        size_human: human_filesize(File.size(@bundle_path))
      }
    end
    
    def count_files_in_zip
      count = 0
      Zip::File.open(@bundle_path) do |zipfile|
        count = zipfile.count
      end
      count
    end
    
    def human_filesize(size)
      units = ['B', 'KB', 'MB', 'GB']
      unit_index = 0
      
      while size > 1024 && unit_index < units.length - 1
        size = size / 1024.0
        unit_index += 1
      end
      
      "%.2f %s" % [size, units[unit_index]]
    end
  end
end