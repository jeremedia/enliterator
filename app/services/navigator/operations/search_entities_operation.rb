module Navigator
  module Operations
    class SearchEntitiesOperation < BaseOperation
      def initialize(ekn, query)
        super(ekn)
        @query = query
      end
      
      def execute
        return { error: "No search query provided" } if @query.blank?
        return { error: "No EKN loaded" } unless @ekn
        
        results = graph_service.search_entities(@query)
        
        {
          success: true,
          query: @query,
          results: results,
          count: results.size
        }
      rescue => e
        Rails.logger.error "SearchEntitiesOperation error: #{e.message}"
        { error: "Search failed", details: e.message }
      end
    end
  end
end