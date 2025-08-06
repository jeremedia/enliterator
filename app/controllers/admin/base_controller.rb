# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :ensure_admin_access
    
    layout 'admin'
    
    private
    
    def ensure_admin_access
      # For now, just ensure we're in development
      # In production, implement proper authentication
      unless Rails.env.development? || Rails.env.test?
        redirect_to root_path, alert: 'Admin access required'
      end
    end
  end
end