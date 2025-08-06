class CreateEkns < ActiveRecord::Migration[8.0]
  def change
    create_table :ekns do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, default: 'initializing'
      t.string :domain_type, default: 'general'
      t.string :personality, default: 'friendly'
      t.integer :session_id  # For pre-auth ownership
      t.jsonb :metadata, default: {}
      t.jsonb :settings, default: {}
      
      # Cached statistics
      t.integer :total_nodes, default: 0
      t.integer :total_relationships, default: 0
      t.integer :total_items, default: 0
      t.float :literacy_score
      
      t.timestamps
    end
    
    add_index :ekns, :session_id
    add_index :ekns, :status
    add_index :ekns, [:metadata], using: :gin  # For finding Meta-Enliterator
  end
end
