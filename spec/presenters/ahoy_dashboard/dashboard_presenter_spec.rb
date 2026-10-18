require "rails_helper"

RSpec.describe AhoyDashboard::DashboardPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }
  let(:metric) { AhoyDashboard::Metric.find("visitors") }

  def tile(value:, comparison:, change: nil)
    stat = AhoyDashboard::TopStatsQuery::Stat.new(
      metric: metric, value: value, comparison_value: comparison, change: change
    )

    described_class.new(query: query, stats: [ stat ]).tiles.first
  end

  describe "the change pill on a tile" do
    it "says New when the previous period had none and this one has some" do
      expect(tile(value: 5, comparison: 0).delta).to include(text: "New", tone: :new)
    end

    it "prints nothing when both periods had none" do
      expect(tile(value: 0, comparison: 0).delta).to be_nil
    end

    it "prints nothing when there is no comparison" do
      expect(tile(value: 5, comparison: nil).delta).to be_nil
    end

    it "keeps the percent change for a real change" do
      expect(tile(value: 15, comparison: 10, change: 50).delta).to include(text: "50%", tone: :good, direction: :up)
    end
  end

  describe "the change pill against a running range" do
    let(:now) { dash_time(2026, 8, 11, 14, 30) }
    let(:query) { AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" }) }

    around { |example| travel_to(now) { example.run } }

    it "says the number is held against yesterday by this hour" do
      expect(tile(value: 15, comparison: 10, change: 50).delta[:title]).to eq("vs 10, yesterday by this hour")
    end

    it "labels the switch the same way" do
      expect(described_class.new(query: query).comparison_label).to eq("vs yesterday by this hour")
    end

    it "keeps the plain label once the range is over" do
      finished = AhoyDashboard::QueryForm.from_params({ period: "yesterday", comparison: "previous_period" })

      expect(described_class.new(query: finished).comparison_label).to eq("Previous period")
    end

    it "calls today so far" do
      expect(query.period_label).to eq("Today so far")
    end
  end

  describe "the comparison switch beside the tiles" do
    it "offers the previous period while nothing is being compared" do
      presenter = described_class.new(query: query)

      expect(presenter).not_to be_comparing
      expect(presenter.comparison_switch_label).to eq("Previous period")
      expect(presenter.comparison_switch_path).to include("comparison=previous_period")
    end

    it "names the comparison on and takes it off when one is" do
      comparing = AhoyDashboard::QueryForm.from_params({ period: "yesterday", comparison: "year_over_year" })
      presenter = described_class.new(query: comparing)

      expect(presenter).to be_comparing
      expect(presenter.comparison_switch_label).to eq("Year over year")
      expect(presenter.comparison_switch_path).not_to include("comparison=")
    end
  end

  describe "the chart payload" do
    let(:now) { dash_time(2026, 8, 11, 14, 30) }

    around { |example| travel_to(now) { example.run } }

    it "formats prepared annotations without reading the database during rendering" do
      note = create(:dash_annotation, happened_at: now)
      presenter = described_class.new(query: query, annotations: [note])
      query.range
      AhoyDashboard.time_zone
      expect(captured_sql(cached: true) { presenter.chart_options }).to be_empty
    end

    it "includes supplied annotation labels and local timestamps in the chart payload" do
      note = create(:dash_annotation, label: "Release", happened_at: now)
      presenter = described_class.new(query: query, annotations: [note])

      expect(presenter.annotations).to include(hash_including(label: "Release", at: now.iso8601))
    end

    it "marks the last bucket as still filling in when the range includes now" do
      format = described_class.new(query: query).chart_options.dig(:library, :plugins, :tmFormat)

      expect(format[:partial]).to be(true)
    end

    it "stops the line at the bucket that is still filling in" do
      day = AhoyDashboard::QueryForm.from_params({ period: "day", comparison: "previous_period" })
      series = 24.times.map { |hour| [ now.change(hour: hour), hour ] }
      comparison = 15.times.map { |hour| [ (now - 1.day).change(hour: hour), hour * 2 ] }
      data = described_class.new(query: day, series: series, comparison_series: comparison).chart_data

      expect(data.first[:data].map(&:last)).to eq((0..14).to_a)
      expect(data.first[:data].last.first).to eq(now.change(hour: 14))
      expect(data.last[:name]).to start_with("Yesterday by this hour")
      expect(data.last[:data].size).to eq(15)
    end
  end

  describe "picking a range off the chart" do
    let(:now) { dash_time(2026, 8, 11, 14, 30) }

    around { |example| travel_to(now) { example.run } }

    def selection(params, selectable: true)
      form = AhoyDashboard::QueryForm.from_params(params)

      described_class.new(query: form, selectable: selectable).chart_options.dig(:library, :plugins, :tmSelect)
    end

    it "names the dates the chart is drawing, in the dashboard's own zone" do
      expect(selection({ period: "7d" })).to include(from: "2026-08-05", to: "2026-08-11")
    end

    it "gives the dates of a custom range back as they were asked for" do
      expect(selection({ period: "custom", from: "2026-06-02", to: "2026-06-20" }))
        .to include(from: "2026-06-02", to: "2026-06-20")
    end

    it "leaves the dates and the grouping to the chart" do
      url = selection({ period: "custom", from: "2026-06-02", to: "2026-06-20", interval: "week" })[:url]
      params = Rack::Utils.parse_nested_query(URI.parse(url).query)

      expect(params).to include("period" => "custom")
      expect(params.keys).not_to include("from", "to", "interval")
    end

    it "offers nothing unless the page asks for it" do
      expect(selection({ period: "30d" }, selectable: false)).to be_nil
    end

    it "offers a single day and realtime, since a drag across either picks times" do
      %w[day yesterday realtime].each do |period|
        expect(selection({ period: period })).to be_present, "expected a range to pick on #{period}"
      end
    end

    it "offers nothing on a range one minute long" do
      expect(selection({ period: "custom", from: "2026-08-10T09:00", to: "2026-08-10T09:01" })).to be_nil
    end

    it "keeps the key out of the payload entirely when there is nothing to offer" do
      options = described_class.new(query: query).chart_options

      expect(options.dig(:library, :plugins)).not_to have_key(:tmSelect)
    end
  end
end
