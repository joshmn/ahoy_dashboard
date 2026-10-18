require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Runs::StartCommand do
  include ActiveJob::TestHelper

  before { switch_on_ahoy_dashboard(:ai_visibility) }

  it "reserves capacity before any queued requests are performed" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
    create(:dash_ai_prompt)
    create(:dash_ai_assistant, :keyed)
    described_class.call(trigger: :manual)

    expect(described_class.call(trigger: :manual)).to have_key(:over_cap)
  end

  it "does not treat reserved requests as finished answers" do
    create(:dash_ai_prompt)
    create(:dash_ai_assistant, :keyed)

    run = described_class.call(trigger: :manual).fetch(:ok)

    expect(run).not_to be_finished
  end

  it "does nothing while switched off" do
    switch_off_ahoy_dashboard(:ai_visibility)
    create(:dash_ai_assistant, :keyed)
    create(:dash_ai_prompt)

    expect(described_class.call(trigger: :manual)).to have_key(:disabled)
    expect(AhoyDashboard::AiVisibility::Run.count).to be_zero
  end

  it "does nothing without an assistant holding a key" do
    create(:dash_ai_assistant)
    create(:dash_ai_prompt)

    expect(described_class.call(trigger: :manual)).to have_key(:no_assistants)
  end

  it "does nothing without prompts" do
    create(:dash_ai_assistant, :keyed)

    expect(described_class.call(trigger: :manual)).to have_key(:no_prompts)
  end

  it "does nothing when every keyed assistant is off" do
    create(:dash_ai_assistant, :keyed, enabled: false)
    create(:dash_ai_prompt)

    expect(described_class.call(trigger: :manual)).to have_key(:no_assistants)
  end

  it "enqueues one job per prompt per model of each assistant that is on and keyed, and records the run" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-5 gpt-4.1])
    create(:dash_ai_assistant, :keyed, name: "gemini")
    create(:dash_ai_assistant, :keyed, name: "anthropic", enabled: false)
    create(:dash_ai_assistant, name: "perplexity")
    prompts = create_list(:dash_ai_prompt, 2)

    events = nil
    expect { events = described_class.call(trigger: :manual) }
      .to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob).exactly(6).times

    run = events[:ok]
    expect(run).to be_queued
    expect(run).to be_triggered_by_manual
    expect(run.requests).to eq(6)
    prompts.each do |prompt|
      expect(AhoyDashboard::AiVisibility::Prompts::RunJob).to have_been_enqueued.with(run.id, prompt.id, "openai", "gpt-5")
      expect(AhoyDashboard::AiVisibility::Prompts::RunJob).to have_been_enqueued.with(run.id, prompt.id, "openai", "gpt-4.1")
      expect(AhoyDashboard::AiVisibility::Prompts::RunJob).to have_been_enqueued.with(run.id, prompt.id, "gemini", "gemini-2.5-flash")
    end
  end

  it "counts only a key stored on the screen as keyed" do
    stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "from-env", "OPENAI_API_KEY" => "from-env"))
    create(:dash_ai_prompt)

    expect(described_class.call(trigger: :schedule)).to have_key(:no_assistants)
    expect(AhoyDashboard::AiVisibility::Prompts::RunJob).not_to have_been_enqueued
  end

  it "skips a run that does not fit in what is left of the cap and sends none of it" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 3)
    prompts = create_list(:dash_ai_prompt, 3)
    create(:dash_ai_answer, prompt: prompts.first, asked_at: Time.current)
    create(:dash_ai_assistant, :keyed)

    events = nil
    expect { events = described_class.call(trigger: :manual) }.not_to have_enqueued_job(AhoyDashboard::AiVisibility::Prompts::RunJob)

    run = events[:over_cap]
    expect(run).to be_skipped
    expect(run.skip_reason).to eq("A run needs 3 requests and 2 are left this month.")
  end

  it "runs regardless of use when the cap is zero" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 0)
    prompt = create(:dash_ai_prompt)
    create_list(:dash_ai_answer, 3, prompt: prompt, asked_at: Time.current)
    create(:dash_ai_assistant, :keyed)

    expect(described_class.call(trigger: :manual)).to have_key(:ok)
  end

  it "does not count last month's answers against this month's cap" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
    prompt = create(:dash_ai_prompt)
    create(:dash_ai_answer, prompt: prompt, asked_at: 2.months.ago)
    create(:dash_ai_assistant, :keyed)

    expect(described_class.call(trigger: :manual)).to have_key(:ok)
  end
end
