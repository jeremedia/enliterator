class CreateEmbeddings < ActiveRecord::Migration[8.0]
  def up
    # Set maintenance work memory for faster index creation
    execute "SET maintenance_work_mem = '2GB';"
    execute "SET max_parallel_maintenance_workers = 7;"
    
    create_table :embeddings do |t|
      # Source information
      t.string :embeddable_type, null: false
      t.string :embeddable_id, null: false
      t.string :pool, null: false
      t.string :embedding_type, null: false # 'entity' or 'path'
      
      # Text that was embedded
      t.text :source_text, null: false
      t.string :text_hash, null: false # For deduplication
      
      # Vector data - OpenAI text-embedding-3-small dimension
      # MUST be non-null for indexing
      t.vector :embedding, limit: 1536, null: false
      
      # Rights tracking
      t.boolean :publishable, default: false, null: false
      t.boolean :training_eligible, default: false, null: false
      
      # Metadata
      t.jsonb :metadata, default: {} # Store path info, entity details, etc.
      t.string :model_version # Track which OpenAI model was used
      t.datetime :indexed_at
      
      t.timestamps
      
      # B-tree indexes for filtering
      t.index [:embeddable_type, :embeddable_id], name: 'index_embeddings_on_embeddable'
      t.index :pool
      t.index :embedding_type
      t.index :text_hash, unique: true
      t.index [:publishable, :training_eligible], name: 'index_embeddings_on_rights'
      t.index :indexed_at
    end
    
    # HNSW index for cosine similarity (normalized vectors)
    # Optimized parameters for 1536-dimensional OpenAI embeddings
    # m=16: balanced between quality and speed
    # ef_construction=64: good build quality without excessive time
    # Use raw SQL for HNSW index with parameters
    execute <<-SQL
      CREATE INDEX index_embeddings_on_embedding 
      ON embeddings 
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL
      
    # Reset to defaults
    execute "RESET maintenance_work_mem;"
    execute "RESET max_parallel_maintenance_workers;"
  end
  
  def down
    drop_table :embeddings
  end
end
