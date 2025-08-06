require 'rails_helper'

RSpec.describe "Webhooks::Openais", type: :request do
  describe "GET /receive" do
    it "returns http success" do
      get "/webhooks/openai/receive"
      expect(response).to have_http_status(:success)
    end
  end

end
