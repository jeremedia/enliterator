class AddEknToConversations < ActiveRecord::Migration[8.0]
  def change
    # Add ekn_id column
    add_reference :conversations, :ekn, foreign_key: true
    
    # Migrate existing data - set ekn_id based on ingest_batch
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE conversations 
          SET ekn_id = ingest_batches.ekn_id
          FROM ingest_batches
          WHERE conversations.ingest_batch_id = ingest_batches.id
        SQL
      end
    end
    
    # Remove the old ingest_batch_id column (optional - can keep for now)
    # remove_reference :conversations, :ingest_batch
  end
end