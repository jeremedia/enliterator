# frozen_string_literal: true

# EknPoolEntity Concern
#
# Shared behavior for all Ten Pool Canon entity models.
# Provides unified extraction configuration, graph syncing, and common attributes.
#
# Usage:
#   class Actor < ApplicationRecord
#     include EknPoolEntity
#     
#     extraction_config do
#       canonical_name "ActorAndRole"
#       description "People and organizations with roles and permissions"
#       field :name, type: :string, required: true
#       field :role, type: :enum, values: -> { roles.keys }
#     end
#   end
#
module EknPoolEntity
  extend ActiveSupport::Concern

  included do
    # Common associations for all pool entities
    belongs_to :provenance_and_rights

    # Common attributes (these should exist in all pool entity tables)
    validates :repr_text, presence: true
    validates :valid_time_start, presence: true

    # Automatic graph synchronization
    after_commit :sync_to_graph, on: [:create, :update]
    after_commit :remove_from_graph, on: :destroy

    # Scope for finding entities by EKN
    scope :for_ekn, ->(ekn) {
      joins(:provenance_and_rights)
        .where(provenance_and_rights: { source_ids: ekn.source_id_patterns })
    }
  end

  class_methods do
    # Define extraction configuration for this pool entity
    # 
    # Example:
    #   extraction_config do
    #     canonical_name "ActorAndRole"
    #     description "People and organizations with roles and permissions"
    #     field :name, type: :string, required: true
    #     field :role, type: :enum, values: -> { roles.keys }, default: 'individual'
    #   end
    def extraction_config(&block)
      if block_given?
        @extraction_config = ExtractionConfig.new(self, &block)
      else
        @extraction_config ||= ExtractionConfig.new(self)
      end
    end

    # Generate extraction schema from live model
    # Returns hash with all information needed for dynamic prompt generation
    def to_extraction_schema
      config = extraction_config
      {
        model_class: self,
        canonical_name: config.canonical_name,
        description: config.description,
        table_name: table_name,
        fields: config.fields,
        enums: live_enum_values,
        examples: config.examples,
        validation_rules: extraction_validation_rules
      }
    end

    # Extract live enum values from model
    def live_enum_values
      defined_enums.transform_values(&:keys)
    end

    # Extract validation rules relevant to extraction
    def extraction_validation_rules
      validators.map do |validator|
        case validator
        when ActiveRecord::Validations::PresenceValidator
          { type: :presence, attributes: validator.attributes }
        when ActiveRecord::Validations::LengthValidator
          { type: :length, attributes: validator.attributes, options: validator.options }
        # Note: Other validators can be added as needed
        end
      end.compact
    end

    # Canonical pool name for this entity (override in model if needed)
    def canonical_pool_name
      extraction_config.canonical_name || name.demodulize
    end

    # Pool description for extraction prompts
    def pool_description
      extraction_config.description || "#{name} entities"
    end
  end

  # Instance methods

  # Sync this entity to the Neo4j knowledge graph
  def sync_to_graph
    return false unless should_sync_to_graph?

    begin
      writer_class_name = "Graph::#{self.class.name}Writer"
      writer_class = writer_class_name.constantize
      writer = writer_class.new(self)
      
      Rails.logger.info "Syncing #{self.class.name} #{id} to Neo4j via #{writer_class_name}"
      result = writer.sync
      
      if result
        Rails.logger.debug "Successfully synced #{self.class.name} #{id} to Neo4j"
      else
        Rails.logger.warn "Failed to sync #{self.class.name} #{id} to Neo4j"
      end
      
      result
    rescue NameError => e
      Rails.logger.warn "Graph writer not found for #{self.class.name}: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "Error syncing #{self.class.name} #{id} to Neo4j: #{e.message}"
      false
    end
  end

  # Remove this entity from the Neo4j knowledge graph
  def remove_from_graph
    # TODO: Implement graph node deletion
    # This would need to connect to Neo4j and remove the node with this ID
    Rails.logger.info "Would remove #{self.class.name} #{id} from Neo4j (not implemented)"
    true
  end

  # Determine if this entity should be synced to the graph
  def should_sync_to_graph?
    # Only sync if we have valid provenance and the entity is ready
    provenance_and_rights.present? && 
    valid_time_start.present? && 
    repr_text.present?
  end

  # Get the EKN this entity belongs to (via provenance chain)
  def ekn
    return @ekn if defined?(@ekn)
    
    @ekn = if provenance_and_rights&.source_ids&.any?
      # Try to determine EKN from source IDs
      # This is a heuristic and may need refinement
      Ekn.find_by(slug: 'arctic-research') || Ekn.first
    else
      nil
    end
  end

  # Display name for this entity (override in models as needed)
  def display_name
    respond_to?(:name) ? name : repr_text
  end

  # Full description combining all relevant fields
  def full_description
    parts = []
    parts << display_name if display_name.present?
    parts << "(#{role})" if respond_to?(:role) && role.present?
    parts << description if respond_to?(:description) && description.present?
    parts.join(' ')
  end
end