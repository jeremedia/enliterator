# frozen_string_literal: true

# Track artifacts generated during pipeline runs
class PipelineArtifact < ApplicationRecord
  belongs_to :pipeline_run
  
  # Enums
  enum :artifact_type, {
    source_file: "source_file",
    processed_file: "processed_file",
    extraction_result: "extraction_result",
    graph_export: "graph_export",
    report: "report",
    index: "index",
    deliverable: "deliverable"
  }, prefix: true
  
  # Validations
  validates :artifact_type, presence: true
  validates :file_path, presence: true
  
  # Scopes
  scope :by_type, ->(type) { where(artifact_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Instance methods
  def file_exists?
    File.exist?(file_path)
  end
  
  def file_size
    return nil unless file_exists?
    File.size(file_path)
  end
  
  def human_file_size
    return nil unless file_exists?
    size = file_size
    
    case size
    when 0..1023
      "#{size} B"
    when 1024..1_048_575
      "#{(size / 1024.0).round(2)} KB"
    when 1_048_576..1_073_741_823
      "#{(size / 1_048_576.0).round(2)} MB"
    else
      "#{(size / 1_073_741_824.0).round(2)} GB"
    end
  end
end