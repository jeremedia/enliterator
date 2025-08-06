# Neo4j model for Emanation nodes (outputs, artifacts, deliverables)
module Graph
  class EmanationNode < BaseNode
    self.mapped_label_name = 'Emanation'
    
    # Properties
    property :name, type: String, constraint: :unique
    property :artifact_type, type: String # document, media, code, design
    property :format, type: String
    property :created_date, type: DateTime
    property :file_path, type: String
    property :metadata, type: Hash, default: {}
    
    # Relationships
    has_many :in, :produced_by, origin: :produces, model_class: [:ExperienceNode, :PracticalNode]
    has_many :out, :derives_from, type: :DERIVES_FROM, model_class: [:IdeaNode, :ManifestNode]
    has_many :out, :references, type: :REFERENCES, model_class: :EmanationNode
    
    validates :name, presence: true
    validates :artifact_type, inclusion: { in: %w[document media code design data] }
  end
end