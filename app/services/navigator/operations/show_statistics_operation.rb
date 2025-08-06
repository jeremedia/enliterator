module Navigator
  module Operations
    class ShowStatisticsOperation < BaseOperation
      def execute
        return { error: "No EKN loaded" } unless @ekn
        
        stats = graph_service.get_statistics
        
        {
          success: true,
          data: stats,
          summary: generate_summary(stats)
        }
      rescue => e
        Rails.logger.error "ShowStatisticsOperation error: #{e.message}"
        { error: "Unable to fetch statistics", details: e.message }
      end
      
      private
      
      def generate_summary(stats)
        total = stats[:total_nodes] || 0
        types = stats[:nodes_by_type] || {}
        
        "Your knowledge graph contains #{total} nodes across #{types.keys.count} types"
      end
    end
  end
end