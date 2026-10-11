require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Answers::ClaimService do
  it "requires capacity for older jobs that have no reserved answer" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
    create(:dash_ai_answer)
    run = create(:dash_ai_run)
    prompt = create(:dash_ai_prompt)

    expect(described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5", now: Time.current))
      .to be_nil
  end

  it "charges a delayed request against the month in which it starts" do
    answer = create(:dash_ai_answer, status: :pending, asked_at: 2.months.ago)

    described_class.call(run: answer.run, prompt: answer.prompt, assistant: answer.assistant,
                         model: answer.model, now: Time.current)

    expect(AhoyDashboard::AiVisibility.used_this_month).to eq(1)
  end

  it "refuses a delayed request if the new month's capacity is exhausted" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
    create(:dash_ai_answer)
    answer = create(:dash_ai_answer, status: :pending, asked_at: 2.months.ago)

    described_class.call(run: answer.run, prompt: answer.prompt, assistant: answer.assistant,
                         model: answer.model, now: Time.current)

    expect(answer.reload).to be_failed
  end
end
