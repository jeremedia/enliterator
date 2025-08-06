class CreatePromptVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: true
      t.text :content
      t.jsonb :variables
      t.integer :status
      t.integer :version_number
      t.float :performance_score

      t.timestamps
    end
  end
end
