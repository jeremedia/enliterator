# Neo4j model for Evolutionary nodes (changes, progressions, histories)
module Graph
  class EvolutionaryNode < BaseNode
    self.mapped_label_name = 'Evolutionary'
    
    # Properties
    property :name, type: String, constraint: :unique
    property :phase, type: String
    property :from_year, type: Integer
    property :to_year, type: Integer
    property :description, type: String
    property :changes, type: Array[String], default: []
    
    # Relationships
    has_many :out, :evolves_into, type: :EVOLVES_INTO, model_class: :EvolutionaryNode
    has_many :in, :evolved_from, origin: :evolves_into, model_class: :EvolutionaryNode
    has_many :out, :transforms, type: :TRANSFORMS, model_class: [:IdeaNode, :ManifestNode]
    
    validates :name, presence: true
  end
end