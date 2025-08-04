# frozen_string_literal: true

# Configure neighbor gem for pgvector
require "neighbor"

# Set the vector dimensions for embeddings
# OpenAI text-embedding-3-small produces 1536 dimensions
# OpenAI text-embedding-3-large produces 3072 dimensions
Rails.application.config.neighbor = {
  dimensions: ENV.fetch("EMBEDDING_DIMENSIONS", 1536).to_i,
  model: ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-small")
}