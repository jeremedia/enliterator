# app/services/meta_enliteration/verb_mapper.rb
# Maps software-domain verbs to the closed Relation Verb Glossary
# CRITICAL: Ensures all graph relationships use spec-compliant verbs

module MetaEnliteration
  class VerbMapper < ApplicationService
    
    # Closed set of verbs from the spec (Section 6)
    GLOSSARY_VERBS = {
      # Core pool relationships
      embodies: { forward: 'embodies', reverse: 'is_embodiment_of', pools: ['Idea', 'Manifest'] },
      elicits: { forward: 'elicits', reverse: 'is_elicited_by', pools: ['Manifest', 'Experience'] },
      influences: { forward: 'influences', reverse: 'is_influenced_by', pools: ['Idea', 'Emanation', '*'] },
      refines: { forward: 'refines', reverse: 'is_refined_by', pools: ['Evolutionary', 'Idea'] },
      version_of: { forward: 'version_of', reverse: 'has_version', pools: ['Evolutionary', 'Manifest'] },
      co_occurs_with: { forward: 'co_occurs_with', reverse: 'co_occurs_with', pools: ['Relational', 'Relational'], symmetric: true },
      located_at: { forward: 'located_at', reverse: 'hosts', pools: ['Manifest', 'Spatial'] },
      adjacent_to: { forward: 'adjacent_to', reverse: 'adjacent_to', pools: ['Spatial', 'Spatial'], symmetric: true },
      validated_by: { forward: 'validated_by', reverse: 'validates', pools: ['Practical', 'Experience'] },
      supports: { forward: 'supports', reverse: nil, pools: ['Evidence', 'Idea'] },
      refutes: { forward: 'refutes', reverse: nil, pools: ['Evidence', 'Idea'] },
      diffuses_through: { forward: 'diffuses_through', reverse: nil, pools: ['Emanation', 'Relational'] },
      
      # Additional required verbs from spec
      codifies: { forward: 'codifies', reverse: 'is_codified_by', pools: ['Idea', 'Practical'] },
      inspires: { forward: 'inspires', reverse: 'is_inspired_by', pools: ['Experience', 'Emanation'] },
      connects_to: { forward: 'connects_to', reverse: 'is_connected_to', pools: ['*', '*'] },
      cites: { forward: 'cites', reverse: 'is_cited_by', pools: ['*', '*'] },
      precedes: { forward: 'precedes', reverse: 'follows', pools: ['*', '*'] },
      feeds_back: { forward: 'feeds_back', reverse: 'is_fed_by', pools: ['Emanation', 'Idea'] },
      derived_from: { forward: 'derived_from', reverse: 'informs', pools: ['Practical', 'Idea'] },
      
      # Evidence-specific verbs
      measures: { forward: 'measures', reverse: 'is_measured_by', pools: ['Evidence', 'Manifest'] },
      produces: { forward: 'produces', reverse: 'is_produced_by', pools: ['Method', 'Evidence'] },
      standardizes: { forward: 'standardizes', reverse: 'is_standardized_by', pools: ['Method', 'Practical'] },
      
      # Governance verbs
      requires_mitigation: { forward: 'requires_mitigation', reverse: nil, pools: ['Risk', 'Practical'] },
      constrains: { forward: 'constrains', reverse: 'is_constrained_by', pools: ['Governance', 'Provenance'] },
      
      # Actor verbs
      authors: { forward: 'authors', reverse: 'is_authored_by', pools: ['Actor', 'Manifest'] },
      owns: { forward: 'owns', reverse: 'is_owned_by', pools: ['Actor', 'Manifest'] },
      member_of: { forward: 'member_of', reverse: 'has_member', pools: ['Actor', 'Relational'] },
      reports: { forward: 'reports', reverse: 'is_reported_by', pools: ['Actor', 'Experience'] }
    }.freeze
    
    # Mapping from software verbs to glossary verbs
    SOFTWARE_TO_GLOSSARY = {
      # Code relationships
      'implements' => :embodies,
      'realizes' => :embodies,
      'instantiates' => :embodies,
      'extends' => :refines,
      'overrides' => :refines,
      'imports' => :connects_to,
      'requires' => :connects_to,
      'depends_on' => :connects_to,
      'uses' => :connects_to,
      'includes' => :connects_to,
      'inherits_from' => :derived_from,
      'subclasses' => :derived_from,
      
      # Testing relationships
      'tests' => :validates,
      'verifies' => :validates,
      'asserts' => :validates,
      'mocks' => :connects_to,
      'stubs' => :connects_to,
      'expects' => :validates,
      
      # Version control relationships
      'commits' => :version_of,
      'branches_from' => :version_of,
      'forked_from' => :version_of,
      'merged_into' => :version_of,
      'tags' => :version_of,
      'releases' => :version_of,
      
      # Documentation relationships
      'documents' => :codifies,
      'describes' => :codifies,
      'specifies' => :codifies,
      'defines' => :codifies,
      'explains' => :codifies,
      
      # Build/deployment relationships
      'builds' => :produces,
      'compiles' => :produces,
      'generates' => :produces,
      'deploys' => :influences,
      'publishes' => :influences,
      
      # Database relationships
      'migrates' => :refines,
      'seeds' => :produces,
      'indexes' => :connects_to,
      'references' => :connects_to,
      'belongs_to' => :connects_to,
      'has_many' => :connects_to,
      
      # Error/exception relationships
      'raises' => :produces,
      'catches' => :validates,
      'handles' => :validates,
      'rescues' => :validates,
      
      # Configuration relationships
      'configures' => :codifies,
      'initializes' => :produces,
      'bootstraps' => :produces,
      'provisions' => :produces
    }.freeze
    
    def initialize(verb, source_pool: nil, target_pool: nil)
      @original_verb = verb.to_s.downcase
      @source_pool = source_pool
      @target_pool = target_pool
    end
    
    def call
      mapped_verb = map_to_glossary(@original_verb)
      
      {
        success: true,
        original: @original_verb,
        mapped: mapped_verb,
        glossary_verb: GLOSSARY_VERBS[mapped_verb],
        confidence: calculate_confidence(mapped_verb),
        warning: generate_warning(mapped_verb)
      }
    end
    
    def self.validate_relationship(verb, source_pool, target_pool)
      mapper = new(verb, source_pool: source_pool, target_pool: target_pool)
      result = mapper.call
      
      unless result[:success]
        raise "Invalid verb mapping: #{verb}"
      end
      
      # Check pool constraints if specified
      if result[:glossary_verb][:pools] != ['*', '*']
        expected_pools = result[:glossary_verb][:pools]
        unless pool_match?(source_pool, expected_pools[0]) && pool_match?(target_pool, expected_pools[1])
          raise "Pool mismatch for verb #{verb}: expected #{expected_pools.join('->')}, got #{source_pool}->#{target_pool}"
        end
      end
      
      result
    end
    
    def self.get_reverse_verb(verb)
      mapped = new(verb).call
      return nil unless mapped[:success]
      
      mapped[:glossary_verb][:reverse]
    end
    
    def self.is_symmetric?(verb)
      mapped = new(verb).call
      return false unless mapped[:success]
      
      mapped[:glossary_verb][:symmetric] == true
    end
    
    def self.list_verbs_for_pools(source_pool, target_pool)
      GLOSSARY_VERBS.select do |verb, config|
        pools = config[:pools]
        pool_match?(source_pool, pools[0]) && pool_match?(target_pool, pools[1])
      end.keys
    end
    
    private
    
    def map_to_glossary(verb)
      # Direct match in glossary
      return verb.to_sym if GLOSSARY_VERBS.key?(verb.to_sym)
      
      # Check reverse verbs
      GLOSSARY_VERBS.each do |key, config|
        return key if config[:reverse] == verb
      end
      
      # Check software mapping
      mapped = SOFTWARE_TO_GLOSSARY[verb]
      return mapped if mapped
      
      # Fuzzy matching for common variations
      case verb
      when /^(is_)?connected/, /^links?_to/
        :connects_to
      when /^(is_)?related/, /^relates?_to/
        :connects_to
      when /^(is_)?based_on/, /^derives?_from/
        :derived_from
      when /^(is_)?part_of/, /^contains?/
        :connects_to
      when /^(is_)?used_by/, /^uses?/
        :connects_to
      when /^(is_)?called_by/, /^calls?/
        :connects_to
      when /^(is_)?triggered_by/, /^triggers?/
        :influences
      when /^(is_)?caused_by/, /^causes?/
        :influences
      when /^(is_)?updated/, /^updates?/
        :refines
      when /^(is_)?created/, /^creates?/
        :produces
      when /^(is_)?generated/, /^generates?/
        :produces
      else
        # Default fallback for unknown verbs
        :connects_to
      end
    end
    
    def calculate_confidence(mapped_verb)
      return 1.0 if GLOSSARY_VERBS.key?(@original_verb.to_sym)
      return 0.9 if SOFTWARE_TO_GLOSSARY.key?(@original_verb)
      return 0.7 if mapped_verb != :connects_to
      0.5 # Low confidence for fallback to connects_to
    end
    
    def generate_warning(mapped_verb)
      return nil if GLOSSARY_VERBS.key?(@original_verb.to_sym)
      
      if SOFTWARE_TO_GLOSSARY.key?(@original_verb)
        "Software verb '#{@original_verb}' mapped to glossary verb '#{mapped_verb}'"
      elsif mapped_verb == :connects_to
        "Unknown verb '#{@original_verb}' defaulted to 'connects_to' - consider manual review"
      else
        "Fuzzy match: '#{@original_verb}' mapped to '#{mapped_verb}' - verify accuracy"
      end
    end
    
    def self.pool_match?(actual, expected)
      expected == '*' || actual.to_s.downcase == expected.to_s.downcase
    end
  end
end