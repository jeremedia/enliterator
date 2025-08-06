require 'rails_helper'

RSpec.describe "Admin::PromptTemplates", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/prompt_templates/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get "/admin/prompt_templates/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/admin/prompt_templates/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/admin/prompt_templates/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/admin/prompt_templates/update"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /destroy" do
    it "returns http success" do
      get "/admin/prompt_templates/destroy"
      expect(response).to have_http_status(:success)
    end
  end

end
