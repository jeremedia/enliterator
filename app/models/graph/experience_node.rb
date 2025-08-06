# Neo4j model for Experience nodes (events, stories, testimonials)
module Graph
  class ExperienceNode < BaseNode
    # Set the Neo4j label
    self.mapped_label_name = 'Experience'
    
    # Properties
    property :title, type: String, constraint: :unique
    property :content, type: String
    property :experience_type, type: String # story, event, testimonial, interaction
    property :occurred_at, type: DateTime
    property :year, type: Integer
    property :sentiment, type: Float # -1.0 to 1.0
    property :participants, type: Array[String], default: []
    property :tags, type: Array[String], default: []
    property :publishable, type: Boolean, default: false
    property :training_eligible, type: Boolean, default: false
    
    # Relationships
    has_many :in, :elicited_by, origin: :elicits, model_class: :IdeaNode
    has_many :in, :hosted_by, origin: :hosts, model_class: :ManifestNode
    has_many :out, :involves, type: :INVOLVES, model_class: :RelationalNode
    has_many :out, :leads_to, type: :LEADS_TO, model_class: :ExperienceNode
    has_many :in, :led_from, origin: :leads_to, model_class: :ExperienceNode
    
    # Validations
    validates :title, presence: true
    validates :experience_type, inclusion: { 
      in: %w[story event testimonial interaction observation ritual] 
    }
    validates :sentiment, numericality: { 
      greater_than_or_equal_to: -1.0, 
      less_than_or_equal_to: 1.0 
    }, allow_nil: true
    
    # Scopes
    scope :publishable, -> { where(publishable: true) }
    scope :training_eligible, -> { where(training_eligible: true) }
    scope :stories, -> { where(experience_type: 'story') }
    scope :events, -> { where(experience_type: 'event') }
    scope :by_year, ->(year) { where(year: year) }
    scope :positive, -> { where('sentiment > 0') }
    scope :negative, -> { where('sentiment < 0') }
    
    # Rights-aware queries
    def self.for_public_use
      publishable.where(training_eligible: false)
    end
    
    def self.for_training
      training_eligible
    end
    
    # Instance methods
    def add_participant(name)
      self.participants ||= []
      self.participants << name unless participants.include?(name)
      save
    end
    
    def add_tag(tag)
      self.tags ||= []
      self.tags << tag.downcase unless tags.include?(tag.downcase)
      save
    end
    
    def temporal_description
      if occurred_at
        occurred_at.strftime("%B %d, %Y at %l:%M %p")
      elsif year
        "Sometime in #{year}"
      else
        "Date unknown"
      end
    end
    
    def to_s
      "Experience(#{title}#{year ? " #{year}" : ""})"
    end
  end
end