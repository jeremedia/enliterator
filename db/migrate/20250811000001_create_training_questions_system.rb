# frozen_string_literal: true

class CreateTrainingQuestionsSystem < ActiveRecord::Migration[8.0]
  def change
    # Training Question Sets - groups of questions for an EKN
    create_table :training_question_sets, if_not_exists: true do |t|
      t.references :ekn, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :generation_method, null: false # 'knowledge_graph', 'manual', 'ai_generated'
      t.json :generation_metadata, default: {}
      t.string :status, default: 'pending' # 'pending', 'active', 'archived'
      t.integer :question_count, default: 0
      t.timestamps
      
      t.index [:ekn_id, :name], unique: true
      t.index :generation_method
      t.index :status
    end
    
    # Individual training questions
    create_table :training_questions, if_not_exists: true do |t|
      t.references :training_question_set, null: false, foreign_key: true
      t.references :ekn, null: false, foreign_key: true
      t.text :question_text, null: false
      t.string :question_type, null: false # 'meta_navigation', 'framework_understanding', 'domain_specific', 'relationship_mapping'
      t.string :archetype_focus # Which archetype should excel at this question
      t.string :difficulty_level, default: 'medium' # 'easy', 'medium', 'hard', 'expert'
      t.json :expected_knowledge_areas, default: [] # Which parts of knowledge graph should be referenced
      t.json :generation_source, default: {} # What knowledge led to this question
      t.json :evaluation_criteria, default: {} # How to judge the response quality
      t.text :ideal_response_outline # Optional guidance for what good response includes
      t.boolean :active, default: true
      t.integer :times_asked, default: 0
      t.float :avg_score, default: 0.0
      t.timestamps
      
      t.index [:training_question_set_id, :question_type]
      t.index [:ekn_id, :archetype_focus]
      t.index [:difficulty_level, :active]
      t.index :question_type
    end
    
    # Training runs - when questions are executed
    create_table :training_runs, if_not_exists: true do |t|
      t.references :ekn, null: false, foreign_key: true
      t.references :training_question_set, null: false, foreign_key: true
      t.string :run_name
      t.text :run_description
      t.string :status, default: 'pending' # 'pending', 'running', 'completed', 'failed'
      t.integer :total_questions, default: 0
      t.integer :completed_questions, default: 0
      t.float :overall_score, default: 0.0
      t.json :archetype_scores, default: {} # Score breakdown by question type
      t.json :run_metadata, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
      
      t.index [:ekn_id, :status]
      t.index :training_question_set_id
      t.index :started_at
    end
    
    # Individual question responses and evaluations
    create_table :training_responses, if_not_exists: true do |t|
      t.references :training_run, null: false, foreign_key: true
      t.references :training_question, null: false, foreign_key: true
      t.references :ekn, null: false, foreign_key: true
      t.text :response_text
      t.float :response_time_seconds
      t.json :tool_usage, default: {} # Which MCP tools were used
      t.json :personality_metadata, default: {} # Archetype influence, routing decisions
      t.float :accuracy_score, default: 0.0
      t.float :completeness_score, default: 0.0
      t.float :personality_authenticity_score, default: 0.0
      t.float :overall_score, default: 0.0
      t.text :evaluation_notes
      t.json :evaluation_metadata, default: {}
      t.boolean :human_reviewed, default: false
      t.timestamps
      
      t.index [:training_run_id, :training_question_id]
      t.index [:ekn_id, :overall_score]
      t.index :created_at
    end
    
    # Add foreign key constraints (only if they don't exist)
    execute "ALTER TABLE training_questions ADD CONSTRAINT fk_training_questions_ekn FOREIGN KEY (ekn_id) REFERENCES ekns(id)" rescue nil
    execute "ALTER TABLE training_runs ADD CONSTRAINT fk_training_runs_ekn FOREIGN KEY (ekn_id) REFERENCES ekns(id)" rescue nil
    execute "ALTER TABLE training_responses ADD CONSTRAINT fk_training_responses_ekn FOREIGN KEY (ekn_id) REFERENCES ekns(id)" rescue nil
  end
end