require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Keys::RemoveCommand do
  it "deletes the stored key and keeps the row and models" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-4.1])

    events = described_class.call(name: "openai")

    assistant = AhoyDashboard::AiVisibility::Assistant.for("openai")
    expect(events).to have_key(:ok)
    expect(assistant.api_key).to be_nil
    expect(assistant.models).to eq(%w[gpt-4.1])
  end

  it "broadcasts missing when there is no row" do
    expect(described_class.call(name: "openai")).to have_key(:missing)
  end

  it "broadcasts missing when the row holds no key" do
    create(:dash_ai_assistant)

    expect(described_class.call(name: "openai")).to have_key(:missing)
  end
end
