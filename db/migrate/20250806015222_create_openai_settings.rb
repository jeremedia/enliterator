class CreateOpenaiSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :openai_settings do |t|
      t.string :key, null: false
      t.string :category # 'model', 'prompt', 'temperature', 'config'
      t.text :value
      t.text :description
      t.string :model_type # 'extraction', 'answer', 'routing', 'fine_tune'
      t.jsonb :metadata, default: {}
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :openai_settings, :key, unique: true
    add_index :openai_settings, :category
    add_index :openai_settings, :model_type
    add_index :openai_settings, :active
  end
end
