-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable additional useful extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text similarity
CREATE EXTENSION IF NOT EXISTS btree_gin; -- For compound indexes
CREATE EXTENSION IF NOT EXISTS btree_gist; -- For exclusion constraints

-- Create schema for vector operations
CREATE SCHEMA IF NOT EXISTS vectors;

-- Grant permissions
GRANT ALL ON SCHEMA vectors TO enliterator;
GRANT ALL ON ALL TABLES IN SCHEMA vectors TO enliterator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA vectors TO enliterator;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA vectors TO enliterator;