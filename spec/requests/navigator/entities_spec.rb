require 'rails_helper'

RSpec.describe "Navigator::Entities", type: :request do
  describe "GET /show" do
    it "returns http success" do
      get "/navigator/entities/show"
      expect(response).to have_http_status(:success)
    end
  end

end
