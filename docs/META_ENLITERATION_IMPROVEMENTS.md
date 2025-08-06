# Meta-Enliteration Critical Improvements

## 1. Rights & Eligibility Nuances ✅

### Problem
MIT license covers code, but commit messages and GitHub issues may contain third-party text and personal information.

### Solution
```ruby
# app/services/meta_enliteration/rights_classifier.rb
class RightsClassifier
  def classify(file_path, content_type)
    case content_type
    when :code, :documentation
      { publishability: true, training_eligibility: true, license: 'MIT' }
    when :commit_message, :issue, :pr
      { publishability: :internal, training_eligibility: false, license: 'mixed' }
    when :test_output
      { publishability: :internal, training_eligibility: true, license: 'MIT' }
    end
  end
end
```

## 2. Pool Boundaries Correction ✅

### Problem
Tests as Experience conflates verification with lived experience.

### Solution
- **Evidence & Observation Pool**: Test outputs, CI logs, performance metrics
- **Experience Pool**: User testimonials, usage stories in docs, error reports from users
- **Practical Pool**: Test code itself (how to verify)

```ruby
# Correct mapping:
test_file → Practical (how to test)
test_result → Evidence (verification data)
user_story_in_docs → Experience (lived outcome)
```

## 3. Closed Verb Glossary Mapping ✅

### Problem
Software naturally uses verbs outside the glossary (implements, imports, depends_on).

### Solution - Strict Mapping Table:
```ruby
VERB_MAPPINGS = {
  # Code relationships
  'implements' => 'embodies',        # Idea→Manifest
  'extends' => 'refines',            # Evolutionary→Idea
  'imports' => 'connects_to',        # Relational
  'requires' => 'connects_to',       # Relational
  'depends_on' => 'connects_to',     # Relational
  'inherits_from' => 'derived_from', # Practical→Idea
  
  # Testing relationships  
  'tests' => 'validates',           # Practical→Evidence
  'verifies' => 'validates',        # Practical→Evidence
  'mocks' => 'connects_to',         # Relational
  
  # Version relationships
  'versioned_as' => 'has_version',  # Manifest→Evolutionary
  'forked_from' => 'version_of',    # Evolutionary→Manifest
  'migrates' => 'refines'           # Evolutionary→Idea
}
```

## 4. Spatial Semantics Clarification ✅

### Problem
File trees aren't geographic space, causing semantic confusion.

### Solution A: Logical Spatialization
```ruby
# Document clearly that Spatial is used metaphorically
class Spatial
  # For codebase: directories are "regions", modules are "districts"
  # app/ is a "continent", app/models/ is a "country", idea.rb is a "city"
  
  def self.type_for_software
    'logical_space'  # Not geographic_space
  end
end
```

### Solution B: Structure Neighbors Tool
```ruby
# app/services/mcp/structure_neighbors.rb
# Mirrors location_neighbors but for code structure
def structure_neighbors(file_path, radius: 'immediate')
  case radius
  when 'immediate'
    # Files in same directory
  when 'adjacent'  
    # Files in parent/child directories
  when 'module'
    # Files in same module/namespace
  end
end
```

## 5. Negative Knowledge & Coverage ✅

### Problem
EKN might claim capabilities it doesn't have.

### Solution
```ruby
# app/models/negative_knowledge.rb
class NegativeKnowledge < ApplicationRecord
  # Record what we explicitly DON'T know
  
  KNOWN_GAPS = [
    "Performance benchmarks for individual services",
    "Production deployment metrics",
    "User satisfaction scores",
    "Cost analysis for OpenAI usage",
    "Security audit results"
  ]
  
  def self.check_coverage(query)
    gaps = KNOWN_GAPS.select { |gap| relevant_to?(query, gap) }
    gaps.any? ? "Note: I don't have data on #{gaps.join(', ')}" : nil
  end
end
```

## 6. Fine-Tune Boundaries ✅

### Problem
Fine-tuned model might hallucinate facts instead of routing to retrieval.

### Solution
```ruby
# Hard boundary in the fine-tune training data
SYSTEM_RULE = <<~RULE
  You are a ROUTER, not an oracle. Your ONLY jobs are:
  1. Normalize queries to canonical terms
  2. Identify which MCP tool to call
  3. Format tool parameters
  4. NEVER answer factual questions directly
  
  If asked "What is X?", respond: "ROUTE: search(query='X', pools=['idea','manifest'])"
  If asked "How do I Y?", respond: "ROUTE: fetch(type='practical', goal='Y')"
RULE

# Add classifier head
class RouteClassifier
  def requires_rag?(query)
    # Returns true for ANY factual question
    query.match?(/what|how|where|when|why|which|list|show|explain/)
  end
end
```

## 7. Objective Evaluation Metrics ✅

### Measurable Targets
```yaml
evaluation_metrics:
  retrieval:
    metric: MRR@10  # Mean Reciprocal Rank
    target: 0.75
    test_set: 50_questions.json
    
  tool_planning:
    metric: exact_match
    target: 0.90
    gold_plans: tool_plans.json
    
  path_textization:
    metric: round_trip_accuracy
    target: 0.95
    test: "path → text → path preserves meaning"
    
  rights_compliance:
    metric: violation_count
    target: 0
    test: "never expose internal-only content"
    
  multi_pool_coverage:
    metric: percentage_using_2plus_pools
    target: 0.80
    test: "explanations draw from multiple pools"
```

## 8. Versioning & Time Travel ✅

### Problem
Can't answer "How did this work in v1.0?"

### Solution
```ruby
# app/services/meta_enliteration/temporal_indexer.rb
class TemporalIndexer
  def index_by_version
    tags = `git tag`.split("\n")
    
    tags.each do |tag|
      `git checkout #{tag}`
      snapshot = create_snapshot
      
      Evolutionary.create!(
        version_id: tag,
        change_note: "Snapshot at #{tag}",
        metadata: snapshot
      )
    end
  end
  
  def answer_as_of(query, version)
    # Fetch only entities valid at that version
    entities = Entity.where("valid_time @> ?::timestamp", version)
    # Route to search with temporal constraint
  end
end
```

## 9. Security & Privacy Redaction ✅

### Problem
Repos contain .env files, API keys, emails.

### Solution
```ruby
# app/services/meta_enliteration/redactor.rb
class Redactor
  DENY_PATTERNS = [
    /\.env/,
    /secrets/,
    /private_key/,
    /password/,
    /token/
  ]
  
  EMAIL_PATTERN = /[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+/i
  
  def redact_file(content)
    # Replace emails
    content.gsub!(EMAIL_PATTERN, '[REDACTED_EMAIL]')
    
    # Replace API keys
    content.gsub!(/[A-Z0-9]{20,}/, '[REDACTED_KEY]')
    
    # Quarantine if sensitive
    if DENY_PATTERNS.any? { |p| content.match?(p) }
      return { quarantine: true, reason: 'Contains sensitive data' }
    end
    
    content
  end
end
```

## 10. M4 Maturity Compliance ✅

### Problem
M4 requires continuous learning and adaptation.

### Solution
```ruby
# app/jobs/ekn_evaluation_job.rb
class EKNEvaluationJob < ApplicationJob
  # Runs weekly
  
  def perform
    results = run_50_question_evaluation
    previous = last_weeks_results
    
    delta = results[:score] - previous[:score]
    
    if delta < -0.05  # 5% degradation
      Issue.create!(
        title: "EKN Performance Degradation",
        body: "Score dropped from #{previous[:score]} to #{results[:score]}",
        labels: ['ekn-health', 'automated']
      )
    end
    
    # Log for continuous improvement
    PerformanceLog.create!(results)
  end
end
```

## 11. Concrete Deliverables ✅

### Deliverable 1: Architecture Webpage
```ruby
# app/services/deliverables/architecture_page_generator.rb
def generate
  nodes = fetch_top_level_components
  paths = fetch_key_paths
  
  html = <<~HTML
    <h1>Enliterator Architecture</h1>
    <div class="knowledge-graph">
      #{render_interactive_graph(nodes, paths)}
    </div>
    <div class="path-explanations">
      #{paths.map { |p| render_path_card(p) }}
    </div>
  HTML
  
  save_as('architecture.html')
end
```

### Deliverable 2: Navigator Creation Guide
```ruby
# app/services/deliverables/navigator_guide_generator.rb
def generate(domain)
  outline = <<~OUTLINE
    # Creating a #{domain} Knowledge Navigator
    
    ## 1. Prepare Your Data [→ Interview Module]
    ## 2. Process Through Pipeline [→ Stage 1-8 Services]  
    ## 3. Generate Training Data [→ Graph Paths]
    ## 4. Fine-Tune Model [→ OpenAI API]
    ## 5. Deploy Navigator [→ Conversation Model]
    
    Each step includes code examples and citations.
  OUTLINE
  
  save_as("#{domain}_navigator_guide.md")
end
```

## 12. Tone Adjustment ✅

### Original
"Historic Note: This represents the first instance of a software system achieving enliteracy about itself"

### Revised
"Note: To our knowledge, this is the first public, spec-conformant implementation of meta-enliteration where a system processes its own codebase to achieve self-understanding through a documented pipeline."

## Implementation Priority

1. **CRITICAL** (Do immediately):
   - Rights classification for commits/issues
   - Security redaction
   - Verb mapping table

2. **IMPORTANT** (Do before pipeline run):
   - Pool boundary corrections (Evidence vs Experience)
   - Negative knowledge recording
   - Fine-tune boundaries

3. **VALUABLE** (Do before deployment):
   - Time travel indexing
   - M4 compliance job
   - Concrete deliverables

4. **NICE-TO-HAVE** (Can defer):
   - Spatial clarification
   - Tone adjustments

## Summary

These improvements transform meta-enliteration from a proof-of-concept into a production-ready, spec-compliant system that:
- Respects rights and privacy
- Uses pools correctly
- Maintains verb discipline
- Knows its limitations
- Measures success objectively
- Delivers real value

The EKN will be honest about what it knows and doesn't know, making it a trustworthy Knowledge Navigator.