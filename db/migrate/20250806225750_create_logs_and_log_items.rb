class CreateLogsAndLogItems < ActiveRecord::Migration[8.0]
  def change
    create_table :logs do |t|
      t.uuid :uuid, null: false
      t.references :loggable, polymorphic: true, null: false, index: true
      t.string :label
      
      t.timestamps
    end
    
    add_index :logs, :uuid, unique: true
    
    create_table :log_items do |t|
      t.uuid :uuid, null: false
      t.references :log, null: false, foreign_key: true
      t.integer :num
      t.string :log_label
      t.string :status
      t.text :text
      t.jsonb :item_data
      
      t.timestamps
    end
    
    add_index :log_items, :uuid, unique: true
  end
end
