require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::Keys::RemoveCommand do
  it "deletes the stored key and keeps the rest of the row" do
    create(:dash_assistant_provider, :active, model: "claude-opus-4-6", credentials: { api_key: "stored-key" })

    events = described_class.call(name: "anthropic")

    provider = AhoyDashboard::AssistantProvider.for("anthropic")
    expect(events).to have_key(:ok)
    expect(provider.api_key).to be_nil
    expect(provider).to be_active
    expect(provider.model).to eq("claude-opus-4-6")
  end

  it "broadcasts missing when there is no row" do
    expect(described_class.call(name: "anthropic")).to have_key(:missing)
  end

  it "broadcasts missing when the row holds no key" do
    create(:dash_assistant_provider)

    expect(described_class.call(name: "anthropic")).to have_key(:missing)
  end
end
