class CreatePromptTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :prompt_templates do |t|
      t.string :name, null: false
      t.string :service_class # e.g., 'Lexicon::TermExtractionService'
      t.text :system_prompt
      t.text :user_prompt_template # with {{placeholders}}
      t.jsonb :variables, default: [] # expected variables list
      t.jsonb :metadata, default: {}
      t.boolean :active, default: true
      t.string :purpose # 'extraction', 'conversation', 'routing', etc.
      
      t.timestamps
    end
    
    add_index :prompt_templates, :name, unique: true
    add_index :prompt_templates, :service_class
    add_index :prompt_templates, :active
    add_index :prompt_templates, :purpose
  end
end
