# CRITICAL: Extraction Architecture Missing 8 of 15 Pools

**Status**: CRITICAL ARCHITECTURAL BUG  
**Impact**: ~50% entity loss, incomplete knowledge graphs  
**Root Cause**: Extraction services only consider 7-10 pools instead of specification's 15 pools

## Specification vs Implementation Gap

### What Specification Defines (15 Total Pools):

**Core Pools (1-10) - REQUIRED:**
1. ✅ **Idea** - principles, theories, intents, design rationales
2. ✅ **Manifest** - concrete instances and artifacts  
3. ✅ **Experience** - lived outcomes and perception
4. ✅ **Relational** - connections, lineages, and networks
5. ✅ **Evolutionary** - change over time
6. ✅ **Practical** - how-to and tacit knowledge
7. ✅ **Emanation** - ripple effects and downstream influence
8. ❌ **Provenance and Rights** - source, attribution, consent, license, lineage
9. ❌ **Lexicon and Ontology** - definitions, synonyms, types, and schema versions
10. ❌ **Intent and Task** - what users ask and how tasks are fulfilled

**Optional Domain Pools (11-15) - ADD WHEN DOMAIN DEMANDS IT:**
11. ❌ **Actor and Role** - people and organizations with roles and permissions
12. ❌ **Spatial** - places, regions, geometries, spatial hierarchies  
13. ❌ **Evidence and Observation** - primary data such as measurements, logs, transcripts
14. ❌ **Risk and Governance** - hazards, mitigations, approvals, compliance states
15. ❌ **Method and Model** - methods, methodologies, evaluation patterns

### Current Implementation Problems:

**Enhanced Extract and Link Tool** (`mcp/enhanced_extract_and_link_tool.rb`):
```ruby
POOLS = %w[Idea Practical Experience Manifest Character Time Space Lifecycle Symbolic Relator].freeze
```
- Wrong canonical names: Character→Actor, Time→Method, Space→Spatial, etc.
- Only considers 10 pools, missing 5 completely

**Basic Entity Extraction Service** (`pools/entity_extraction_service.rb`):
```ruby
POOL_DESCRIPTIONS = {
  'idea' => '...',
  'manifest' => '...',
  'experience' => '...',
  'relational' => '...',
  'evolutionary' => '...',
  'practical' => '...',
  'emanation' => '...'
}.freeze
```
- Only considers 7 pools, missing 8 completely
- Never attempts to extract entities for missing pools

## Critical User Insight

> "The optional pools are only optional due to the EKN's subject not having data to fill them, not code-optional."

This means extraction should attempt ALL 15 pools and only report empty results when content genuinely lacks that entity type.

## Impact Assessment

### Arctic Research EKN Example:
- **Expected**: Could contain entities from all 15 pools
- **Current**: Only extracting from 7-10 pools  
- **Missing**: Spatial locations, Methods, Actors, Evidence, etc.
- **Result**: Incomplete knowledge graph, poor chat responses

### System-Wide Impact:
- Every EKN is missing 30-50% of potential entities
- Knowledge graphs have massive gaps
- Chat system cannot answer questions about missing entity types
- Pipeline appears to work but produces incomplete results

## Required Fixes

### 1. Update Enhanced Extract and Link Tool
- Fix canonical pool names
- Add all 15 pools to POOLS constant
- Update prompts to consider all pools
- Implement pool-specific extraction logic

### 2. Update Basic Entity Extraction Service  
- Add missing 8 pools to POOL_DESCRIPTIONS
- Implement extraction for all pools
- Add pool-specific transformation logic

### 3. Update PostgreSQL Models
- Ensure all 15 pool types have corresponding models
- Verify Graph Writers exist for all pools
- Test sync to Neo4j for all entity types

### 4. Update MCP Tools
- Search tool should handle all 15 pools
- UI should display all pool types
- Navigation should work across all pools

## Testing Strategy

1. **Fresh Pipeline Run**: Arctic Research data through updated extraction
2. **Entity Count Verification**: Should see ~50% increase in entities
3. **Pool Distribution Check**: All applicable pools should have entities
4. **Knowledge Graph Verification**: Neo4j should contain all entity types
5. **Chat Testing**: Should be able to answer questions about all entity types

## Timeline

**Immediate**: Fix extraction services (2-3 hours)
**Next**: Test on Arctic Research EKN (1 hour)  
**Follow-up**: Document updated architecture (30 minutes)

This is blocking all EKNs from being complete Knowledge Navigators.