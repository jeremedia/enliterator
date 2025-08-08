# frozen_string_literal: true

# Concern for tracking the current EKN context across API calls
module CurrentEknTrackable
  extend ActiveSupport::Concern
  
  included do
    before_save :set_current_ekn_and_session
  end
  
  class_methods do
    def current_ekn
      Thread.current[:current_ekn]
    end
    
    def current_ekn=(ekn)
      Thread.current[:current_ekn] = ekn
    end
    
    def current_session
      Thread.current[:current_session]
    end
    
    def current_session=(session)
      Thread.current[:current_session] = session
    end
    
    # Set EKN context for a block of code
    def with_ekn_context(ekn, session = nil)
      old_ekn = Thread.current[:current_ekn]
      old_session = Thread.current[:current_session]
      
      Thread.current[:current_ekn] = ekn
      Thread.current[:current_session] = session
      
      yield
    ensure
      Thread.current[:current_ekn] = old_ekn
      Thread.current[:current_session] = old_session
    end
  end
  
  private
  
  def set_current_ekn_and_session
    if self.respond_to?(:ekn_id) && ekn_id.nil?
      self.ekn_id = self.class.current_ekn&.id
    end
    
    if self.respond_to?(:session_id) && session_id.nil?
      self.session_id = self.class.current_session&.id
    end
  end
end