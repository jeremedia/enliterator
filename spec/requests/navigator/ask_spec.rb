require 'rails_helper'

RSpec.describe "Navigator::Asks", type: :request do
  describe "GET /show" do
    it "returns http success" do
      get "/navigator/ask/show"
      expect(response).to have_http_status(:success)
    end
  end

end
