# frozen_string_literal: true

module Pipeline
  # Relation Verb Glossary from the spec
  # Defines allowed relationships between pool entities
  module VerbGlossary
    VERBS = {
      'embodies' => { source: 'Idea', target: 'Manifest', reverse: 'is_embodiment_of' },
      'elicits' => { source: 'Manifest', target: 'Experience', reverse: 'is_elicited_by' },
      'influences' => { source: %w[Idea Emanation], target: '*', reverse: 'is_influenced_by' },
      'refines' => { source: 'Evolutionary', target: 'Idea', reverse: 'is_refined_by' },
      'version_of' => { source: 'Evolutionary', target: 'Manifest', reverse: 'has_version' },
      'co_occurs_with' => { source: 'Relational', target: 'Relational', symmetric: true },
      'located_at' => { source: 'Manifest', target: 'Spatial', reverse: 'hosts' },
      'adjacent_to' => { source: 'Spatial', target: 'Spatial', symmetric: true },
      'validated_by' => { source: 'Practical', target: 'Experience', reverse: 'validates' },
      'supports' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'refutes' => { source: 'Evidence', target: 'Idea', reverse: nil },
      'diffuses_through' => { source: 'Emanation', target: 'Relational', reverse: nil }
    }.freeze
  end
end