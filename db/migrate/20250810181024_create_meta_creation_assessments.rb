class CreateMetaCreationAssessments < ActiveRecord::Migration[8.0]
  def change
    create_table :meta_creation_assessments do |t|
      t.references :ekn, null: false, foreign_key: true
      t.references :mcp_test_run, null: true, foreign_key: true  # Null for non-test assessments
      t.integer :assessment_type, null: false  # enum: creation_guidance, personality_development, etc.
      t.integer :assessment_status, default: 0, null: false  # enum: pending, analyzing, completed, failed
      t.decimal :overall_score, precision: 4, scale: 3, null: false  # 0.000-1.000
      t.json :assessment_criteria             # Evaluation criteria used
      t.json :evaluation_results             # Detailed assessment results
      t.json :meta_enliterator_performance   # Meta-enliterator effectiveness data
      t.json :personality_health_metrics     # EKN personality health indicators
      t.json :user_satisfaction_indicators   # User experience metrics
      t.json :improvement_recommendations    # Specific suggestions for improvement
      t.json :meta_learning_evidence        # Evidence of meta-enliterator learning
      t.json :context_data                   # Additional context for assessment

      t.timestamps
    end
    
    add_index :meta_creation_assessments, :assessment_type
    add_index :meta_creation_assessments, :assessment_status
    add_index :meta_creation_assessments, :overall_score
    add_index :meta_creation_assessments, [:ekn_id, :created_at]
    add_index :meta_creation_assessments, [:assessment_type, :overall_score]
  end
end
