# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::PromptAnswersQuery do
  let(:prompt) { create(:dash_ai_prompt) }
  let(:now) { Time.current.change(usec: 0) }

  context "with several models and historical answers" do
    let!(:groups) do
      [["openai", "gpt-5"], ["openai", "gpt-4.1"], ["anthropic", "claude-opus-5"]].map do |assistant, model|
        create_list(:dash_ai_answer, 3, prompt: prompt, assistant: assistant, model: model, asked_at: now - 40.days).each do |answer|
          create(:dash_ai_source, answer: answer)
        end
      end
    end

    it "bounds each model independently with deterministic newest-first ordering" do
      reading = described_class.call(prompt: prompt, limit: 2)

      expect(reading.answers.map(&:id)).to eq(groups.flat_map { |group| group.last(2) }.map(&:id).sort.reverse)
    end

    it "keeps exact totals before limiting each model" do
      expect(described_class.call(prompt: prompt, limit: 2).answers.map { |answer| answer[:prompt_answer_count] })
        .to eq([3] * 6)
    end

    it "preloads every retained answer's sources" do
      expect(described_class.call(prompt: prompt, limit: 2).answers.map { |answer| answer.association(:sources) })
        .to all(be_loaded)
    end

    it "reads all retained answers and their sources in two SQL statements" do
      statements = []
      subscriber = lambda do |*, payload|
        statements << payload[:sql] if payload[:sql].match?(/\ASELECT.*ahoy_dashboard_ai_visibility_(answers|sources)/m)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        described_class.call(prompt: prompt, limit: 2)
      end

      expect(statements.size).to eq(2)
    end
  end

  it "filters prompt, assistant and model before counting" do
    wanted = create(:dash_ai_answer, prompt: prompt, model: "gpt-5")
    create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1")
    create(:dash_ai_answer, model: "gpt-5")

    expect(sole_item(described_class.call(prompt: prompt, assistant: "openai", model: "gpt-5").answers))
      .to have_attributes(id: wanted.id, prompt_answer_count: 1)
  end

  it "keeps all models when no assistant is selected" do
    create(:dash_ai_answer, prompt: prompt, model: "gpt-5")
    create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1")

    expect(described_class.call(prompt: prompt, model: "gpt-5").answers.map(&:model)).to contain_exactly("gpt-5", "gpt-4.1")
  end

  it "excludes in-flight reservations from history and totals" do
    create(:dash_ai_answer, prompt: prompt, status: "pending")
    create(:dash_ai_answer, prompt: prompt, status: "processing")
    completed = create(:dash_ai_answer, :failed, prompt: prompt)

    expect(described_class.call(prompt: prompt).answers).to contain_exactly(completed)
  end

  it "caps requested history at one hundred per model" do
    create_list(:dash_ai_answer, 101, prompt: prompt)

    expect(described_class.call(prompt: prompt, limit: 500).answers.size).to eq(100)
  end

  it "prepares the current host and stored brand terms for highlighting" do
    AhoyDashboard::Preferences.write(:site, host: "https://example.com")
    AhoyDashboard::Setting.write(AhoyDashboard::Seo::BrandTerms::KEY, ["Example Brand"])

    expect(described_class.call(prompt: prompt).terms).to eq(["example.com", "Example Brand"])
  end
end
