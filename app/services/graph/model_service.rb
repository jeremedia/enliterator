# Service for working with ActiveGraph models in database-per-EKN architecture
module Graph
  class ModelService
    attr_reader :ekn, :database_name
    
    def initialize(ekn)
      @ekn = ekn
      @database_name = ekn.neo4j_database_name
      
      # Ensure database exists
      ekn.ensure_neo4j_database_exists!
      
      # Configure ActiveGraph to use this database
      configure_models_for_database
    end
    
    # Pool filling methods using ActiveGraph models
    
    def create_idea(attributes)
      with_database do
        IdeaNode.create!(attributes)
      end
    end
    
    def create_manifest(attributes)
      with_database do
        ManifestNode.create!(attributes)
      end
    end
    
    def create_experience(attributes)
      with_database do
        ExperienceNode.create!(attributes)
      end
    end
    
    def find_or_create_idea(name, attributes = {})
      with_database do
        IdeaNode.find_or_create_canonical(name, attributes)
      end
    end
    
    # Relationship creation
    
    def link_idea_to_manifest(idea_name, manifest_name)
      with_database do
        idea = IdeaNode.find_by(name: idea_name)
        manifest = ManifestNode.find_by(name: manifest_name)
        
        if idea && manifest
          idea.embodies << manifest unless idea.embodies.include?(manifest)
          true
        else
          false
        end
      end
    end
    
    def link_manifest_to_experience(manifest_name, experience_title)
      with_database do
        manifest = ManifestNode.find_by(name: manifest_name)
        experience = ExperienceNode.find_by(title: experience_title)
        
        if manifest && experience
          manifest.hosts << experience unless manifest.hosts.include?(experience)
          true
        else
          false
        end
      end
    end
    
    # Query methods
    
    def ideas(limit: 100)
      with_database do
        IdeaNode.limit(limit).to_a
      end
    end
    
    def manifests(limit: 100)
      with_database do
        ManifestNode.limit(limit).to_a
      end
    end
    
    def experiences(limit: 100, publishable_only: false)
      with_database do
        scope = ExperienceNode
        scope = scope.publishable if publishable_only
        scope.limit(limit).to_a
      end
    end
    
    def search(query, pools: [], limit: 10)
      with_database do
        results = []
        
        if pools.empty? || pools.include?('idea')
          results += IdeaNode.where("name =~ '(?i).*#{query}.*'").limit(limit).to_a
        end
        
        if pools.empty? || pools.include?('manifest')
          results += ManifestNode.where("name =~ '(?i).*#{query}.*'").limit(limit).to_a
        end
        
        if pools.empty? || pools.include?('experience')
          results += ExperienceNode.where("title =~ '(?i).*#{query}.*'").limit(limit).to_a
        end
        
        results.first(limit)
      end
    end
    
    # Path finding using ActiveGraph relationships
    
    def find_path(from_node, to_node, max_length: 3)
      with_database do
        # Use Neo4j's shortest path algorithm
        query = <<~CYPHER
          MATCH path = shortestPath(
            (from {name: $from_name})-[*..#{max_length}]-(to {name: $to_name})
          )
          RETURN path
        CYPHER
        
        result = ActiveGraph::Base.query(query, from_name: from_node, to_name: to_node)
        format_path(result.first) if result.any?
      end
    end
    
    # Statistics
    
    def statistics
      with_database do
        {
          ideas: IdeaNode.count,
          manifests: ManifestNode.count,
          experiences: ExperienceNode.count,
          publishable_experiences: ExperienceNode.publishable.count,
          training_eligible: ExperienceNode.training_eligible.count
        }
      end
    end
    
    private
    
    def configure_models_for_database
      # Configure all models to use this EKN's database
      [IdeaNode, ManifestNode, ExperienceNode].each do |model_class|
        model_class.use_database(@database_name)
      end
    end
    
    def with_database(&block)
      # Execute block with the correct database context
      # ActiveGraph handles the database switching internally
      yield
    rescue => e
      Rails.logger.error "Graph::ModelService error in database #{@database_name}: #{e.message}"
      raise
    end
    
    def format_path(path_result)
      return nil unless path_result
      
      nodes = path_result.nodes.map do |node|
        {
          name: node.name || node.title,
          type: node.labels.first
        }
      end
      
      relationships = path_result.relationships.map(&:type)
      
      {
        nodes: nodes,
        relationships: relationships,
        text: generate_path_text(nodes, relationships)
      }
    end
    
    def generate_path_text(nodes, relationships)
      parts = []
      nodes.each_with_index do |node, i|
        parts << "#{node[:type]}(#{node[:name]})"
        parts << "→#{relationships[i]}→" if i < relationships.size
      end
      parts.join(' ')
    end
  end
end