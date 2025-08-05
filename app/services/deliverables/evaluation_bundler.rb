# app/services/deliverables/evaluation_bundler.rb
module Deliverables
  class EvaluationBundler < ApplicationService
    attr_reader :batch_id, :output_dir

    def initialize(batch_id, output_dir: nil)
      @batch_id = batch_id
      @output_dir = output_dir || Rails.root.join('tmp', 'deliverables', "batch_#{batch_id}", 'evaluation_bundles')
      FileUtils.mkdir_p(@output_dir)
    end

    def call
      validate_batch!
      
      {
        test_questions: generate_test_questions,
        expected_answers: generate_expected_answers,
        groundedness_tests: create_groundedness_tests,
        rights_compliance_tests: create_rights_compliance_tests,
        coverage_tests: create_coverage_tests,
        path_accuracy_tests: create_path_accuracy_tests,
        temporal_consistency_tests: create_temporal_consistency_tests,
        evaluation_rubric: generate_evaluation_rubric,
        baseline_scores: calculate_baseline_scores
      }
    end

    def validate
      # Validation method to check bundle integrity
      bundle_valid = true
      errors = []
      
      ['test_questions.json', 'expected_answers.json', 'evaluation_rubric.json'].each do |file|
        filepath = File.join(output_dir, file)
        unless File.exist?(filepath)
          bundle_valid = false
          errors << "Missing required file: #{file}"
        end
      end
      
      if bundle_valid
        questions = JSON.parse(File.read(File.join(output_dir, 'test_questions.json')))
        answers = JSON.parse(File.read(File.join(output_dir, 'expected_answers.json')))
        
        if questions['questions'].count != answers['answers'].count
          bundle_valid = false
          errors << "Question/answer count mismatch"
        end
      end
      
      { valid: bundle_valid, errors: errors }
    end

    private

    def validate_batch!
      batch = IngestBatch.find(batch_id)
      raise "Batch not found" unless batch
      raise "Batch not ready for deliverables" unless batch.literacy_score.to_f >= 70
    end

    def generate_test_questions
      filename = 'test_questions.json'
      filepath = File.join(output_dir, filename)
      
      questions = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        questions: []
      }
      
      # Entity existence questions
      ideas = Idea.where(ingest_batch_id: batch_id).limit(10)
      ideas.each do |idea|
        questions[:questions] << {
          id: "exist_idea_#{idea.id}",
          type: 'entity_existence',
          question: "Does the dataset contain information about '#{idea.canonical_name}'?",
          entity_id: idea.id,
          pool: 'idea',
          difficulty: 'easy'
        }
      end
      
      # Relationship questions
      result = neo4j_query(<<-CYPHER)
        MATCH (a:Idea)-[r]->(b:Manifest)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN a, type(r) as rel_type, b
        LIMIT 10
      CYPHER
      
      result.each do |row|
        questions[:questions] << {
          id: "rel_#{row['a']['id']}_#{row['b']['id']}",
          type: 'relationship',
          question: "What is the relationship between '#{row['a']['canonical_name']}' and '#{row['b']['title']}'?",
          entity_ids: [row['a']['id'], row['b']['id']],
          relationship_type: row['rel_type'],
          difficulty: 'medium'
        }
      end
      
      # Path questions
      result = neo4j_query(<<-CYPHER)
        MATCH path = (a:Idea)-[*2..3]-(b:Experience)
        WHERE a.ingest_batch_id = #{batch_id}
        WITH path, length(path) as len
        ORDER BY len
        LIMIT 5
        RETURN nodes(path) as nodes, relationships(path) as rels
      CYPHER
      
      result.each_with_index do |row, idx|
        start_node = row['nodes'].first
        end_node = row['nodes'].last
        
        questions[:questions] << {
          id: "path_#{idx}",
          type: 'path_finding',
          question: "Find a path connecting '#{start_node['canonical_name'] || start_node['title']}' to '#{end_node['title']}'",
          start_entity_id: start_node['id'],
          end_entity_id: end_node['id'],
          path_length: row['nodes'].count - 1,
          difficulty: 'hard'
        }
      end
      
      # Temporal questions
      experiences = Experience.where(ingest_batch_id: batch_id)
                             .where.not(occurred_at: nil)
                             .order(:occurred_at)
                             .limit(10)
      
      if experiences.count >= 2
        questions[:questions] << {
          id: "temporal_order",
          type: 'temporal',
          question: "Which happened first: '#{experiences.first.title}' or '#{experiences.last.title}'?",
          entity_ids: [experiences.first.id, experiences.last.id],
          difficulty: 'easy'
        }
        
        year = experiences.sample.occurred_at.year
        questions[:questions] << {
          id: "temporal_year_#{year}",
          type: 'temporal',
          question: "What experiences occurred in #{year}?",
          year: year,
          difficulty: 'medium'
        }
      end
      
      # Aggregation questions
      questions[:questions] << {
        id: "count_ideas",
        type: 'aggregation',
        question: "How many unique ideas are in the dataset?",
        pool: 'idea',
        difficulty: 'easy'
      }
      
      questions[:questions] << {
        id: "most_connected",
        type: 'aggregation',
        question: "Which entity has the most relationships?",
        difficulty: 'hard'
      }
      
      File.write(filepath, JSON.pretty_generate(questions))
      
      {
        filename: filename,
        path: filepath,
        question_count: questions[:questions].count
      }
    end

    def generate_expected_answers
      filename = 'expected_answers.json'
      filepath = File.join(output_dir, filename)
      
      # Load questions
      questions_file = File.join(output_dir, 'test_questions.json')
      questions_data = JSON.parse(File.read(questions_file))
      
      answers = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        answers: []
      }
      
      questions_data['questions'].each do |question|
        answer = case question['type']
        when 'entity_existence'
          generate_existence_answer(question)
        when 'relationship'
          generate_relationship_answer(question)
        when 'path_finding'
          generate_path_answer(question)
        when 'temporal'
          generate_temporal_answer(question)
        when 'aggregation'
          generate_aggregation_answer(question)
        else
          { answer: "Unknown question type", confidence: 0 }
        end
        
        answers[:answers] << {
          question_id: question['id'],
          **answer
        }
      end
      
      File.write(filepath, JSON.pretty_generate(answers))
      
      {
        filename: filename,
        path: filepath,
        answer_count: answers[:answers].count
      }
    end

    def create_groundedness_tests
      filename = 'groundedness_tests.json'
      filepath = File.join(output_dir, filename)
      
      tests = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        tests: []
      }
      
      # Test: Can the system cite sources for facts?
      ideas = Idea.where(ingest_batch_id: batch_id).limit(5)
      ideas.each do |idea|
        tests[:tests] << {
          id: "ground_#{idea.id}",
          type: 'citation_required',
          statement: "The idea of #{idea.canonical_name} is part of this dataset",
          required_citations: [
            { entity_id: idea.id, pool: 'idea' }
          ],
          test: "System must cite the specific entity when making this claim"
        }
      end
      
      # Test: Can it distinguish between grounded and speculative statements?
      tests[:tests] << {
        id: "ground_speculative",
        type: 'grounding_distinction',
        grounded_statement: "Based on the data, this idea connects to 5 manifests",
        speculative_statement: "This idea might be related to other concepts not in the dataset",
        test: "System must clearly distinguish grounded from speculative claims"
      }
      
      File.write(filepath, JSON.pretty_generate(tests))
      
      {
        filename: filename,
        path: filepath,
        test_count: tests[:tests].count
      }
    end

    def create_rights_compliance_tests
      filename = 'rights_compliance_tests.json'
      filepath = File.join(output_dir, filename)
      
      tests = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        tests: []
      }
      
      # Test: Respect publishability flags
      public_exp = Experience.where(ingest_batch_id: batch_id, publishability: true).first
      private_exp = Experience.where(ingest_batch_id: batch_id, publishability: false).first
      
      if public_exp
        tests[:tests] << {
          id: "rights_public_#{public_exp.id}",
          type: 'public_content',
          entity_id: public_exp.id,
          expected_behavior: 'can_quote_directly',
          test: "System should be able to quote public content directly"
        }
      end
      
      if private_exp
        tests[:tests] << {
          id: "rights_private_#{private_exp.id}",
          type: 'private_content',
          entity_id: private_exp.id,
          expected_behavior: 'paraphrase_only',
          test: "System must paraphrase private content, not quote directly"
        }
      end
      
      # Test: Training eligibility
      tests[:tests] << {
        id: "rights_training",
        type: 'training_eligibility',
        test: "System should only use training-eligible content for learning",
        check: "Verify embeddings exclude non-eligible content"
      }
      
      File.write(filepath, JSON.pretty_generate(tests))
      
      {
        filename: filename,
        path: filepath,
        test_count: tests[:tests].count
      }
    end

    def create_coverage_tests
      filename = 'coverage_tests.json'
      filepath = File.join(output_dir, filename)
      
      tests = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        tests: []
      }
      
      # Pool coverage tests
      %w[idea manifest experience relational evolutionary practical emanation].each do |pool|
        model = pool.capitalize.constantize
        count = model.where(ingest_batch_id: batch_id).count
        
        tests[:tests] << {
          id: "coverage_#{pool}",
          type: 'pool_coverage',
          pool: pool,
          entity_count: count,
          test_queries: [
            "List all #{pool} entities",
            "How many #{pool} entities exist?",
            "What percentage of the dataset is #{pool}?"
          ],
          expected_coverage: count > 0 ? 1.0 : 0.0
        }
      end
      
      # Relationship coverage
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        RETURN type(r) as rel_type, count(r) as count
        ORDER BY count DESC
      CYPHER
      
      tests[:tests] << {
        id: "coverage_relationships",
        type: 'relationship_coverage',
        relationship_types: result.map { |r| r['rel_type'] },
        test: "System should be aware of all relationship types"
      }
      
      File.write(filepath, JSON.pretty_generate(tests))
      
      {
        filename: filename,
        path: filepath,
        test_count: tests[:tests].count
      }
    end

    def create_path_accuracy_tests
      filename = 'path_accuracy_tests.json'
      filepath = File.join(output_dir, filename)
      
      tests = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        tests: []
      }
      
      # Direct path tests
      result = neo4j_query(<<-CYPHER)
        MATCH (a)-[r]->(b)
        WHERE a.ingest_batch_id = #{batch_id}
        RETURN a, type(r) as rel_type, b, labels(a)[0] as label_a, labels(b)[0] as label_b
        LIMIT 10
      CYPHER
      
      result.each do |row|
        tests[:tests] << {
          id: "path_direct_#{row['a']['id']}_#{row['b']['id']}",
          type: 'direct_path',
          from: {
            id: row['a']['id'],
            pool: row['label_a'].downcase,
            name: row['a']['canonical_name'] || row['a']['title']
          },
          to: {
            id: row['b']['id'],
            pool: row['label_b'].downcase,
            name: row['b']['canonical_name'] || row['b']['title']
          },
          relationship: row['rel_type'],
          test: "Verify direct relationship exists and is correctly typed"
        }
      end
      
      # Multi-hop path tests
      result = neo4j_query(<<-CYPHER)
        MATCH path = (a:Idea)-[*2]-(b:Experience)
        WHERE a.ingest_batch_id = #{batch_id}
        WITH path
        LIMIT 5
        RETURN nodes(path) as nodes, relationships(path) as rels
      CYPHER
      
      result.each_with_index do |row, idx|
        tests[:tests] << {
          id: "path_multi_#{idx}",
          type: 'multi_hop_path',
          nodes: row['nodes'].map { |n| n['id'] },
          relationships: row['rels'].map(&:type),
          length: row['rels'].count,
          test: "Verify multi-hop path is traversable and correctly sequenced"
        }
      end
      
      File.write(filepath, JSON.pretty_generate(tests))
      
      {
        filename: filename,
        path: filepath,
        test_count: tests[:tests].count
      }
    end

    def create_temporal_consistency_tests
      filename = 'temporal_consistency_tests.json'
      filepath = File.join(output_dir, filename)
      
      tests = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        tests: []
      }
      
      # Chronological ordering tests
      experiences = Experience.where(ingest_batch_id: batch_id)
                             .where.not(occurred_at: nil)
                             .order(:occurred_at)
      
      if experiences.count >= 3
        tests[:tests] << {
          id: "temporal_ordering",
          type: 'chronological_order',
          events: experiences.first(5).map { |e|
            { id: e.id, title: e.title, date: e.occurred_at.iso8601 }
          },
          test: "Verify events are correctly ordered chronologically"
        }
      end
      
      # Date consistency tests
      manifests = Manifest.where(ingest_batch_id: batch_id).where.not(year: nil)
      
      manifests.first(5).each do |manifest|
        tests[:tests] << {
          id: "temporal_consistency_#{manifest.id}",
          type: 'date_consistency',
          entity: {
            id: manifest.id,
            title: manifest.title,
            year: manifest.year
          },
          test: "Verify year is consistently reported across queries"
        }
      end
      
      # Temporal range tests
      if experiences.any?
        tests[:tests] << {
          id: "temporal_range",
          type: 'date_range',
          start_date: experiences.minimum(:occurred_at).iso8601,
          end_date: experiences.maximum(:occurred_at).iso8601,
          test: "Verify system correctly identifies temporal boundaries"
        }
      end
      
      File.write(filepath, JSON.pretty_generate(tests))
      
      {
        filename: filename,
        path: filepath,
        test_count: tests[:tests].count
      }
    end

    def generate_evaluation_rubric
      filename = 'evaluation_rubric.json'
      filepath = File.join(output_dir, filename)
      
      rubric = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        criteria: {
          groundedness: {
            weight: 0.25,
            levels: {
              excellent: "All facts cited with correct sources, clear distinction between grounded and speculative",
              good: "Most facts cited, occasional missing citations",
              fair: "Some facts cited, mixing of grounded and speculative",
              poor: "Rarely cites sources, mostly speculative"
            },
            scoring: "Percentage of statements with correct citations"
          },
          rights_compliance: {
            weight: 0.20,
            levels: {
              excellent: "Perfect compliance with publishability and training eligibility",
              good: "Minor violations, quickly corrected",
              fair: "Occasional violations, some awareness of rights",
              poor: "Frequent violations, little rights awareness"
            },
            scoring: "Percentage of rights-respecting responses"
          },
          coverage: {
            weight: 0.20,
            levels: {
              excellent: "Can answer >90% of coverage questions accurately",
              good: "Can answer 70-90% of coverage questions",
              fair: "Can answer 50-70% of coverage questions",
              poor: "Can answer <50% of coverage questions"
            },
            scoring: "Percentage of entities and relationships accessible"
          },
          path_accuracy: {
            weight: 0.15,
            levels: {
              excellent: "All paths correctly traced with accurate relationships",
              good: "Most paths correct, minor relationship errors",
              fair: "Some paths correct, frequent relationship confusion",
              poor: "Paths often incorrect or incomplete"
            },
            scoring: "Percentage of correctly identified paths and relationships"
          },
          temporal_consistency: {
            weight: 0.10,
            levels: {
              excellent: "Perfect chronological ordering and date consistency",
              good: "Minor date errors, generally correct ordering",
              fair: "Some date confusion, ordering mostly correct",
              poor: "Frequent date errors and chronological confusion"
            },
            scoring: "Percentage of correct temporal assertions"
          },
          response_quality: {
            weight: 0.10,
            levels: {
              excellent: "Clear, complete, well-structured responses",
              good: "Generally clear, minor structural issues",
              fair: "Somewhat unclear, needs improvement",
              poor: "Unclear, incomplete, poorly structured"
            },
            scoring: "Subjective assessment of response quality"
          }
        },
        scoring_guide: {
          excellent: "90-100 points",
          good: "70-89 points",
          fair: "50-69 points",
          poor: "Below 50 points"
        },
        minimum_passing_score: 70
      }
      
      File.write(filepath, JSON.pretty_generate(rubric))
      
      {
        filename: filename,
        path: filepath
      }
    end

    def calculate_baseline_scores
      filename = 'baseline_scores.json'
      filepath = File.join(output_dir, filename)
      
      batch = IngestBatch.find(batch_id)
      
      scores = {
        version: '1.0.0',
        generated_at: Time.current.iso8601,
        batch_id: batch_id,
        literacy_score: batch.literacy_score,
        baseline_metrics: {
          entity_count: count_all_entities,
          relationship_count: count_all_relationships,
          path_connectivity: calculate_connectivity,
          temporal_coverage: calculate_temporal_coverage,
          rights_coverage: calculate_rights_coverage
        },
        expected_performance: {
          groundedness: estimate_groundedness_score,
          rights_compliance: estimate_rights_compliance,
          coverage: estimate_coverage_score,
          path_accuracy: estimate_path_accuracy,
          temporal_consistency: estimate_temporal_consistency,
          overall: calculate_overall_baseline
        },
        notes: "Baseline scores represent expected performance based on dataset characteristics"
      }
      
      File.write(filepath, JSON.pretty_generate(scores))
      
      {
        filename: filename,
        path: filepath,
        scores: scores
      }
    end

    # Helper methods for answer generation
    def generate_existence_answer(question)
      entity = question['pool'].capitalize.constantize.find_by(id: question['entity_id'])
      
      {
        answer: entity ? "Yes" : "No",
        confidence: 1.0,
        grounding: entity ? [{ entity_id: entity.id, pool: question['pool'] }] : []
      }
    end

    def generate_relationship_answer(question)
      {
        answer: question['relationship_type'],
        confidence: 1.0,
        grounding: question['entity_ids'].map { |id| { entity_id: id } }
      }
    end

    def generate_path_answer(question)
      result = neo4j_query(<<-CYPHER)
        MATCH path = shortestPath((a {id: '#{question['start_entity_id']}'})-[*..5]-(b {id: '#{question['end_entity_id']}'}))
        RETURN nodes(path) as nodes, relationships(path) as rels
        LIMIT 1
      CYPHER
      
      if result.any?
        nodes = result.first['nodes'].map { |n| n['id'] }
        rels = result.first['rels'].map(&:type)
        
        {
          answer: "Path exists with #{nodes.count - 1} hops",
          path: nodes,
          relationships: rels,
          confidence: 1.0
        }
      else
        {
          answer: "No path found within 5 hops",
          confidence: 1.0
        }
      end
    end

    def generate_temporal_answer(question)
      case question['question']
      when /Which happened first/
        exp1 = Experience.find(question['entity_ids'][0])
        exp2 = Experience.find(question['entity_ids'][1])
        
        first = exp1.occurred_at < exp2.occurred_at ? exp1 : exp2
        
        {
          answer: first.title,
          confidence: 1.0,
          grounding: [{ entity_id: first.id, date: first.occurred_at.iso8601 }]
        }
      when /What experiences occurred in/
        year = question['year']
        experiences = Experience.where(ingest_batch_id: batch_id)
                               .where('extract(year from occurred_at) = ?', year)
        
        {
          answer: experiences.map(&:title),
          count: experiences.count,
          confidence: 1.0,
          grounding: experiences.map { |e| { entity_id: e.id, date: e.occurred_at.iso8601 } }
        }
      else
        { answer: "Unknown temporal question format", confidence: 0 }
      end
    end

    def generate_aggregation_answer(question)
      case question['question']
      when /How many unique ideas/
        count = Idea.where(ingest_batch_id: batch_id).count
        { answer: count, confidence: 1.0 }
      when /Which entity has the most relationships/
        result = neo4j_query(<<-CYPHER)
          MATCH (n)
          WHERE n.ingest_batch_id = #{batch_id}
          WITH n, size((n)-[]-()) as degree
          ORDER BY degree DESC
          LIMIT 1
          RETURN n, degree, labels(n)[0] as pool
        CYPHER
        
        if result.any?
          node = result.first['n']
          {
            answer: node['title'] || node['canonical_name'],
            entity_id: node['id'],
            relationship_count: result.first['degree'],
            confidence: 1.0
          }
        else
          { answer: "No entities found", confidence: 0 }
        end
      else
        { answer: "Unknown aggregation question format", confidence: 0 }
      end
    end

    # Helper methods for metrics calculation
    def count_all_entities
      %w[Idea Manifest Experience Relational Evolutionary Practical Emanation].sum do |pool|
        pool.constantize.where(ingest_batch_id: batch_id).count
      end
    end

    def count_all_relationships
      result = neo4j_query(<<-CYPHER)
        MATCH ()-[r]->()
        WHERE startNode(r).ingest_batch_id = #{batch_id}
        RETURN count(r) as count
      CYPHER
      
      result.first['count'] || 0
    end

    def calculate_connectivity
      nodes = count_all_entities
      relationships = count_all_relationships
      
      return 0 if nodes < 2
      
      max_possible = nodes * (nodes - 1)
      (relationships.to_f / max_possible * 100).round(2)
    end

    def calculate_temporal_coverage
      total = Experience.where(ingest_batch_id: batch_id).count
      with_dates = Experience.where(ingest_batch_id: batch_id).where.not(occurred_at: nil).count
      
      return 0 if total == 0
      
      (with_dates.to_f / total * 100).round(2)
    end

    def calculate_rights_coverage
      total = count_all_entities
      with_rights = ProvenanceAndRights.where(ingest_batch_id: batch_id).count
      
      return 0 if total == 0
      
      (with_rights.to_f / total * 100).round(2)
    end

    def estimate_groundedness_score
      # Estimate based on entity count and relationships
      entity_factor = [count_all_entities / 100.0, 1.0].min
      relationship_factor = [count_all_relationships / 500.0, 1.0].min
      
      (((entity_factor + relationship_factor) / 2) * 100).round(2)
    end

    def estimate_rights_compliance
      calculate_rights_coverage
    end

    def estimate_coverage_score
      # Based on literacy score
      batch = IngestBatch.find(batch_id)
      batch.literacy_score || 70
    end

    def estimate_path_accuracy
      connectivity = calculate_connectivity
      [connectivity * 2, 95].min
    end

    def estimate_temporal_consistency
      calculate_temporal_coverage
    end

    def calculate_overall_baseline
      scores = [
        estimate_groundedness_score * 0.25,
        estimate_rights_compliance * 0.20,
        estimate_coverage_score * 0.20,
        estimate_path_accuracy * 0.15,
        estimate_temporal_consistency * 0.10,
        75 * 0.10  # Default response quality
      ]
      
      scores.sum.round(2)
    end

    def neo4j_query(cypher)
      Rails.configuration.neo4j_driver.session do |session|
        session.run(cypher).to_a
      end
    end
  end
end