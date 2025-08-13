# frozen_string_literal: true

# ExtractionConfig
#
# Configuration system for model-driven entity extraction.
# Allows models to declare their extraction requirements using a clean DSL.
#
# Usage:
#   class Actor < ApplicationRecord
#     include EknPoolEntity
#     
#     extraction_config do
#       canonical_name "ActorAndRole"
#       description "People and organizations with roles and permissions"
#       
#       field :name, type: :string, required: true,
#         examples: ["Dr. Sarah Johnson", "Arctic Research Institute"],
#         hints: "Look for individual names, organizations, titles"
#         
#       field :role, type: :enum, 
#         values: -> { roles.keys },  # Dynamic from model
#         default: 'individual',
#         hints: "Dr./Professor=individual, Institute=organization"
#     end
#   end
#
class ExtractionConfig
  attr_reader :model_class, :canonical_name, :description, :fields, :examples

  def initialize(model_class, &block)
    @model_class = model_class
    @canonical_name = model_class.name
    @description = "#{model_class.name} entities"
    @fields = {}
    @examples = []
    
    instance_eval(&block) if block_given?
  end

  # DSL Methods

  def canonical_name(name = nil)
    if name
      @canonical_name = name
    else
      @canonical_name
    end
  end

  def description(desc = nil)
    if desc
      @description = desc
    else
      @description
    end
  end

  def field(name, **options)
    @fields[name] = FieldConfig.new(name, model_class, **options)
  end

  def example(text)
    @examples << text
  end

  def examples(*texts)
    if texts.any?
      @examples.concat(texts)
    else
      @examples
    end
  end

  # Schema Generation

  def to_schema
    {
      canonical_name: canonical_name,
      description: description,
      fields: fields_schema,
      examples: examples,
      model_class: model_class.name
    }
  end

  def to_extraction_prompt_section
    # Pre-process the data to avoid ERB block parameter issues
    processed_fields = fields_schema.map do |field_name, field_config|
      formatted_values = field_config[:enum_values]&.any? ? 
        field_config[:enum_values].map { |v| "`#{v}`" }.join(', ') : nil
      formatted_examples = field_config[:examples]&.any? ? 
        field_config[:examples].map { |ex| "\"#{ex}\"" }.join(', ') : nil
        
      {
        name: field_name,
        type: field_config[:type],
        required: field_config[:required],
        enum_values_formatted: formatted_values,
        default: field_config[:default],
        hints: field_config[:hints],
        examples_formatted: formatted_examples
      }
    end
    
    ERB.new(extraction_prompt_template).result(binding)
  end

  private

  def fields_schema
    @fields.transform_values(&:to_schema)
  end

  def extraction_prompt_template
    <<~ERB
      ### <%= canonical_name.upcase %> 🎯
      **<%= description %>**
      
      Fields to extract:
      <% processed_fields.each do |field| %>
      - **<%= field[:name] %>**: <%= field[:type] %><%= " (REQUIRED)" if field[:required] %>
        <% if field[:enum_values_formatted] %>
        Valid values: <%= field[:enum_values_formatted] %>
        <% end %>
        <% if field[:default] %>
        Default: `<%= field[:default] %>`
        <% end %>
        <% if field[:hints] %>
        Extraction hints: <%= field[:hints] %>
        <% end %>
        <% if field[:examples_formatted] %>
        Examples: <%= field[:examples_formatted] %>
        <% end %>
      <% end %>
      
      <% if examples.any? %>
      **Entity Examples**:
      <% examples.each do |example| %>
      - "<%= example %>"
      <% end %>
      <% end %>
    ERB
  end

  # Field Configuration Class
  class FieldConfig
    attr_reader :name, :model_class, :type, :required, :examples, :hints, :default, :values_proc

    def initialize(name, model_class, type: :string, required: false, examples: [], hints: nil, default: nil, values: nil)
      @name = name
      @model_class = model_class
      @type = type
      @required = required
      @examples = Array(examples)
      @hints = hints
      @default = default
      @values_proc = values.is_a?(Proc) ? values : -> { values }
    end

    def to_schema
      schema = {
        name: name,
        type: type,
        required: required,
        examples: examples,
        hints: hints,
        default: default
      }

      # Add enum values if this is an enum field
      if enum?
        schema[:enum_values] = live_enum_values
        schema[:enum_mapping] = enum_mapping if model_class.respond_to?(:defined_enums)
      end

      schema.compact
    end

    def enum?
      type == :enum
    end

    def live_enum_values
      return [] unless enum?
      
      # Call the values proc in the model's context to get current enum values
      values = model_class.instance_exec(&@values_proc)
      return values if values.is_a?(Array)
      
      # Try to get from model's enum definition
      if model_class.respond_to?(:defined_enums) && model_class.defined_enums[name.to_s]
        model_class.defined_enums[name.to_s].keys
      else
        []
      end
    end

    def enum_mapping
      return {} unless enum? && model_class.respond_to?(:defined_enums)
      
      model_class.defined_enums[name.to_s] || {}
    end
  end
end