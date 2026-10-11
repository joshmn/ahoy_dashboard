require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::ReportQuery do
  let(:range) { 7.days.ago..Time.current }
  let(:prompt) { create(:dash_ai_prompt) }

  def answer(**attributes)
    create(:dash_ai_answer, prompt: prompt, **attributes)
  end

  it "counts successful answers only, and reads rates off them" do
    answer(assistant: "openai", mentioned: true, cited: true, position: 2)
    answer(assistant: "anthropic", mentioned: true)
    answer(assistant: "gemini")
    answer(assistant: "perplexity", status: "failed", text: nil, mentioned: true)

    result = described_class.call(range: range)

    expect(result.answers).to eq(3)
    expect(result.mentioned).to eq(2)
    expect(result.cited).to eq(1)
    expect(result.failed).to eq(1)
    expect(result.mention_rate).to be_within(0.001).of(2.0 / 3)
    expect(result.citation_rate).to be_within(0.001).of(1.0 / 3)
  end

  it "leaves out answers outside the range" do
    answer(asked_at: 30.days.ago, mentioned: true)

    expect(described_class.call(range: range).answers).to eq(0)
  end

  it "narrows to one assistant" do
    answer(assistant: "openai", mentioned: true)
    answer(assistant: "anthropic")

    result = described_class.call(range: range, assistant: "anthropic")

    expect(result.answers).to eq(1)
    expect(result.mentioned).to eq(0)
    expect(result.by_assistant.map(&:assistant)).to eq([ "anthropic" ])
  end

  it "breaks the numbers down by assistant with the average position when cited" do
    answer(assistant: "openai", mentioned: true, cited: true, position: 1)
    answer(assistant: "openai", mentioned: true, cited: true, position: 4)
    answer(assistant: "openai")

    row = described_class.call(range: range).by_assistant.first

    expect([ row.answers, row.mentioned, row.cited ]).to eq([ 3, 2, 2 ])
    expect(row.average_position).to eq(2.5)
    expect(row.mention_rate).to be_within(0.001).of(2.0 / 3)
  end

  it "counts a prompt as missing when no assistant's latest answer mentions you, even if an older one did" do
    answer(assistant: "openai", mentioned: true, asked_at: 3.days.ago)
    answer(assistant: "openai", mentioned: false, asked_at: 1.day.ago)
    answer(assistant: "anthropic", mentioned: false, asked_at: 1.day.ago)

    missing = described_class.call(range: range).missing_prompts

    expect(missing.map(&:prompt)).to eq([ prompt ])
    expect(missing.first.asked).to eq(2)
  end

  it "reads each model's latest answer on its own when deciding a prompt is missing" do
    answer(assistant: "openai", model: "gpt-5", mentioned: true, asked_at: 1.day.ago)
    answer(assistant: "openai", model: "gpt-4.1", mentioned: false, asked_at: 1.hour.ago)

    expect(described_class.call(range: range).missing_prompts).to be_empty
  end

  it "breaks rows and the daily series down by model, and narrows to one" do
    answer(assistant: "openai", model: "gpt-5", mentioned: true)
    answer(assistant: "openai", model: "gpt-4.1")
    answer(assistant: "anthropic", model: "claude-opus-5", mentioned: true)

    result = described_class.call(range: range)

    expect(result.by_assistant.map { |row| [ row.assistant, row.model, row.mentioned ] })
      .to eq([ [ "openai", "gpt-4.1", 0 ], [ "openai", "gpt-5", 1 ], [ "anthropic", "claude-opus-5", 1 ] ])
    expect(result.series.map { |point| [ point.assistant, point.model ] })
      .to contain_exactly([ "openai", "gpt-5" ], [ "openai", "gpt-4.1" ], [ "anthropic", "claude-opus-5" ])

    narrowed = described_class.call(range: range, assistant: "openai", model: "gpt-5")
    expect([ narrowed.answers, narrowed.mentioned ]).to eq([ 1, 1 ])
  end

  it "does not count a prompt as missing when one assistant's latest answer mentions you" do
    answer(assistant: "openai", mentioned: false, asked_at: 3.days.ago)
    answer(assistant: "openai", mentioned: true, asked_at: 1.day.ago)
    answer(assistant: "anthropic", mentioned: false, asked_at: 1.day.ago)

    expect(described_class.call(range: range).missing_prompts).to be_empty
  end

  it "ranks the other domains by how many answers cite them" do
    first = answer
    second = answer(assistant: "anthropic")
    create(:dash_ai_source, answer: first, slot: 1, domain: "big.example")
    create(:dash_ai_source, answer: first, slot: 2, domain: "big.example", url: "https://big.example/two")
    create(:dash_ai_source, answer: second, slot: 1, domain: "big.example")
    create(:dash_ai_source, answer: second, slot: 2, domain: "small.example")
    create(:dash_ai_source, answer: second, slot: 3, domain: "ours.example", ours: true)

    rows = described_class.call(range: range).cited_instead

    expect(rows.map(&:domain)).to eq([ "big.example", "small.example" ])
    expect(rows.first.answers).to eq(2)
    expect(rows.first.share).to eq(1.0)
    expect(rows.last.share).to eq(0.5)
  end

  it "reads the mention rate per assistant per day" do
    answer(assistant: "openai", mentioned: true, asked_at: 2.days.ago)
    answer(assistant: "openai", mentioned: false, asked_at: 2.days.ago)

    point = described_class.call(range: range).series.first

    expect([ point.assistant, point.answers, point.mentioned ]).to eq([ "openai", 2, 1 ])
    expect(point.rate).to eq(0.5)
  end

  it "finds the latest run the cap skipped" do
    create(:dash_ai_run, status: "skipped", skip_reason: "A run needs 8 requests and 2 are left this month.", started_at: 1.day.ago)

    expect(described_class.call(range: range).skipped_run.skip_reason).to include("8 requests")
  end
end
