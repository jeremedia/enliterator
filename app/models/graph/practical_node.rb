# Neo4j model for Practical nodes (tools, methods, processes)
module Graph
  class PracticalNode < BaseNode
    self.mapped_label_name = 'Practical'
    
    # Properties
    property :name, type: String, constraint: :unique
    property :method_type, type: String # tool, process, technique, framework
    property :description, type: String
    property :requirements, type: Array[String], default: []
    property :outcomes, type: Array[String], default: []
    
    # Relationships
    has_many :out, :enables, type: :ENABLES, model_class: [:ManifestNode, :ExperienceNode]
    has_many :out, :requires, type: :REQUIRES, model_class: :PracticalNode
    has_many :in, :required_by, origin: :requires, model_class: :PracticalNode
    
    validates :name, presence: true
    validates :method_type, inclusion: { in: %w[tool process technique framework] }
  end
end