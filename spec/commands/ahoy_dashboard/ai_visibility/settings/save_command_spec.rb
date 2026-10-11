require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Settings::SaveCommand do
  def form(**attributes)
    AhoyDashboard::AiVisibility::SettingsForm.new({ frequency: "weekly", monthly_cap: 200 }.merge(attributes))
  end

  it "saves the prompts, the frequency and the cap" do
    events = described_class.call(form: form(prompts: "one\ntwo", frequency: "daily", monthly_cap: 30))

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::AiVisibility::Prompt.ordered.pluck(:text, :position)).to eq([ [ "one", 0 ], [ "two", 1 ] ])
    expect(AhoyDashboard::AiVisibility.frequency).to eq("daily")
    expect(AhoyDashboard::AiVisibility.monthly_cap).to eq(30)
  end

  it "keeps a prompt whose case changed, with its answers, and takes the new wording" do
    prompt = create(:dash_ai_prompt, text: "Best consultant")
    create(:dash_ai_answer, prompt: prompt)

    events = described_class.call(form: form(prompts: "best consultant"))

    expect(events).to have_key(:ok)
    expect(prompt.reload.text).to eq("best consultant")
    expect(prompt.answers.count).to eq(1)
  end

  it "broadcasts the prompts at stake with their answer counts instead of deleting them" do
    doomed = create(:dash_ai_prompt, text: "gone")
    create_list(:dash_ai_answer, 3, prompt: doomed)

    events = described_class.call(form: form(prompts: "new"))

    form_back, stake = events[:confirm_deletions]
    expect(form_back).to be_a(AhoyDashboard::AiVisibility::SettingsForm)
    expect(stake.map { |item| [ item.prompt.text, item.answers ] }).to eq([ [ "gone", 3 ] ])
    expect(AhoyDashboard::AiVisibility::Prompt.pluck(:text)).to eq([ "gone" ])
  end

  it "deletes them and their answers when confirmed" do
    doomed = create(:dash_ai_prompt, text: "gone")
    create(:dash_ai_answer, prompt: doomed)

    events = described_class.call(form: form(prompts: "", confirm: true))

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::AiVisibility::Prompt.count).to be_zero
    expect(AhoyDashboard::AiVisibility::Answer.count).to be_zero
  end

  it "broadcasts invalid and saves nothing" do
    events = described_class.call(form: form(prompts: "one", monthly_cap: nil))

    expect(events).to have_key(:invalid)
    expect(AhoyDashboard::AiVisibility::Prompt.count).to be_zero
  end
end
