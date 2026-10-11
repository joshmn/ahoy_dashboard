require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Prompts::RunJob do
  it "is on the low queue" do
    expect(described_class.new.queue_name).to eq("low")
  end

  it "hands the run, prompt, assistant and model to the command" do
    run = create(:dash_ai_run)
    prompt = create(:dash_ai_prompt)
    allow(AhoyDashboard::AiVisibility::Answers::RecordCommand).to receive(:call)

    described_class.perform_now(run.id, prompt.id, "gemini", "gemini-2.5-pro")

    expect(AhoyDashboard::AiVisibility::Answers::RecordCommand).to have_received(:call)
      .with(run: run, prompt: prompt, assistant: "gemini", model: "gemini-2.5-pro")
  end

  it "asks the assistant's first model when a job queued before models existed has none" do
    run = create(:dash_ai_run)
    prompt = create(:dash_ai_prompt)
    create(:dash_ai_assistant, name: "gemini", models: %w[gemini-2.5-pro])
    allow(AhoyDashboard::AiVisibility::Answers::RecordCommand).to receive(:call)

    described_class.perform_now(run.id, prompt.id, "gemini")

    expect(AhoyDashboard::AiVisibility::Answers::RecordCommand).to have_received(:call)
      .with(run: run, prompt: prompt, assistant: "gemini", model: "gemini-2.5-pro")
  end

  it "does nothing when the prompt was deleted after the run started" do
    run = create(:dash_ai_run)
    allow(AhoyDashboard::AiVisibility::Answers::RecordCommand).to receive(:call)

    described_class.perform_now(run.id, 0, "openai")

    expect(AhoyDashboard::AiVisibility::Answers::RecordCommand).not_to have_received(:call)
  end
end
