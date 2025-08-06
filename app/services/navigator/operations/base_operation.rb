# Base class for all conversation operations
module Navigator
  module Operations
    class BaseOperation
      attr_reader :ekn, :params
      
      def initialize(ekn = nil, params = {})
        @ekn = ekn
        @params = params
      end
      
      def execute
        raise NotImplementedError, "Subclasses must implement execute"
      end
      
      protected
      
      def graph_service
        @graph_service ||= Graph::QueryService.new(@ekn&.id || 7)
      end
    end
  end
end