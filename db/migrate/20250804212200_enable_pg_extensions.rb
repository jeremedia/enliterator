class EnablePgExtensions < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pg_trgm'    # For trigram text search
    enable_extension 'pgcrypto'   # For UUID generation
    enable_extension 'btree_gin'  # For better GIN index performance
    enable_extension 'vector'     # For pgvector embeddings
  end
end