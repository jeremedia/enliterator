# frozen_string_literal: true

# TrainingQuestionGenerator - Generates domain-specific training questions from EKN knowledge graphs
#
# Analyzes an EKN's actual knowledge content to generate relevant training questions.
# Each question tests specific archetype capabilities and domain understanding.
#
# Usage:
#   generator = TrainingQuestionGenerator.new(ekn)
#   question_set = generator.generate_question_set
#
class TrainingQuestionGenerator
  attr_reader :ekn, :knowledge_analysis
  
  def initialize(ekn)
    @ekn = ekn
    @knowledge_analysis = nil
  end
  
  def generate_question_set(options = {})
    Rails.logger.info "Generating training questions for EKN #{ekn.id} (#{ekn.slug})"
    
    # Analyze the knowledge graph
    @knowledge_analysis = analyze_knowledge_graph
    
    # Create the question set
    question_set = create_question_set(options)
    
    # Generate different types of questions
    questions_generated = 0
    questions_generated += generate_meta_navigation_questions(question_set)
    questions_generated += generate_framework_questions(question_set)
    questions_generated += generate_domain_specific_questions(question_set)
    questions_generated += generate_relationship_questions(question_set)
    questions_generated += generate_architectural_questions(question_set)
    questions_generated += generate_process_questions(question_set)
    
    # Update question count
    question_set.update_question_count!
    
    Rails.logger.info "Generated #{questions_generated} training questions for #{ekn.slug}"
    
    question_set
  end
  
  private
  
  def analyze_knowledge_graph
    return { error: "No Neo4j database" } unless ekn.neo4j_database_exists?
    
    begin
      session = Graph::Connection.instance.driver.session(database: ekn.neo4j_database_name)
      
      # Get pool distribution
      pool_query = "MATCH (n) WITH labels(n)[0] as pool, count(n) as count RETURN pool, count ORDER BY count DESC"
      pool_results = session.run(pool_query).map { |r| [r[:pool], r[:count]] }.to_h
      
      # Get sample entities from each significant pool
      pool_samples = {}
      pool_results.select { |pool, count| count > 5 }.each do |pool, _count|
        sample_query = "MATCH (n:#{pool}) RETURN n.label as name LIMIT 10"
        samples = session.run(sample_query).map { |r| r[:name] }.compact.reject(&:empty?)
        pool_samples[pool] = samples if samples.any?
      end
      
      # Get relationship types
      rel_query = "MATCH ()-[r]->() WITH type(r) as rel_type, count(r) as count RETURN rel_type, count ORDER BY count DESC LIMIT 10"
      relationship_types = session.run(rel_query).map { |r| [r[:rel_type], r[:count]] }.to_h
      
      # Get some entity-relationship patterns
      pattern_query = "MATCH (a)-[r]->(b) RETURN labels(a)[0] as source_type, type(r) as rel, labels(b)[0] as target_type, count(*) as freq ORDER BY freq DESC LIMIT 15"
      patterns = session.run(pattern_query).map do |r|
        {
          source: r[:source_type],
          relationship: r[:rel], 
          target: r[:target_type],
          frequency: r[:freq]
        }
      end
      
      session.close
      
      {
        pool_distribution: pool_results,
        pool_samples: pool_samples,
        relationship_types: relationship_types,
        relationship_patterns: patterns,
        total_nodes: pool_results.values.sum,
        total_relationships: relationship_types.values.sum,
        dominant_pools: pool_results.keys.first(3),
        complexity_score: calculate_complexity_score(pool_results, relationship_types)
      }
      
    rescue => e
      Rails.logger.error "Error analyzing knowledge graph for EKN #{ekn.id}: #{e.message}"
      { error: e.message }
    end
  end
  
  def calculate_complexity_score(pools, relationships)
    node_count = pools.values.sum
    rel_count = relationships.values.sum
    pool_diversity = pools.keys.size
    rel_diversity = relationships.keys.size
    
    # Simple complexity formula
    ((node_count * 0.1) + (rel_count * 0.2) + (pool_diversity * 5) + (rel_diversity * 3)).round(2)
  end
  
  def create_question_set(options)
    set_name = options[:name] || "Auto-generated questions for #{ekn.name}"
    
    TrainingQuestionSet.create!(
      ekn: ekn,
      name: set_name,
      description: "Questions generated from knowledge graph analysis on #{Time.current.strftime('%Y-%m-%d')}",
      generation_method: :knowledge_graph,
      generation_metadata: {
        knowledge_snapshot: @knowledge_analysis,
        generated_at: Time.current.iso8601,
        node_count: @knowledge_analysis[:total_nodes],
        relationship_count: @knowledge_analysis[:total_relationships],
        pools_analyzed: @knowledge_analysis[:dominant_pools],
        complexity_score: @knowledge_analysis[:complexity_score]
      },
      status: :active
    )
  end
  
  def generate_meta_navigation_questions(question_set)
    return 0 if @knowledge_analysis[:error]
    
    questions = []
    
    # Questions about overall navigation and understanding
    if @knowledge_analysis[:dominant_pools].any?
      pools = @knowledge_analysis[:dominant_pools].first(3).join(', ')
      questions << {
        text: "How should I navigate this knowledge base to understand the relationship between #{pools}?",
        type: :meta_navigation,
        archetype: :master_navigator,
        difficulty: :medium,
        areas: @knowledge_analysis[:dominant_pools],
        source: { pools: @knowledge_analysis[:dominant_pools], reason: 'dominant_pools' }
      }
    end
    
    # Questions about knowledge organization
    total_concepts = @knowledge_analysis[:total_nodes]
    if total_concepts > 100
      questions << {
        text: "What are the most important concepts I should understand first in this #{total_concepts}-item knowledge base?",
        type: :meta_navigation,
        archetype: :master_navigator,
        difficulty: :easy,
        areas: ['knowledge_organization', 'prioritization'],
        source: { node_count: total_concepts, reason: 'knowledge_scale' }
      }
    end
    
    # Questions about knowledge completeness
    if @knowledge_analysis[:pool_distribution].any?
      questions << {
        text: "What gaps or limitations should I be aware of in this knowledge base?",
        type: :meta_navigation,
        archetype: :master_navigator,
        difficulty: :hard,
        areas: ['knowledge_gaps', 'limitations'],
        source: { pools: @knowledge_analysis[:pool_distribution], reason: 'completeness_assessment' }
      }
    end
    
    create_training_questions(question_set, questions)
  end
  
  def generate_framework_questions(question_set)
    return 0 if @knowledge_analysis[:error]
    
    questions = []
    
    # Questions about the framework/system being described
    @knowledge_analysis[:pool_samples].each do |pool, samples|
      next unless samples.size > 3
      
      # Pick interesting samples for questions
      sample_concepts = samples.first(3)
      
      questions << {
        text: "How do #{sample_concepts.join(', ')} fit into the overall #{pool} framework?",
        type: :framework_understanding,
        archetype: :master_navigator,
        difficulty: :medium,
        areas: [pool.downcase, 'framework_integration'],
        source: { pool: pool, concepts: sample_concepts, reason: 'framework_integration' }
      }
      
      if samples.size > 5
        questions << {
          text: "What are the key principles that govern #{pool} in this system?",
          type: :framework_understanding,
          archetype: :domain_specialist,
          difficulty: :hard,
          areas: [pool.downcase, 'principles'],
          source: { pool: pool, sample_size: samples.size, reason: 'principle_extraction' }
        }
      end
    end
    
    create_training_questions(question_set, questions)
  end
  
  def generate_domain_specific_questions(question_set)
    return 0 if @knowledge_analysis[:error]
    
    questions = []
    
    # Generate questions about specific entities and concepts
    @knowledge_analysis[:pool_samples].each do |pool, samples|
      next unless samples.size > 2
      
      # Pick specific entities for detailed questions
      samples.first(3).each do |entity|
        next if entity.nil? || entity.empty?
        
        questions << {
          text: "What is #{entity} and why is it important in this domain?",
          type: :domain_specific,
          archetype: :domain_specialist,
          difficulty: :easy,
          areas: [pool.downcase, entity.downcase.gsub(/\s+/, '_')],
          source: { pool: pool, entity: entity, reason: 'entity_explanation' }
        }
        
        questions << {
          text: "How does #{entity} connect to other concepts in the system?",
          type: :domain_specific,
          archetype: :relationship_mapper,
          difficulty: :medium,
          areas: [pool.downcase, 'relationships'],
          source: { pool: pool, entity: entity, reason: 'entity_connections' }
        }
      end
      
      # Comparative questions
      if samples.size >= 2
        entity1, entity2 = samples.first(2)
        questions << {
          text: "Compare and contrast #{entity1} and #{entity2} - how are they similar and different?",
          type: :domain_specific,
          archetype: :precision_analyst,
          difficulty: :medium,
          areas: [pool.downcase, 'comparison'],
          source: { pool: pool, entities: [entity1, entity2], reason: 'comparison' }
        }
      end
    end
    
    create_training_questions(question_set, questions.first(15)) # Limit domain questions
  end
  
  def generate_relationship_questions(question_set)
    return 0 if @knowledge_analysis[:error] || @knowledge_analysis[:relationship_patterns].empty?
    
    questions = []
    
    # Questions about relationship patterns
    @knowledge_analysis[:relationship_patterns].first(5).each do |pattern|
      questions << {
        text: "What does it mean when #{pattern[:source]} #{pattern[:relationship]} #{pattern[:target]}?",
        type: :relationship_mapping,
        archetype: :relationship_mapper,
        difficulty: :medium,
        areas: [pattern[:source].downcase, pattern[:target].downcase, 'relationships'],
        source: { pattern: pattern, reason: 'relationship_pattern' }
      }
      
      if pattern[:frequency] > 5
        questions << {
          text: "Why is the #{pattern[:source]} → #{pattern[:relationship]} → #{pattern[:target]} pattern so common in this domain?",
          type: :relationship_mapping,
          archetype: :data_detective,
          difficulty: :hard,
          areas: [pattern[:source].downcase, 'patterns', 'frequency_analysis'],
          source: { pattern: pattern, frequency: pattern[:frequency], reason: 'pattern_frequency' }
        }
      end
    end
    
    # Network-level questions
    if @knowledge_analysis[:relationship_types].size > 5
      questions << {
        text: "What are the most important types of relationships in this knowledge network?",
        type: :relationship_mapping,
        archetype: :relationship_mapper,
        difficulty: :medium,
        areas: ['network_analysis', 'relationship_types'],
        source: { relationship_types: @knowledge_analysis[:relationship_types], reason: 'network_analysis' }
      }
    end
    
    create_training_questions(question_set, questions)
  end
  
  def generate_architectural_questions(question_set)
    return 0 if @knowledge_analysis[:error]
    
    questions = []
    
    # Questions about system architecture and structure
    complexity = @knowledge_analysis[:complexity_score]
    
    if complexity > 50
      questions << {
        text: "How is this system architecturally organized? What are the main structural components?",
        type: :architectural_knowledge,
        archetype: :systematic_explorer,
        difficulty: :hard,
        areas: ['architecture', 'system_structure'],
        source: { complexity_score: complexity, reason: 'architectural_complexity' }
      }
    end
    
    # Questions about pool organization
    if @knowledge_analysis[:pool_distribution].size > 3
      questions << {
        text: "Why is this knowledge organized into these specific categories? What's the organizing principle?",
        type: :architectural_knowledge,
        archetype: :systematic_explorer,
        difficulty: :medium,
        areas: ['knowledge_organization', 'categorization'],
        source: { pool_count: @knowledge_analysis[:pool_distribution].size, reason: 'organizational_structure' }
      }
    end
    
    create_training_questions(question_set, questions)
  end
  
  def generate_process_questions(question_set)
    return 0 if @knowledge_analysis[:error]
    
    questions = []
    
    # Look for process-related content
    if @knowledge_analysis[:pool_samples]['Practical']&.any?
      practical_items = @knowledge_analysis[:pool_samples]['Practical'].first(3)
      
      practical_items.each do |item|
        next if item.nil? || item.empty?
        
        questions << {
          text: "Walk me through the #{item} process step by step.",
          type: :process_understanding,
          archetype: :systematic_explorer,
          difficulty: :medium,
          areas: ['practical', 'processes'],
          source: { pool: 'Practical', item: item, reason: 'process_explanation' }
        }
      end
    end
    
    # Troubleshooting questions
    if @knowledge_analysis[:total_nodes] > 200
      questions << {
        text: "What would you do if you couldn't find the information you were looking for in this knowledge base?",
        type: :troubleshooting,
        archetype: :data_detective,
        difficulty: :hard,
        areas: ['troubleshooting', 'search_strategies'],
        source: { knowledge_scale: @knowledge_analysis[:total_nodes], reason: 'troubleshooting' }
      }
    end
    
    create_training_questions(question_set, questions)
  end
  
  def create_training_questions(question_set, question_data)
    return 0 if question_data.empty?
    
    created_count = 0
    
    question_data.each do |q_data|
      begin
        TrainingQuestion.create!(
          training_question_set: question_set,
          ekn: ekn,
          question_text: q_data[:text],
          question_type: q_data[:type],
          archetype_focus: q_data[:archetype],
          difficulty_level: q_data[:difficulty],
          expected_knowledge_areas: q_data[:areas] || [],
          generation_source: q_data[:source] || {},
          evaluation_criteria: build_evaluation_criteria(q_data),
          ideal_response_outline: build_ideal_response_outline(q_data)
        )
        created_count += 1
      rescue => e
        Rails.logger.error "Failed to create training question: #{e.message}"
        Rails.logger.error "Question data: #{q_data.inspect}"
      end
    end
    
    created_count
  end
  
  def build_evaluation_criteria(q_data)
    base_criteria = {
      accuracy: "Response should be factually correct based on knowledge graph",
      completeness: "Response should address all aspects of the question", 
      personality_authenticity: "Response should reflect the #{q_data[:archetype]} archetype characteristics"
    }
    
    case q_data[:type]
    when :meta_navigation
      base_criteria[:guidance_quality] = "Should provide helpful navigation guidance"
    when :framework_understanding
      base_criteria[:framework_coherence] = "Should demonstrate understanding of system architecture"
    when :domain_specific
      base_criteria[:domain_expertise] = "Should show deep understanding of domain concepts"
    when :relationship_mapping
      base_criteria[:relationship_accuracy] = "Should correctly identify and explain relationships"
    when :architectural_knowledge
      base_criteria[:structural_understanding] = "Should demonstrate grasp of system structure"
    when :process_understanding
      base_criteria[:process_clarity] = "Should explain processes clearly and completely"
    end
    
    base_criteria
  end
  
  def build_ideal_response_outline(q_data)
    case q_data[:type]
    when :meta_navigation
      "Should provide: 1) Overview of navigation approach, 2) Key areas to focus on, 3) Suggested exploration path, 4) Relevant connections to highlight"
    when :framework_understanding  
      "Should explain: 1) Core framework concepts, 2) How components fit together, 3) Underlying principles, 4) Practical applications"
    when :domain_specific
      "Should cover: 1) Clear definition/explanation, 2) Context and importance, 3) Related concepts, 4) Practical implications"
    when :relationship_mapping
      "Should describe: 1) Nature of relationships, 2) Connection patterns, 3) Implications of connections, 4) Related network effects"
    when :architectural_knowledge
      "Should address: 1) Structural organization, 2) Design principles, 3) Component interactions, 4) Architectural decisions"
    when :process_understanding
      "Should outline: 1) Process steps, 2) Dependencies and prerequisites, 3) Expected outcomes, 4) Potential issues"
    else
      "Should provide comprehensive, accurate response appropriate to question type"
    end
  end
end