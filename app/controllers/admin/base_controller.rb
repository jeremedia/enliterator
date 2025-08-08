# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin_access
    
    layout 'admin'
    
    private
    
    def ensure_admin_access
      unless current_user&.admin?
        redirect_to root_path, alert: 'Admin access required'
      end
    end
  end
end