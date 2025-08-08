class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  before_action :set_current_user_for_models
  
  private
  
  def set_current_user_for_models
    # Set the current user in Thread.current for models to access
    ApiCall.current_user = current_user
  end
end
