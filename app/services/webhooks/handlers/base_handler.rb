# frozen_string_literal: true

module Webhooks
  module Handlers
    class BaseHandler
      attr_reader :webhook_event
      
      def initialize(webhook_event)
        @webhook_event = webhook_event
      end
      
      def process
        raise NotImplementedError, "Subclasses must implement the process method"
      end
      
      protected
      
      def event_type
        webhook_event.event_type
      end
      
      def data
        webhook_event.data
      end
      
      def resource_id
        webhook_event.resource_id
      end
      
      def payload
        webhook_event.payload
      end
      
      def log_info(message)
        Rails.logger.info "[#{self.class.name}] #{message}"
      end
      
      def log_error(message)
        Rails.logger.error "[#{self.class.name}] #{message}"
      end
      
      def update_metadata(key, value)
        webhook_event.metadata ||= {}
        webhook_event.metadata[key] = value
        webhook_event.save!
      end
    end
  end
end