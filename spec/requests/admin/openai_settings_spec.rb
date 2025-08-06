require 'rails_helper'

RSpec.describe "Admin::OpenaiSettings", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/openai_settings/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/admin/openai_settings/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/admin/openai_settings/update"
      expect(response).to have_http_status(:success)
    end
  end

end
