# frozen_string_literal: true

module Graph
  # Policy class for enforcing closed verb glossary and pool-pair legality
  # Based on spec v1.2 Relation Verb Glossary
  class VerbPolicy
    # Canonical verbs with allowed pool pairs (from spec)
    CANONICAL = {
      idea_manifest: :embodies,
      manifest_experience: :elicits,
      idea_practical: :codifies,
      practical_experience: :validated_by,
      emanation_relational: :diffuses_through,
      evidence_idea: [:supports, :refutes],
      idea_any: :influences,
      evolutionary_manifest: :version_of,
      spatial_spatial: :adjacent_to,
      manifest_spatial: :located_at,
      relational_relational: :co_occurs_with,
      actor_manifest: :authors,
      actor_relational: :member_of,
      actor_experience: :reports,
      evidence_manifest: :measures,
      method_practical: :standardizes,
      lexicon_any: :normalizes
    }.freeze

    # Reverse mappings
    REVERSES = {
      embodies: :is_embodiment_of,
      elicits: :is_elicited_by,
      influences: :is_influenced_by,
      refines: :is_refined_by,
      version_of: :has_version,
      located_at: :hosts,
      validated_by: :validates,
      authors: :authored_by,
      member_of: :has_member,
      reports: :reported_by,
      measures: :measured_by,
      standardizes: :standardized_by,
      normalizes: :normalized_by
    }.freeze

    # Synonym mappings to canonical verbs
    SYNONYMS = {
      relates_to: :influences,
      guides: :codifies,
      manifests_in: :embodies,
      connects_to: :influences,
      inspires: :influences,
      feeds_back: :influences,
      implements: :standardizes,
      disambiguates: :normalizes,
      extends: :influences,
      bridges: :influences,
      associates_with: :influences,
      enables: :influences,
      requires: :influences
    }.freeze

    class << self
      # Check if a verb is allowed for a pool pair
      def allowed?(source_pool, target_pool, verb)
        normalized_verb = normalize(verb)
        return false unless normalized_verb

        source = source_pool.to_s.downcase.to_sym
        target = target_pool.to_s.downcase.to_sym
        
        # Check all canonical mappings
        CANONICAL.each do |pools, allowed_verbs|
          pools_str = pools.to_s
          source_match = pools_str.include?(source.to_s) || pools_str.include?('any')
          target_match = pools_str.include?(target.to_s) || pools_str.include?('any')
          
          next unless source_match || target_match
          
          allowed_list = Array(allowed_verbs)
          return true if allowed_list.include?(normalized_verb)
          
          # Check reverses
          allowed_list.each do |v|
            return true if REVERSES[v] == normalized_verb
          end
        end
        
        # Special case: influences is allowed from Idea/Emanation to anything
        if normalized_verb == :influences && [:idea, :emanation].include?(source)
          return true
        end
        
        # Check EdgeLoader for compatibility
        glossary_entry = EdgeLoader::VERB_GLOSSARY[normalized_verb.to_s]
        if glossary_entry
          source_ok = glossary_entry[:source] == '*' || 
                     glossary_entry[:source] == source_pool.to_s.capitalize ||
                     (glossary_entry[:source].is_a?(Array) && glossary_entry[:source].include?(source_pool.to_s.capitalize))
          
          target_ok = glossary_entry[:target] == '*' || 
                     glossary_entry[:target] == target_pool.to_s.capitalize ||
                     (glossary_entry[:target].is_a?(Array) && glossary_entry[:target].include?(target_pool.to_s.capitalize))
          
          return source_ok && target_ok
        end
        
        false
      end

      # Normalize a verb to its canonical form
      def normalize(verb)
        return nil unless verb
        
        verb_sym = verb.to_s.downcase.to_sym
        
        # Return if already canonical
        return verb_sym if canonical_verbs.include?(verb_sym)
        
        # Check synonyms
        normalized = SYNONYMS[verb_sym]
        return normalized if normalized
        
        # Check if it's a reverse
        REVERSES.each do |canonical, reverse|
          return canonical if reverse == verb_sym
        end
        
        # Check EdgeLoader glossary
        return verb_sym if EdgeLoader::VERB_GLOSSARY.key?(verb.to_s.downcase)
        
        nil # Unknown verb
      end

      # Get all canonical verbs
      def canonical_verbs
        verbs = CANONICAL.values.flatten.uniq
        verbs + REVERSES.keys + REVERSES.values
      end

      # Get allowed verbs for a pool pair
      def allowed_verbs(source_pool, target_pool)
        verbs = []
        
        canonical_verbs.each do |verb|
          verbs << verb if allowed?(source_pool, target_pool, verb)
        end
        
        verbs.uniq
      end

      # Validate a relationship
      def validate_relationship(source_pool, target_pool, verb)
        normalized = normalize(verb)
        
        return { valid: false, error: "Unknown verb: #{verb}" } unless normalized
        
        unless allowed?(source_pool, target_pool, normalized)
          return { 
            valid: false, 
            error: "Verb '#{verb}' not allowed for #{source_pool}→#{target_pool}" 
          }
        end
        
        { valid: true, canonical_verb: normalized }
      end
    end
  end
end