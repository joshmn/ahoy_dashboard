require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::SearchConsoleKeywordPresenter do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:keyword) { "fci thomson visiting" }
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d" }) }

  around { |example| travel_to(now) { example.run } }

  def keyword!(date, clicks: 3, impressions: 50, ctr: 0.06, position: 8.0)
    create(:dash_search_console_keyword, date: date, query: keyword, clicks: clicks,
           impressions: impressions, ctr: ctr, position: position)
  end

  def presenter(series: nil, range: nil)
    result = AhoyDashboard::SearchConsoleKeywordQuery.call(keyword: keyword, range: range || query.range)

    context = AhoyDashboard::SearchConsole::PageContextQuery.call(range: range || query.range, countries: true)
    described_class.new(query: query, result: result, series: series, context: context)
  end

  def figure(presented, key)
    presented.figures.find { |candidate| candidate.key == key }
  end

  describe "the figures" do
    before do
      keyword!(Date.new(2026, 8, 1), clicks: 2, impressions: 100, ctr: 0.02, position: 12.0)
      keyword!(Date.new(2026, 8, 2), clicks: 8, impressions: 100, ctr: 0.08, position: 6.0)
    end

    let(:presented) do
      presenter(range: AhoyDashboard.time_zone.local(2026, 8, 2)..AhoyDashboard.time_zone.local(2026, 8, 2).end_of_day)
    end

    it "reads clicks as a proportion of the window before it" do
      clicks = figure(presented, "clicks")

      expect(clicks.display).to eq("8")
      expect(clicks.delta).to eq(text: "300.0%", tone: :good, direction: :up)
      expect(clicks.against).to eq("2")
    end

    it "reads click through in percentage points rather than a percentage of a percentage" do
      expect(figure(presented, "ctr").delta[:text]).to eq("6.0 pts")
    end

    # Position runs the other way: a fall in the number is the keyword doing
    # better, so the colour cannot follow the sign.
    it "reads position in places and calls a fall an improvement" do
      position = figure(presented, "position")

      expect(position.display).to eq(6.0)
      expect(position.delta).to eq(text: "6.0", tone: :good, direction: :down)
    end

    it "prints no change at all when there is nothing to compare against" do
      presented = presenter

      expect(figure(presented, "clicks").delta).to be_nil
      expect(presented.comparison_note).to be_nil
    end
  end

  describe "the chart" do
    before do
      keyword!(Date.new(2026, 8, 10), clicks: 4, impressions: 200, ctr: 0.02, position: 9.4)
      keyword!(Date.new(2026, 8, 12), clicks: 1, impressions: 50, ctr: 0.02, position: 4.2)
    end

    it "draws clicks as an area with zero on the days Google said nothing" do
      presented = presenter

      expect(presented.chart_kind).to eq(:area)
      expect(presented.chart_data.first[:name]).to eq("Clicks")
      expect(presented.chart_data.first[:data].map(&:last)).to eq([ 4, 0, 1 ])
    end

    it "draws position as a line, upside down, and leaves the quiet day empty" do
      presented = presenter(series: "position")

      expect(presented.chart_kind).to eq(:line)
      expect(presented.chart_data.first[:data].map(&:last)).to eq([ 9.4, nil, 4.2 ])
      expect(presented.chart_options.dig(:library, :scales, :y, :reverse)).to be(true)
    end

    it "hands click through over as a percentage the tooltip can print" do
      presented = presenter(series: "ctr")

      expect(presented.chart_data.first[:data].map(&:last)).to eq([ 2.0, nil, 2.0 ])
      expect(presented.chart_options.dig(:library, :plugins, :tmFormat, :value)).to eq("rate")
    end

    it "falls back to clicks when the series is not one of the four" do
      expect(presenter(series: "vibes").series).to eq("clicks")
    end

    it "renders the complete series in the configured timezone" do
      with_ahoy_dashboard_settings(:site, time_zone: "America/Chicago") do
        zone = AhoyDashboard.time_zone

        expect(presenter.chart_data.first[:data])
          .to eq((10..12).zip([4, 0, 1]).map { |day, count| [zone.local(2026, 8, day), count] })
      end
    end
  end

  describe "the paths" do
    before { keyword!(Date.new(2026, 8, 10)) }

    it "carries the keyword and leaves the default series out of the url" do
      presented = presenter

      expect(figure(presented, "clicks").path).to eq(
        "/telemetry/search_console_keyword?period=30d&q=fci+thomson+visiting"
      )
      expect(figure(presented, "position").path).to eq(
        "/telemetry/search_console_keyword?period=30d&q=fci+thomson+visiting&series=position"
      )
    end

    it "keeps the series when the range changes under it" do
      urls = presenter(series: "impressions").period_options.map { |option| option[:url] }

      expect(urls).to all(include("series=impressions"))
      expect(urls).to all(include("q=fci+thomson+visiting"))
    end
  end

  describe "what it admits to" do
    it "says the record is shorter than the range asked for" do
      keyword!(Date.new(2026, 8, 10))

      expect(presenter.trim_note).to include("The keyword record runs")
    end

    it "counts the days Google said nothing about" do
      keyword!(Date.new(2026, 8, 10))
      keyword!(Date.new(2026, 8, 13))

      expect(presenter.gap_note).to include("on 2 of the 4 days")
    end

    it "points at the pull rather than the traffic when nothing is stored" do
      presented = presenter

      expect(presented).to be_empty
      expect(presented.empty_title).to eq("Nothing pulled at the keyword grain yet")
      expect(presented.empty_hint).to include("syncs every night")
      expect(presented.empty_hint).not_to include("rails")
    end
  end
end
