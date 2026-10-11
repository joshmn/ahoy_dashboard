require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::View do
  it "reads a stored hash back into the view it was written from" do
    view = described_class.series(
      title: "Unique visitors, the last 7 days", points: [ [ Time.current, 1 ], [ Time.current, 2 ] ],
      metric_key: "visitors", interval: "day", path: "/telemetry", path_label: "Open on the dashboard"
    )

    read = described_class.from(view.to_h.deep_stringify_keys)

    expect(read).to be_series
    expect(read).to be_drawable
    expect(read.title).to eq("Unique visitors, the last 7 days")
    expect(read.path).to eq("/telemetry")
    expect(read.metric.key).to eq("visitors")
  end

  it "stamps a time as something a browser can parse" do
    at = Time.zone.local(2026, 8, 14)
    view = described_class.series(title: "x", points: [ [ at, 1 ], [ at, 2 ] ])

    expect(view.points.first.first).to eq(at.iso8601)
  end

  it "refuses a stored row that is not a view" do
    expect(described_class.from({ "kind" => "nonsense" })).to be_nil
  end

  it "is not drawable with one point, a table with no rows, or no figures" do
    expect(described_class.series(title: "x", points: [ [ Time.current, 1 ] ])).not_to be_drawable
    expect(described_class.table(title: "x", columns: [], rows: [])).not_to be_drawable
    expect(described_class.figures(title: "x", figures: [])).not_to be_drawable
  end
end

RSpec.describe AhoyDashboard::Assistant::Views do
  let(:collector) { described_class.new }

  def series(title)
    AhoyDashboard::Assistant::View.series(
      title: title, points: [ [ Time.current, 1 ], [ Time.current, 2 ] ]
    )
  end

  it "keeps what a tool drew, in the order it drew it" do
    collector.push(series("first")).push(series("second"))

    expect(collector.to_a.map(&:title)).to eq(%w[first second])
  end

  it "drops anything there is nothing to draw" do
    collector.push(AhoyDashboard::Assistant::View.table(title: "x", columns: [], rows: []))

    expect(collector).not_to be_any
  end

  it "stops at a handful, so one turn cannot fill the page with charts" do
    (described_class::LIMIT + 3).times { |index| collector.push(series("one #{index}")) }

    expect(collector.to_a.size).to eq(described_class::LIMIT)
  end
end

RSpec.describe "Dashboard assistant tools drawing what they read" do
  let(:collector) { AhoyDashboard::Assistant::Views.new }

  it "draws the trend as a chart and links to the dashboard over the same window" do
    AhoyDashboard::Assistant::Tools::Trend.new(views: collector).execute(metric: "visitors", days: 7)
    view = collector.to_a.first

    expect(view).to be_series
    expect(view.metric_key).to eq("visitors")
    expect(view.path).to include("period=custom", "metric=visitors", "interval=day")
  end

  it "draws the headline figures and links to the dashboard" do
    AhoyDashboard::Assistant::Tools::TrafficSummary.new(views: collector).execute(days: 7)
    view = collector.to_a.first

    expect(view).to be_figures
    expect(view.figures.map { |figure| figure[:label] }).to include("Visitors")
    expect(view.path).to include("/telemetry/?")
  end

  it "draws a breakdown as a table and links into explore on that dimension" do
    visit = Ahoy::Visit.create!(visitor_token: SecureRandom.uuid, visit_token: SecureRandom.uuid,
                               started_at: 1.day.ago)
    Ahoy::Event.create!(visit: visit, name: AhoyDashboard::PAGE_VIEW, time: 1.day.ago, properties: { path: "/x" })

    AhoyDashboard::Assistant::Tools::Breakdown.new(views: collector).execute(dimension: "page", days: 7)
    view = collector.to_a.first

    expect(view).to be_table
    expect(view).to be_drawable
    expect(view.path).to include("/telemetry/explore?", "dimension=page")
  end

  it "says nothing about drawing when it is only handing back a list" do
    AhoyDashboard::Assistant::Tools::Breakdown.new(views: collector).execute

    expect(collector).not_to be_any
  end
end
