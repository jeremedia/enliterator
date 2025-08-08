# frozen_string_literal: true

# Concern to track the current user in API calls and other models
module CurrentUserTrackable
  extend ActiveSupport::Concern
  
  class_methods do
    # Get the current user from Thread.current
    def current_user
      Thread.current[:current_user]
    end
    
    # Set the current user in Thread.current
    def current_user=(user)
      Thread.current[:current_user] = user
    end
    
    # Clear the current user from Thread.current
    def clear_current_user
      Thread.current[:current_user] = nil
    end
    
    # Execute a block with a specific user context
    def with_user(user)
      old_user = current_user
      self.current_user = user
      yield
    ensure
      self.current_user = old_user
    end
  end
  
  included do
    before_create :set_user_from_current
    
    private
    
    def set_user_from_current
      if respond_to?(:user_id=) && user_id.nil?
        self.user_id = self.class.current_user&.id
      end
    end
  end
end