require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Assistants::SaveCommand do
  def form(**attributes)
    AhoyDashboard::AiVisibility::AssistantForm.new(attributes)
  end

  it "creates the row with an encrypted key and the models picked" do
    events = described_class.call(form: form(name: "gemini", models: [ "", "gemini-2.5-flash" ], credentials: { api_key: "k" }))

    assistant = events[:ok]
    expect(assistant.api_key).to eq("k")
    expect(assistant.models).to eq(%w[gemini-2.5-flash])
    expect(assistant).to be_enabled
  end

  it "keeps the stored key when none is submitted" do
    create(:dash_ai_assistant, :keyed, name: "gemini")

    described_class.call(form: form(name: "gemini", models: %w[gemini-2.5-pro], credentials: { api_key: " " }))

    assistant = AhoyDashboard::AiVisibility::Assistant.for("gemini")
    expect(assistant.api_key).to eq("stored-key")
    expect(assistant.models).to eq(%w[gemini-2.5-pro])
  end

  it "adds typed models to the ones picked, once each" do
    events = described_class.call(form: form(name: "openai", models: %w[gpt-5], other_models: "o3, gpt-5  gpt-5.1"))

    expect(events[:ok].models).to eq(%w[gpt-5 o3 gpt-5.1])
  end

  it "turns an assistant off and keeps its models" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-4.1])

    described_class.call(form: form(name: "openai", enabled: "0", models: %w[gpt-4.1]))

    assistant = AhoyDashboard::AiVisibility::Assistant.for("openai")
    expect(assistant).not_to be_enabled
    expect(assistant.models).to eq(%w[gpt-4.1])
  end

  it "wants a model while the assistant is on" do
    events = described_class.call(form: form(name: "openai", enabled: "1", models: [ "" ], other_models: " "))

    expect(events[:invalid].errors[:models]).to eq([ "need at least one, or turn ChatGPT off" ])
    expect(AhoyDashboard::AiVisibility::Assistant.count).to be_zero
  end

  it "refuses a typed model that is not a model name" do
    events = described_class.call(form: form(name: "openai", models: %w[gpt-5], other_models: "gpt-5;drop"))

    expect(events[:invalid].errors[:models]).to eq([ "gpt-5;drop is not a model name" ])
  end

  it "broadcasts invalid for an assistant it does not know" do
    expect(described_class.call(form: form(name: "copilot"))).to have_key(:invalid)
    expect(AhoyDashboard::AiVisibility::Assistant.count).to be_zero
  end
end
