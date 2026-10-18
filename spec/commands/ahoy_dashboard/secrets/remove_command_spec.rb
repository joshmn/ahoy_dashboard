require "rails_helper"

RSpec.describe AhoyDashboard::Secrets::RemoveCommand do
  def call(record, key)
    described_class.call(record: record, key: key)
  end

  describe "an AI visibility assistant" do
    it "broadcasts missing when the row holds no key" do
      create(:dash_ai_assistant)

      expect(call(AhoyDashboard::AiVisibility::Assistant.for("openai"), :api_key)).to have_key(:missing)
    end
  end

  describe "an assistant provider" do
    it "broadcasts missing when the row holds no key" do
      create(:dash_assistant_provider)

      expect(call(AhoyDashboard::AssistantProvider.for("anthropic"), :api_key)).to have_key(:missing)
    end
  end

  describe "a search provider" do
    it "broadcasts missing when nothing is stored under that key" do
      create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com" })

      expect(call(AhoyDashboard::SerpProvider.for("dataforseo"), :password)).to have_key(:missing)
    end
  end

  describe "the Google OAuth client" do
    it "broadcasts missing when nothing is stored under that key" do
      store_google_client(client_id: "id", client_secret: nil)

      expect(call(AhoyDashboard::SearchConsole.credential, :client_secret)).to have_key(:missing)
    end
  end
end
