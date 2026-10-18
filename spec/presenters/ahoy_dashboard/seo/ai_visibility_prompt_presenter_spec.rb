# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Seo::AiVisibilityPromptPresenter do
  let(:prompt) { create(:dash_ai_prompt) }

  def presenter(**options)
    reading = AhoyDashboard::AiVisibility::PromptAnswersQuery.call(prompt: prompt, **options)

    described_class.new(prompt: prompt, reading: reading, query: AhoyDashboard::QueryForm.from_params({}),
                        surface: AhoyDashboard::Seo::Surface.find("ai_visibility"))
  end

  it "orders groups by assistant and then model" do
    [["anthropic", "claude-opus-5"], ["openai", "gpt-5"], ["openai", "gpt-4.1"]].each do |assistant, model|
      create(:dash_ai_answer, prompt: prompt, assistant: assistant, model: model)
    end

    expect(presenter.groups.map { |group| [group.assistant, group.model] })
      .to eq([["openai", "gpt-4.1"], ["openai", "gpt-5"], ["anthropic", "claude-opus-5"]])
  end

  it "describes the exact total when a model has more history than fits on the page" do
    create_list(:dash_ai_answer, 3, prompt: prompt)
    shown = presenter(limit: 2)

    expect(shown.truncated_note(sole_item(shown.groups))).to eq("Showing the latest 2 of 3 answers.")
  end

  it "formats prepared answers, sources and brand mentions without database reads" do
    AhoyDashboard::Setting.write(AhoyDashboard::Seo::BrandTerms::KEY, ["Federal Prison Dude"])
    answer = create(:dash_ai_answer, prompt: prompt, text: "Ask federal-prison dude.")
    create(:dash_ai_source, answer: answer)
    shown = presenter
    statements = captured_sql(/\ASELECT/, cached: true) do
      shown.groups.each do |group|
        shown.summary(group)
        group.answers.each do |item|
          shown.paragraphs(item)
          item.sources.map(&:url)
        end
      end
    end

    expect(statements).to be_empty
  end

  it "formats answers across the configured daylight-saving boundary" do
    AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago")
    shown = presenter
    answers = [Time.utc(2026, 3, 8, 7, 30), Time.utc(2026, 3, 8, 8, 30)].map do |time|
      build(:dash_ai_answer, asked_at: time)
    end

    expect(answers.map { |answer| shown.asked_label(answer) }).to eq(["Mar 8, 2026 1:30 AM", "Mar 8, 2026 3:30 AM"])
  end

  it "uses the configured local date for a UTC time on the next day" do
    AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago")

    expect(presenter.local_date(Time.utc(2026, 3, 8, 1))).to eq(Date.new(2026, 3, 7))
  end
end
