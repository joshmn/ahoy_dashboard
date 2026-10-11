require "rails_helper"

RSpec.describe "Dashboard assistant kept dimensions", type: :request do
  def withheld
    AhoyDashboard::Assistant.withheld_keys
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/assistant_dimensions/edit"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      patch "/telemetry/settings/assistant_dimensions", params: { assistant_dimensions: { keys: %w[city] } }

      expect(response).to have_http_status(:not_found)
      expect(withheld).to be_empty
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "offers every dimension, with the kept ones ticked" do
      AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city])

      get "/telemetry/settings/assistant_dimensions/edit"

      expect(response).to have_http_status(:ok)
      boxes = Nokogiri::HTML5(response.body).css("input[type=checkbox][name='assistant_dimensions[keys][]']")
      expect(boxes.map { |box| box["value"] }).to include("city", "country", "entry_url", "referrer")
      expect(boxes.select { |box| box["checked"] }.map { |box| box["value"] }).to eq(%w[city])
    end

    it "saves what is ticked and lists it on the assistant screen" do
      patch "/telemetry/settings/assistant_dimensions", params: { assistant_dimensions: { keys: [ "", "referrer", "city" ] } }

      expect(response).to redirect_to("/telemetry/settings/assistant_providers")
      expect(withheld).to eq(%w[city referrer])
      expect(AhoyDashboard::Assistant).to be_withheld("city")

      get "/telemetry/settings/assistant_providers"
      kept = Nokogiri::HTML5(response.body).css("[aria-label='Kept from the assistant'] li").map { |item| item.text.strip }
      expect(kept).to eq(%w[city referrer])
    end

    it "hands everything back when nothing is ticked" do
      AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city])

      patch "/telemetry/settings/assistant_dimensions", params: { assistant_dimensions: { keys: [ "" ] } }

      expect(withheld).to be_empty
    end

    it "keeps a property that is no longer offered rather than quietly handing it back" do
      AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[prop:email])

      patch "/telemetry/settings/assistant_dimensions", params: { assistant_dimensions: { keys: %w[city] } }

      expect(withheld).to eq(%w[city prop:email])
    end

    it "refuses a dimension the dashboard does not have" do
      patch "/telemetry/settings/assistant_dimensions", params: { assistant_dimensions: { keys: %w[shoe_size] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("shoe_size")
      expect(withheld).to be_empty
    end
  end
end
