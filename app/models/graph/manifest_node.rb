# Neo4j model for Manifest nodes (physical/tangible things)
module Graph
  class ManifestNode < BaseNode
    # Set the Neo4j label
    self.mapped_label_name = 'Manifest'
    
    # Properties
    property :name, type: String, constraint: :unique
    property :canonical, type: String
    property :description, type: String
    property :manifest_type, type: String # camp, art, structure, vehicle, etc.
    property :location, type: Hash # spatial data
    property :year, type: Integer
    property :size, type: String
    property :capacity, type: Integer
    
    # Relationships
    has_many :in, :embodied_by, origin: :embodies, model_class: :IdeaNode
    has_many :out, :hosts, type: :HOSTS, model_class: :ExperienceNode
    has_many :out, :contains, type: :CONTAINS, model_class: :ManifestNode
    has_many :in, :contained_by, origin: :contains, model_class: :ManifestNode
    has_many :out, :neighbors, type: :NEIGHBORS, model_class: :ManifestNode
    
    # Validations
    validates :name, presence: true
    validates :year, numericality: { greater_than: 1986 }, allow_nil: true
    
    # Scopes
    scope :camps, -> { where(manifest_type: 'camp') }
    scope :art, -> { where(manifest_type: 'art') }
    scope :by_year, ->(year) { where(year: year) }
    scope :with_location, -> { where_not(location: nil) }
    
    # Spatial queries
    def self.near(location, radius_meters: 100)
      # This would use Neo4j spatial features
      # For now, return all with locations
      with_location
    end
    
    # Instance methods
    def coordinates
      return nil unless location
      [location['lat'], location['lng']]
    end
    
    def add_neighbor(other_manifest)
      neighbors << other_manifest unless neighbors.include?(other_manifest)
    end
    
    def to_s
      "Manifest(#{canonical || name}#{year ? " #{year}" : ""})"
    end
  end
end