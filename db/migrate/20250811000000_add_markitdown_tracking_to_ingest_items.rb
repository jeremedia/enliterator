# frozen_string_literal: true

class AddMarkitdownTrackingToIngestItems < ActiveRecord::Migration[8.0]
  def change
    # Add MarkItDown processing tracking fields
    add_column :ingest_items, :extraction_method, :string # 'markitdown' | 'legacy' | nil
    add_column :ingest_items, :extraction_model_used, :string # 'gpt-5' | 'gpt-4.1-mini' | nil
    add_column :ingest_items, :routing_tier, :string # 'tier_1' | 'tier_2' | 'too_much_text' | nil
    add_column :ingest_items, :estimated_tokens, :integer
    add_column :ingest_items, :content_length_chars, :integer
    add_column :ingest_items, :markitdown_metadata, :json
    
    # Add indexes for performance on new columns
    add_index :ingest_items, :extraction_method
    add_index :ingest_items, :routing_tier
  end
end