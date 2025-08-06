# app/services/meta_enliteration/evidence_extractor.rb
# Extracts Evidence entities from test outputs, CI logs, and performance metrics
# Evidence pool captures primary data (measurements, logs) vs Experience (subjective/lived)

module MetaEnliteration
  class EvidenceExtractor < ApplicationService
    
    attr_reader :batch, :evidence_entities
    
    # Patterns to identify evidence-type content
    TEST_OUTPUT_PATTERNS = {
      rspec: /(\d+) examples?, (\d+) failures?/,
      minitest: /(\d+) runs?, (\d+) assertions?, (\d+) failures?/,
      junit: /<testsuite.*tests="(\d+)".*failures="(\d+)"/,
      coverage: /Coverage report generated.*\((\d+\.?\d*)\%\) covered/,
      performance: /Completed (\d+) requests? in (\d+\.?\d*)ms/,
      memory: /Memory usage: (\d+\.?\d*) MB/,
      cpu: /CPU usage: (\d+\.?\d*)%/
    }.freeze
    
    CI_LOG_PATTERNS = {
      build_success: /Build #(\d+) succeeded/,
      build_failure: /Build #(\d+) failed/,
      deployment: /Deployed to (production|staging|development)/,
      artifact: /Artifact created: ([\w\-\.]+)/,
      docker: /Successfully built ([a-f0-9]{12})/,
      npm: /added (\d+) packages?/,
      bundle: /Bundle complete! (\d+) Gemfile dependencies/
    }.freeze
    
    METRIC_PATTERNS = {
      response_time: /p95: (\d+)ms/,
      throughput: /(\d+) req\/s/,
      error_rate: /Error rate: (\d+\.?\d*)%/,
      uptime: /Uptime: (\d+\.?\d*)%/,
      database: /Query time: (\d+\.?\d*)ms/
    }.freeze
    
    def initialize(batch)
      @batch = batch
      @evidence_entities = []
      @verb_mapper = VerbMapper.new(nil)
    end
    
    def call
      extract_test_results
      extract_ci_logs
      extract_performance_metrics
      extract_code_metrics
      create_evidence_relationships
      
      {
        success: true,
        count: @evidence_entities.count,
        entities: @evidence_entities,
        categories: categorize_evidence
      }
    rescue => e
      {
        success: false,
        error: e.message,
        backtrace: e.backtrace
      }
    end
    
    private
    
    def extract_test_results
      # Look for test output files
      test_files = batch.raw_documents.where("file_path LIKE ?", "%test%")
      
      test_files.each do |doc|
        content = doc.content
        next unless content
        
        # Extract RSpec results
        if match = content.match(TEST_OUTPUT_PATTERNS[:rspec])
          @evidence_entities << {
            pool: 'Evidence',
            type: 'test_result',
            subtype: 'rspec',
            title: "RSpec Test Run - #{doc.file_path}",
            data: {
              examples: match[1].to_i,
              failures: match[2].to_i,
              success_rate: calculate_success_rate(match[1].to_i, match[2].to_i)
            },
            observed_at: doc.created_at,
            source_document_id: doc.id,
            repr_text: "Test: #{match[1]} examples, #{match[2]} failures"
          }
        end
        
        # Extract coverage data
        if match = content.match(TEST_OUTPUT_PATTERNS[:coverage])
          @evidence_entities << {
            pool: 'Evidence',
            type: 'coverage_metric',
            subtype: 'code_coverage',
            title: "Code Coverage Report",
            data: {
              coverage_percentage: match[1].to_f,
              threshold_met: match[1].to_f >= 80.0
            },
            observed_at: doc.created_at,
            source_document_id: doc.id,
            repr_text: "Coverage: #{match[1]}%"
          }
        end
      end
    end
    
    def extract_ci_logs
      # Look for CI/CD logs
      ci_files = batch.raw_documents.where("file_path LIKE ? OR file_path LIKE ?", "%ci%", "%build%")
      
      ci_files.each do |doc|
        content = doc.content
        next unless content
        
        CI_LOG_PATTERNS.each do |pattern_name, pattern|
          content.scan(pattern) do |match|
            @evidence_entities << {
              pool: 'Evidence',
              type: 'ci_artifact',
              subtype: pattern_name.to_s,
              title: "CI #{pattern_name.to_s.humanize}",
              data: extract_ci_data(pattern_name, match),
              observed_at: doc.created_at,
              source_document_id: doc.id,
              repr_text: "CI: #{pattern_name} - #{match.first}"
            }
          end
        end
      end
    end
    
    def extract_performance_metrics
      # Look for performance logs and metrics
      perf_files = batch.raw_documents.where(
        "file_path LIKE ? OR file_path LIKE ? OR content LIKE ?",
        "%performance%", "%metrics%", "%benchmark%"
      )
      
      perf_files.each do |doc|
        content = doc.content
        next unless content
        
        METRIC_PATTERNS.each do |metric_name, pattern|
          if match = content.match(pattern)
            @evidence_entities << {
              pool: 'Evidence',
              type: 'performance_metric',
              subtype: metric_name.to_s,
              title: "Performance: #{metric_name.to_s.humanize}",
              data: {
                value: match[1],
                unit: infer_unit(metric_name)
              },
              observed_at: doc.created_at,
              source_document_id: doc.id,
              repr_text: "Metric: #{metric_name} = #{match[1]}#{infer_unit(metric_name)}"
            }
          end
        end
      end
    end
    
    def extract_code_metrics
      # Extract static code analysis metrics
      analyze_complexity
      analyze_dependencies
      analyze_code_quality
    end
    
    def analyze_complexity
      # Analyze cyclomatic complexity of Ruby files
      ruby_files = batch.raw_documents.where("file_path LIKE ?", "%.rb")
      
      ruby_files.each do |doc|
        next unless doc.content
        
        complexity = calculate_cyclomatic_complexity(doc.content)
        loc = doc.content.lines.count
        
        @evidence_entities << {
          pool: 'Evidence',
          type: 'code_metric',
          subtype: 'complexity',
          title: "Code Complexity - #{File.basename(doc.file_path)}",
          data: {
            cyclomatic_complexity: complexity,
            lines_of_code: loc,
            complexity_per_line: (complexity.to_f / loc).round(3)
          },
          observed_at: doc.created_at,
          source_document_id: doc.id,
          repr_text: "Complexity: #{complexity} (#{loc} LOC)"
        }
      end
    end
    
    def analyze_dependencies
      # Extract dependency information from Gemfile.lock
      gemfile_lock = batch.raw_documents.find_by(file_path: "Gemfile.lock")
      
      if gemfile_lock && gemfile_lock.content
        gems = extract_gems(gemfile_lock.content)
        
        @evidence_entities << {
          pool: 'Evidence',
          type: 'dependency_analysis',
          subtype: 'ruby_gems',
          title: "Dependency Analysis",
          data: {
            total_dependencies: gems.count,
            direct_dependencies: count_direct_deps(gems),
            security_advisories: check_security_advisories(gems)
          },
          observed_at: gemfile_lock.created_at,
          source_document_id: gemfile_lock.id,
          repr_text: "Dependencies: #{gems.count} gems"
        }
      end
    end
    
    def analyze_code_quality
      # Run basic quality checks
      quality_metrics = {
        todo_count: count_todos,
        fixme_count: count_fixmes,
        deprecated_count: count_deprecated,
        rubocop_violations: count_rubocop_violations
      }
      
      @evidence_entities << {
        pool: 'Evidence',
        type: 'code_quality',
        subtype: 'static_analysis',
        title: "Code Quality Metrics",
        data: quality_metrics,
        observed_at: Time.current,
        repr_text: "Quality: #{quality_metrics[:todo_count]} TODOs, #{quality_metrics[:rubocop_violations]} violations"
      }
    end
    
    def create_evidence_relationships
      @evidence_entities.each do |evidence|
        # Evidence validates Practical (test code)
        if evidence[:type] == 'test_result'
          create_validation_relationship(evidence)
        end
        
        # Evidence supports or refutes Ideas
        if evidence[:type] == 'performance_metric'
          create_support_relationship(evidence)
        end
        
        # Evidence measures Manifest
        if evidence[:type] == 'code_metric'
          create_measurement_relationship(evidence)
        end
      end
    end
    
    def create_validation_relationship(evidence)
      # Find related Practical entity (test file)
      practical = find_practical_entity(evidence[:source_document_id])
      
      if practical
        evidence[:relationships] ||= []
        evidence[:relationships] << {
          verb: 'validates',
          target_pool: 'Practical',
          target_id: practical[:id],
          confidence: 0.9
        }
      end
    end
    
    def create_support_relationship(evidence)
      # Performance evidence supports architectural Ideas
      if evidence[:data][:value].to_f > threshold_for(evidence[:subtype])
        evidence[:relationships] ||= []
        evidence[:relationships] << {
          verb: 'supports',
          target_pool: 'Idea',
          target_label: 'Performance Optimization',
          confidence: 0.8
        }
      end
    end
    
    def create_measurement_relationship(evidence)
      # Code metrics measure Manifest entities
      manifest = find_manifest_entity(evidence[:source_document_id])
      
      if manifest
        evidence[:relationships] ||= []
        evidence[:relationships] << {
          verb: 'measures',
          target_pool: 'Manifest',
          target_id: manifest[:id],
          confidence: 0.95
        }
      end
    end
    
    def calculate_success_rate(total, failures)
      return 100.0 if total == 0
      ((total - failures).to_f / total * 100).round(2)
    end
    
    def calculate_cyclomatic_complexity(content)
      # Simple heuristic: count decision points
      complexity = 1
      complexity += content.scan(/\bif\b/).count
      complexity += content.scan(/\bunless\b/).count
      complexity += content.scan(/\bwhile\b/).count
      complexity += content.scan(/\bfor\b/).count
      complexity += content.scan(/\bcase\b/).count
      complexity += content.scan(/\brescue\b/).count
      complexity += content.scan(/\&\&/).count
      complexity += content.scan(/\|\|/).count
      complexity
    end
    
    def extract_gems(gemfile_content)
      gems = []
      gemfile_content.scan(/^\s{4}(\w+)\s+\(([^)]+)\)/) do |name, version|
        gems << { name: name, version: version }
      end
      gems
    end
    
    def count_direct_deps(gems)
      # Heuristic: gems with shorter names are usually direct deps
      gems.count { |g| g[:name].length < 15 }
    end
    
    def check_security_advisories(gems)
      # Placeholder - would check against vulnerability database
      0
    end
    
    def count_todos
      batch.raw_documents.sum do |doc|
        doc.content ? doc.content.scan(/TODO|FIXME/).count : 0
      end
    end
    
    def count_fixmes
      batch.raw_documents.sum do |doc|
        doc.content ? doc.content.scan(/FIXME/).count : 0
      end
    end
    
    def count_deprecated
      batch.raw_documents.sum do |doc|
        doc.content ? doc.content.scan(/deprecated|DEPRECATED/).count : 0
      end
    end
    
    def count_rubocop_violations
      # Placeholder - would run rubocop
      0
    end
    
    def extract_ci_data(pattern_name, match)
      case pattern_name
      when :build_success, :build_failure
        { build_number: match[0].to_i }
      when :deployment
        { environment: match[0] }
      when :artifact
        { artifact_name: match[0] }
      when :docker
        { image_id: match[0] }
      when :npm
        { package_count: match[0].to_i }
      when :bundle
        { dependency_count: match[0].to_i }
      else
        { raw_value: match[0] }
      end
    end
    
    def infer_unit(metric_name)
      case metric_name
      when :response_time, :database
        'ms'
      when :throughput
        'req/s'
      when :error_rate, :uptime
        '%'
      else
        ''
      end
    end
    
    def threshold_for(metric_type)
      case metric_type
      when 'response_time'
        100  # ms
      when 'throughput'
        100  # req/s
      when 'uptime'
        99   # %
      else
        0
      end
    end
    
    def find_practical_entity(source_doc_id)
      # Placeholder - would look up related Practical entity
      nil
    end
    
    def find_manifest_entity(source_doc_id)
      # Placeholder - would look up related Manifest entity
      nil
    end
    
    def categorize_evidence
      categories = @evidence_entities.group_by { |e| e[:type] }
      categories.transform_values(&:count)
    end
  end
end