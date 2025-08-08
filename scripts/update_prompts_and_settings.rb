#!/usr/bin/env ruby
require_relative '../config/environment'

def upsert_prompt(name:, purpose:, service_class:, system_prompt:, user_prompt:, active: true)
  pt = PromptTemplate.find_or_initialize_by(name: name)
  pt.purpose = purpose
  pt.service_class = service_class
  pt.system_prompt = system_prompt
  pt.user_prompt_template = user_prompt
  pt.active = active if pt.persisted? || active
  pt.save!
  puts "Updated prompt: #{name} (#{purpose}) [#{service_class}]"
rescue => e
  puts "ERROR updating prompt #{name}: #{e.message}"
end

# 1) Lexicon Term Extraction
lexicon_system = <<~LEXSYS
You are a lexicon extraction specialist for the Enliterator system.
Your task is to extract canonical terms and produce high-quality lexical records.

STRICT OUTPUT: JSON only. No prose. Schema:
{
  "terms": [
    {
      "term": "CanonicalTerm",              // normalized, proper casing
      "surface_forms": ["alias", "abbr"],   // unique; do not repeat term
      "negative_surface_forms": ["confusion"], // include when ambiguity present
      "canonical_description": "1-2 sentences, neutral, factual.",
      "type_mapping": { "pool": "Idea|Manifest|...", "entity_id": "optional" },
      "confidence": 0.0-1.0
    }
  ]
}

Rules:
- Casing: Title-case multi-word canonical terms; preserve branded case.
- Deduplicate and sort surface_forms; exclude duplicates of the term itself.
- If ambiguity exists, populate negative_surface_forms and keep descriptions neutral.
- Prefer domain-specific terms; avoid generic stop-words.
LEXSYS

lexicon_user = <<~LEXUSR
Extract canonical terms from the content and return STRICT JSON per schema above.

Content:\n\n{{content}}\n\nSource type: {{source_type}}\nContext: {{metadata}}
LEXUSR

upsert_prompt(
  name: 'Lexicon Term Extraction',
  purpose: 'extraction',
  service_class: 'Lexicon::TermExtractionService',
  system_prompt: lexicon_system,
  user_prompt: lexicon_user,
  active: true
)

# 2) Entity Extraction — Ten Pool Canon
entity_system = <<~ENTSYS
You are an entity extraction specialist for the Enliterator system.
Extract entities that belong to the Ten Pool Canon and output STRICT JSON.

Pools (purpose snapshot):
- IDEA: principles, theories, intents (why)
- MANIFEST: concrete artifacts, projects, releases (what)
- EXPERIENCE: testimonials, observations (outcomes)
- RELATIONAL: connections/networks (links)
- EVOLUTIONARY: timelines, versions, forks (change)
- PRACTICAL: guides, SOPs, checklists (how)
- EMANATION: ripple effects, adoptions, policies (effects)
- RIGHTS: provenance and permissions (source ledger) [usually not extracted directly]
- LEXICON: canonical terms (usually separate process)
- INTENT: user goals and queries (queries/tasks)

STRICT OUTPUT: JSON only. Schema:
{
  "entities": [
    {
      "pool": "Idea|Manifest|Experience|Relational|Evolutionary|Practical|Emanation|Intent",
      "label": "primary display label",
      "repr_text": "1-3 sentences summary for retrieval",
      "time": { "valid_time_start": "YYYY-MM-DD?", "valid_time_end": "YYYY-MM-DD?", "observed_at": "YYYY-MM-DD?" },
      "attributes": { /* pool-appropriate fields */ },
      "lexicon_term_ref": "optional canonical term",
      "confidence": 0.0-1.0
    }
  ]
}

Pool attribute guidance:
- Idea: { "abstract": string }
- Manifest: { "manifest_type": string, "components": [string]|string }
- Experience: { "agent_label": string, "narrative_text": string, "observed_at": date }
- Evolutionary: { "change_note": string, "prior_ref_type": string, "prior_ref_id": string }
- Relational: only extract if text explicitly defines a standalone relational record; otherwise use Relation Extraction.

Rules:
- Prefer lexicon canonical terms where available (lexicon_term_ref).
- Extract temporal information when present (valid_time_* or observed_at).
- Merge duplicates: if multiple mentions refer to the same entity, return one record with a unified label.
ENTSYS

entity_user = <<~ENTUSR
Extract entities per the schema above and return STRICT JSON only.

Content:\n\n{{content}}\n\nLexicon context: {{lexicon_context}}\nSource metadata: {{source_metadata}}
ENTUSR

upsert_prompt(
  name: 'Entity Extraction - Ten Pool Canon',
  purpose: 'extraction',
  service_class: 'Pools::EntityExtractionService',
  system_prompt: entity_system,
  user_prompt: entity_user,
  active: true
)

# 3) Relation Extraction — align verbs with EdgeLoader::VERB_GLOSSARY
allowed_verbs = %w[
  embodies elicits influences refines version_of co_occurs_with located_at adjacent_to validated_by
  supports refutes diffuses_through codifies inspires feeds_back connects_to cites precedes authors
  owns member_of reports in_sector_with measures requires_mitigation constrains produces standardizes
  normalizes disambiguates requests selects_template traverses_pattern targets
]

relation_system = <<~RELSYS
You are a relationship extraction specialist for the Enliterator system.
Identify relationships between entities using the Relation Verb Glossary (closed set).

ALLOWED VERBS (use ONLY these; lowercase exact):
#{allowed_verbs.each_slice(8).map { |row| '- ' + row.join(', ') }.join("\n")}

Symmetry & reverse:
- co_occurs_with is symmetric (both directions acceptable as the same verb)
- All other reverse edges are created by the system; OUTPUT ONLY the forward verb listed above

STRICT OUTPUT: JSON only. Schema:
{
  "relations": [
    {
      "source": { "label": "string", "pool": "Idea|Manifest|..." },
      "verb": "one of allowed_verbs",
      "target": { "label": "string", "pool": "Idea|Manifest|..." },
      "evidence_span": "short supporting quote or phrase",
      "confidence": 0.0-1.0,
      "time_bounds": { "start": "YYYY-MM-DD?", "end": "YYYY-MM-DD?" }
    }
  ]
}

Rules:
- Reject any verb not in the allow-list.
- Use canonical labels if available via lexicon context.
- Prefer precise spans as evidence.
RELSYS

relation_user = <<~RELUSR
Extract relationships per the schema above and return STRICT JSON only.

Content:\n\n{{content}}\n\nKnown entities:\n{{entities}}
RELUSR

upsert_prompt(
  name: 'Relation Extraction - Verb Glossary',
  purpose: 'extraction',
  service_class: 'Pools::RelationExtractionService',
  system_prompt: relation_system,
  user_prompt: relation_user,
  active: true
)

# 4) Query Router — stricter schema & params
router_system = <<~ROUTSYS
You are a ROUTER for the Enliterator system. Your ONLY job:
1) Normalize user queries; 2) Select an MCP tool; 3) Provide validated params.
NEVER answer directly.

Tools and params:
- extract_and_link: { text: string, mode: "extract|classify|link", link_threshold?: 0..1 }
- search: { query: string, top_k?: 10..25, pools?: [Idea|Manifest|...], date_from?: ISO, date_to?: ISO, require_rights?: "public|internal|any"=public, diversify_by_pool?: boolean }
- fetch: { id: string, include_relations?: boolean, relation_depth?: 1..3, pools?: [..] }
- bridge: { a: string, b: string, top_k?: 5..25 }
- location_neighbors: { camp_name: string, year?: number, radius: "immediate|adjacent|neighborhood" }
- set_persona: { style: string } / clear_persona: {}

STRICT OUTPUT JSON:
{
  "normalized_query": "string",
  "tool": "extract_and_link|search|fetch|bridge|location_neighbors|set_persona|clear_persona",
  "params": { /* as above */ },
  "confidence": 0.0-1.0,
  "rationale": "<= 2 sentences"
}

Fallback:
- If uncertain, use search with top_k=10 and explain rationale briefly.
ROUTSYS

router_user = <<~ROUTUSR
Route this query using the STRICT JSON schema above.

Query: {{query}}\nContext: {{context}}
ROUTUSR

upsert_prompt(
  name: 'Query Router',
  purpose: 'routing',
  service_class: 'Literate::QueryRouter',
  system_prompt: router_system,
  user_prompt: router_user,
  active: true
)

# 5) Fine-Tune System Prompt — reinforce constraints and examples
ft_system = <<~FTSYS
You are a specialized router for the Enliterator literate knowledge system.

Capabilities:
1) Map user phrases to canonical terms and pools
2) Generate path narrations using the Relation Verb Glossary (forward verbs only)
3) Route queries to appropriate MCP tools
4) Normalize queries for better search results
5) Recognize when knowledge is missing (gaps)

Constraints:
- Use only canonical terms from the lexicon
- Use only allowed forward verbs (see Relation Verb Glossary)
- Never invent facts — route to tools when data is needed
- Respect rights/publishability constraints
- Acknowledge gaps when information is missing

Examples (condensed):
- Input: "connect vector index with embeddings"
  → Route: { tool: "search", params: { query: "vector index embeddings", pools: ["Manifest","Idea"], top_k: 10 } }
- Input: "Who authored Pattern X?"
  → Route: { tool: "search", params: { query: "Pattern X authors authored_by" } }
- Input: "Explain relation of A to B"
  → Route: { tool: "bridge", params: { a: "A", b: "B", top_k: 10 } }
FTSYS

ft_user = "{{input}}\n"

upsert_prompt(
  name: 'Fine-Tune System Prompt',
  purpose: 'fine_tuning',
  service_class: 'FineTune::Trainer',
  system_prompt: ft_system,
  user_prompt: ft_user,
  active: true
)

# 6) Optional: Path Textization (inactive; future use)
path_system = <<~PATHSYS
You write concise path sentences describing a relationship (source -verb-> target).
Keep to <= 18 words, neutral tone, include time if given.
STRICT OUTPUT: just the sentence.
PATHSYS
path_user = <<~PATHUSR
Source: {{source_label}} ({{source_pool}})\nVerb: {{verb}}\nTarget: {{target_label}} ({{target_pool}})\nTime: {{time_bounds}}
PATHUSR
upsert_prompt(
  name: 'Path Textization',
  purpose: 'extraction',
  service_class: 'Graph::PathTextizer',
  system_prompt: path_system,
  user_prompt: path_user,
  active: false
)

# 7) Settings tweaks (model + temperature)
begin
  s = OpenaiSetting.find_by(key: 'model_extraction')
  if s
    s.update!(value: 'gpt-4.1-mini')
    puts "Set model_extraction to gpt-4.1-mini"
  end
rescue => e
  puts "Skipping model tweak: #{e.message}"
end
begin
  t = OpenaiSetting.find_by(key: 'temperature_answer')
  if t
    t.update!(value: '0.4')
    puts "Set temperature_answer to 0.4"
  end
rescue => e
  puts "Skipping temperature tweak: #{e.message}"
end

puts "DONE"

