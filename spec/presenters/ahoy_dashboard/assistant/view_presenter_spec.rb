require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::ViewPresenter do
  def presenter(*figures)
    described_class.new(AhoyDashboard::Assistant::View.figures(title: "Traffic", figures: figures))
  end

  def tone(figure)
    view = presenter(figure)

    view.delta(view.figures.first)[:tone]
  end

  it "reads a fall in bounce rate as good news, the same as the dashboard tile" do
    expect(tone(label: "Bounce rate", value: "40%", change: -10, metric_key: "bounce_rate")).to eq(:good)
    expect(tone(label: "Bounce rate", value: "40%", change: 10, metric_key: "bounce_rate")).to eq(:bad)
  end

  it "reads a rise in visitors as good news" do
    expect(tone(label: "Visitors", value: "120", change: 10, metric_key: "visitors")).to eq(:good)
    expect(tone(label: "Visitors", value: "120", change: -10, metric_key: "visitors")).to eq(:bad)
  end

  it "keeps the old reading for a figure stored before it named its metric" do
    expect(tone(label: "Bounce rate", value: "40%", change: -10)).to eq(:bad)
    expect(tone(label: "Bounce rate", value: "40%", change: -10, metric_key: "nonsense")).to eq(:bad)
  end

  it "says nothing about a figure with no comparison" do
    view = presenter(label: "Visitors", value: "120", change: nil, metric_key: "visitors")

    expect(view.delta(view.figures.first)).to be_nil
  end

  it "keeps the metric through the round trip into the database" do
    stored = AhoyDashboard::Assistant::View.figures(
      title: "Traffic", figures: [ { label: "Bounce rate", value: "40%", change: -10, metric_key: "bounce_rate" } ]
    ).to_h.deep_stringify_keys
    view = described_class.new(AhoyDashboard::Assistant::View.from(stored))

    expect(view.delta(view.figures.first)[:tone]).to eq(:good)
  end

  it "is handed the metric by the traffic summary tool" do
    collector = AhoyDashboard::Assistant::Views.new
    AhoyDashboard::Assistant::Tools::TrafficSummary.new(views: collector).execute(days: 7)
    figures = collector.to_a.first.figures

    expect(figures.map { |figure| figure[:metric_key] }).to eq(AhoyDashboard::Metric::ALL.map(&:key))
  end
end
