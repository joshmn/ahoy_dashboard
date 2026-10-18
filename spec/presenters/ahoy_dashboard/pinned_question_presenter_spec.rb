# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::PinnedQuestionPresenter do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def presenter(metric: "visitors", period: "day", change: 0)
    question = build(:dash_saved_query, name: "My question", params: { "period" => period, "metric" => metric })
    form = AhoyDashboard::QueryForm.from_params(question.to_query)
    reading = AhoyDashboard::PinnedQuestionsQuery::Reading.new(question: question, metric: form.metric,
      value: 2500, change: change, period: form.period, range: form.range, series: [1.0, 2.0])

    described_class.new(reading: reading)
  end

  it "formats the metric reading for the card" do
    expect(presenter.display).to eq("2,500")
  end

  it "describes the equal elapsed portion of an ongoing comparison" do
    expect(presenter.against).to eq("yesterday by this hour")
  end

  it "describes the whole preceding period for a finished range" do
    expect(presenter(period: "yesterday").against).to eq("the day before")
  end

  it "treats a falling bounce rate as an improvement" do
    expect(presenter(metric: "bounce_rate", change: -50).delta).to include(tone: :good, direction: :down)
  end

  it "treats a rising bounce rate as a decline" do
    expect(presenter(metric: "bounce_rate", change: 50).delta).to include(tone: :bad, direction: :up)
  end

  it "keeps the saved query parameters in the card URL" do
    params = Rack::Utils.parse_nested_query(URI.parse(presenter(metric: "bounce_rate").path).query)

    expect(params).to include("period" => "day", "metric" => "bounce_rate")
  end
end
