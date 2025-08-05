class WelcomeController < ApplicationController
  def index
    @host = request.host
    @port = request.port
    @protocol = request.protocol
    @environment = Rails.env
    @pipeline_status = check_pipeline_status
  end

  private

  def check_pipeline_status
    {
      batches: IngestBatch.count,
      ideas: Idea.count,
      manifests: Manifest.count,
      experiences: Experience.count,
      embeddings: Embedding.count,
      graph_nodes: check_neo4j_count
    }
  rescue => e
    { error: e.message }
  end

  def check_neo4j_count
    result = Rails.configuration.neo4j_driver.session do |session|
      session.run("MATCH (n) RETURN count(n) as count LIMIT 1").single
    end
    result[:count]
  rescue
    0
  end
end