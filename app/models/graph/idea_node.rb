# Neo4j model for Idea nodes (Ten Pool Canon)
module Graph
  class IdeaNode < BaseNode
    # Set the Neo4j label
    self.mapped_label_name = 'Idea'
    
    # Properties
    property :name, type: String
    property :canonical, type: String
    property :description, type: String
    property :surface_forms, default: [], type: Array
    property :negative_forms, default: [], type: Array
    
    # Add unique constraint via validation
    validates :name, presence: true, uniqueness: true
    
    # Relationships
    has_many :out, :embodies, type: :EMBODIES, model_class: '::Graph::ManifestNode'
    has_many :out, :influences, type: :INFLUENCES, model_class: '::Graph::IdeaNode'
    has_many :out, :elicits, type: :ELICITS, model_class: '::Graph::ExperienceNode'
    
    # Scopes
    scope :canonical, -> { where(canonical: true) }
    scope :with_description, -> { where('n.description IS NOT NULL') }
    
    # Class methods
    def self.find_or_create_canonical(name, attributes = {})
      find_by(name: name) || create!(attributes.merge(name: name, canonical: name))
    end
    
    # Instance methods
    def add_surface_form(form)
      self.surface_forms ||= []
      self.surface_forms << form unless surface_forms.include?(form)
      save
    end
    
    def add_negative_form(form)
      self.negative_forms ||= []
      self.negative_forms << form unless negative_forms.include?(form)
      save
    end
    
    def to_s
      "Idea(#{canonical || name})"
    end
  end
end