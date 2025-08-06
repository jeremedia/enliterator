# frozen_string_literal: true

module Admin
  class OpenaiSettingsController < BaseController
    before_action :set_setting, only: [:edit, :update, :destroy]
    
    def index
      @model_settings = OpenaiSetting.models.order(:model_type)
      @temperature_settings = OpenaiSetting.temperatures.order(:key)
      @config_settings = OpenaiSetting.configs.order(:key)
      @all_settings = OpenaiSetting.all.order(:category, :key)
      
      # Cost tracking
      @usage_stats = calculate_usage_stats
    end
    
    def new
      @setting = OpenaiSetting.new
    end
    
    def create
      @setting = OpenaiSetting.new(setting_params)
      
      if @setting.save
        redirect_to admin_openai_settings_path, notice: 'Setting created successfully'
      else
        render :new, status: :unprocessable_entity
      end
    end
    
    def edit
    end
    
    def update
      if @setting.update(setting_params)
        redirect_to admin_openai_settings_path, notice: 'Setting updated successfully'
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def destroy
      @setting.destroy
      redirect_to admin_openai_settings_path, notice: 'Setting deleted'
    end
    
    def test_model
      model = params[:model]
      task_type = params[:task_type] || 'extraction'
      
      result = test_model_with_sample(model, task_type)
      
      render json: result
    end
    
    def reset_defaults
      OpenaiConfig::SettingsManager.create_default_settings!
      redirect_to admin_openai_settings_path, notice: 'Default settings restored'
    end
    
    private
    
    def set_setting
      @setting = OpenaiSetting.find(params[:id])
    end
    
    def setting_params
      params.require(:openai_setting).permit(:key, :value, :category, :model_type, :description, :active)
    end
    
    def calculate_usage_stats
      {
        today_cost: 0.0,
        month_cost: 0.0,
        batch_savings: 0.0,
        models_configured: OpenaiSetting.models.active.count,
        templates_active: PromptTemplate.active.count
      }
    end
    
    def test_model_with_sample(model, task_type)
      # Simple test to verify model is accessible
      begin
        response = OPENAI.models.retrieve(id: model)
        {
          success: true,
          model: model,
          owner: response.owned_by,
          created: Time.at(response.created).iso8601,
          task_type: task_type,
          message: "Model #{model} is available and ready for #{task_type} tasks"
        }
      rescue => e
        {
          success: false,
          error: e.message,
          model: model,
          task_type: task_type
        }
      end
    end
  end
end