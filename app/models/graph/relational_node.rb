# Neo4j model for Relational nodes (people, roles, relationships)
module Graph
  class RelationalNode < BaseNode
    self.mapped_label_name = 'Relational'
    
    # Properties
    property :name, type: String, constraint: :unique
    property :role, type: String
    property :affiliation, type: String
    property :years_active, type: Array[Integer], default: []
    
    # Relationships
    has_many :in, :involved_in, origin: :involves, model_class: :ExperienceNode
    has_many :out, :collaborates_with, type: :COLLABORATES_WITH, model_class: :RelationalNode
    has_many :out, :creates, type: :CREATES, model_class: :ManifestNode
    has_many :out, :participates_in, type: :PARTICIPATES_IN, model_class: :ExperienceNode
    
    validates :name, presence: true
  end
end