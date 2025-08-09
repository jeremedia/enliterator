require 'rails_helper'

RSpec.describe "Navigator::Edges", type: :request do
  describe "GET /promote" do
    it "returns http success" do
      get "/navigator/edges/promote"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /reject" do
    it "returns http success" do
      get "/navigator/edges/reject"
      expect(response).to have_http_status(:success)
    end
  end

end
