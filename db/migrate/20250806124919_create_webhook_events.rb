class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :webhook_id, null: false
      t.datetime :timestamp, null: false
      t.string :signature
      t.jsonb :headers, default: {}
      t.jsonb :payload, default: {}, null: false
      t.string :status, default: 'pending', null: false
      t.datetime :processed_at
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.integer :retry_count, default: 0
      t.string :resource_type # e.g., 'FineTuneJob', 'Batch', 'Response'
      t.string :resource_id   # e.g., fine-tune job ID, batch ID

      t.timestamps
    end
    
    add_index :webhook_events, :event_id, unique: true
    add_index :webhook_events, :event_type
    add_index :webhook_events, :status
    add_index :webhook_events, :webhook_id
    add_index :webhook_events, [:resource_type, :resource_id]
    add_index :webhook_events, :created_at
  end
end
