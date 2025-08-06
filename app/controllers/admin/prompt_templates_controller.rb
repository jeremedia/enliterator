# frozen_string_literal: true

module Admin
  class PromptTemplatesController < BaseController
    before_action :set_template, only: [:show, :edit, :update, :destroy, :duplicate, :activate, :test]
    
    def index
      @templates = PromptTemplate.all.order(:purpose, :name)
      @templates_by_purpose = @templates.group_by(&:purpose)
    end
    
    def show
    end
    
    def new
      @template = PromptTemplate.new
      @template.active = true
    end
    
    def create
      @template = PromptTemplate.new(template_params)
      
      if @template.save
        redirect_to admin_prompt_templates_path, notice: 'Prompt template created successfully'
      else
        render :new, status: :unprocessable_entity
      end
    end
    
    def edit
    end
    
    def update
      if @template.update(template_params)
        redirect_to admin_prompt_templates_path, notice: 'Prompt template updated successfully'
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def destroy
      @template.destroy
      redirect_to admin_prompt_templates_path, notice: 'Prompt template deleted'
    end
    
    def duplicate
      new_name = "#{@template.name} (Copy)"
      new_template = @template.duplicate!(new_name)
      
      redirect_to edit_admin_prompt_template_path(new_template), 
                  notice: 'Template duplicated. Please update the name and settings.'
    end
    
    def activate
      @template.update!(active: !@template.active)
      status = @template.active? ? 'activated' : 'deactivated'
      
      redirect_to admin_prompt_templates_path, notice: "Template #{status}"
    end
    
    def test
      sample_content = params[:sample_content] || "Sample content for testing"
      sample_variables = params[:variables] || {}
      
      result = @template.test_with_sample(sample_content, sample_variables)
      
      render json: result
    end
    
    private
    
    def set_template
      @template = PromptTemplate.find(params[:id])
    end
    
    def template_params
      params.require(:prompt_template).permit(
        :name, :service_class, :purpose, :system_prompt, 
        :user_prompt_template, :active, variables: [], metadata: {}
      )
    end
  end
end