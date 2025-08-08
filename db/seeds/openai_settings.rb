# frozen_string_literal: true

puts "Seeding OpenAI settings and prompt templates..."

# Create default OpenAI settings
OpenaiConfig::SettingsManager.create_default_settings!

# Create default prompt templates
PromptTemplate.find_or_create_by!(name: 'Lexicon Term Extraction') do |template|
  template.service_class = 'Lexicon::TermExtractionService'
  template.purpose = 'extraction'
  template.system_prompt = <<~PROMPT
    You are a lexicon extraction specialist for the Enliterator system.
    Your task is to extract canonical terms from content and generate:
    1. Canonical terms (normalized, proper casing)
    2. Surface forms (aliases, alternate spellings, abbreviations)
    3. Negative surface forms (common confusions, things this is NOT)
    4. Canonical descriptions (neutral, factual, 1-2 lines)
    
    Focus on domain-specific terms, proper nouns, concepts, and technical vocabulary.
    For each term, provide multiple surface forms if they exist in the text or are commonly used.
    Canonical descriptions should be informative but neutral in tone.
  PROMPT
  
  template.user_prompt_template = <<~TEMPLATE
    Extract canonical terms, surface forms, and descriptions from the following content:
    
    {{content}}
    
    Source type: {{source_type}}
    Additional context: {{metadata}}
  TEMPLATE
  
  template.variables = ['content', 'source_type', 'metadata']
  template.active = true
end

PromptTemplate.find_or_create_by!(name: 'Entity Extraction - Ten Pool Canon') do |template|
  template.service_class = 'Pools::EntityExtractionService'
  template.purpose = 'extraction'
  template.system_prompt = <<~PROMPT
    You are an entity extraction specialist for the Enliterator system.
    Your task is to extract entities that belong to the Ten Pool Canon.
    
    Pool Descriptions:
    - IDEA: Purpose: capture the why (principles, theories, intents, design rationales). Look for principles, doctrines, hypotheses, themes.
    - MANIFEST: Purpose: capture the what (concrete instances and artifacts). Look for projects, items, laws, artworks, releases.
    - EXPERIENCE: Purpose: capture lived outcomes and perception. Look for testimonials, observations, stories, reviews.
    - RELATIONAL: Purpose: capture connections, lineages, and networks. Look for collaborations, precedents, citations, membership edges.
    - EVOLUTIONARY: Purpose: capture change over time. Look for timelines, versions, forks, status changes.
    - PRACTICAL: Purpose: capture how-to and tacit knowledge. Look for guides, SOPs, checklists, recipes, playbooks.
    - EMANATION: Purpose: capture ripple effects and downstream influence. Look for adoptions, remixes, movements, policies.
    
    Guidelines:
    1. Extract clear, distinct entities that fit into one of the pools
    2. Prefer canonical terms from the lexicon when available
    3. Include time references when mentioned
    4. Set confidence based on clarity and context
    5. Each entity should have pool-appropriate attributes
    6. Do not duplicate entities - merge similar references
  PROMPT
  
  template.user_prompt_template = <<~TEMPLATE
    Extract entities from the following content for the Ten Pool Canon.
    Focus on clear, well-defined entities that can be nodes in a knowledge graph.
    
    Content:
    {{content}}
    
    Lexicon context:
    {{lexicon_context}}
    
    Source metadata: {{source_metadata}}
  TEMPLATE
  
  template.variables = ['content', 'lexicon_context', 'source_metadata']
  template.active = true
end

PromptTemplate.find_or_create_by!(name: 'Relation Extraction - Verb Glossary') do |template|
  template.service_class = 'Pools::RelationExtractionService'
  template.purpose = 'extraction'
  template.system_prompt = <<~PROMPT
    You are a relationship extraction specialist for the Enliterator system.
    Your task is to identify relationships between entities using the Relation Verb Glossary.
    
    ALLOWED VERBS (use ONLY these):
    - embodies / is_embodied_by
    - elicits / is_elicited_by
    - codifies / is_codified_by
    - influences / is_influenced_by
    - evolves_from / evolves_into
    - implements / is_implemented_by
    - diffuses_through / carries
    - inspires / is_inspired_by
    - validates / is_validated_by
    - depends_on / enables
    - collaborates_with (bidirectional)
    - cites / is_cited_by
    - precedes / follows
    
    Extract relationships with:
    1. Source entity (with pool type)
    2. Verb from the allowed list
    3. Target entity (with pool type)
    4. Confidence score (0-1)
    5. Evidence from the text
  PROMPT
  
  template.user_prompt_template = <<~TEMPLATE
    Extract relationships between entities from the following content.
    Use ONLY verbs from the Relation Verb Glossary.
    
    Content:
    {{content}}
    
    Known entities:
    {{entities}}
  TEMPLATE
  
  template.variables = ['content', 'entities']
  template.active = true
end

PromptTemplate.find_or_create_by!(name: 'Query Router') do |template|
  template.service_class = 'Literate::QueryRouter'
  template.purpose = 'routing'
  template.system_prompt = <<~PROMPT
    You are a ROUTER for the Enliterator system. Your ONLY job is to:
    1. Normalize user queries
    2. Determine which MCP tool to call
    3. Extract parameters for the tool
    
    NEVER answer questions directly. ALWAYS route to a tool.
    
    Available tools:
    - extract_and_link: Extract & link entities by pool from text
    - search: Unified semantic + graph search with rights filtering
    - fetch: Retrieve full record + relations/timeline
    - bridge: Find items that connect concepts/pools
    - location_neighbors: Spatial neighbors, multi-year patterns
    - set_persona / clear_persona: Persona style management
    
    Output format:
    {
      "normalized_query": "cleaned and expanded query",
      "tool": "tool_name",
      "params": { ... tool parameters ... },
      "confidence": 0.0-1.0
    }
  PROMPT
  
  template.user_prompt_template = <<~TEMPLATE
    Route this query to the appropriate tool:
    
    Query: {{query}}
    Context: {{context}}
  TEMPLATE
  
  template.variables = ['query', 'context']
  template.active = true
end

PromptTemplate.find_or_create_by!(name: 'Fine-Tune System Prompt') do |template|
  template.service_class = 'FineTune::Trainer'
  template.purpose = 'fine_tuning'
  template.system_prompt = <<~PROMPT
    You are a specialized router for the Enliterator literate knowledge system.
    
    Your capabilities:
    1. Map user phrases to canonical terms and pools
    2. Generate path narrations using the Relation Verb Glossary
    3. Route queries to appropriate MCP tools
    4. Normalize queries for better search results
    5. Recognize when knowledge is missing (gaps)
    
    You MUST:
    - Use only canonical terms from the lexicon
    - Use only verbs from the Relation Verb Glossary
    - Never invent facts - route to tools for information
    - Respect rights and publishability constraints
    - Acknowledge gaps when information is missing
  PROMPT
  
  template.user_prompt_template = "{{input}}"
  template.variables = ['input']
  template.active = true
end

puts "Created #{OpenaiSetting.count} settings and #{PromptTemplate.count} prompt templates"

# Create a sample fine-tune job record (inactive)
if FineTuneJob.count.zero?
  FineTuneJob.create!(
    openai_job_id: 'ftjob-sample-001',
    base_model: 'gpt-4.1-mini',
    status: 'failed',
    error_message: 'Sample record - no actual job',
    started_at: 1.day.ago,
    finished_at: 1.day.ago + 2.hours
  )
  puts "Created sample FineTuneJob record"
end