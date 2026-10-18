require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsolePresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }

  def row(label: "fci thomson", clicks: 3, impressions: 40, ctr: 0.075, position: 8.44)
    AhoyDashboard::SearchConsoleQuery::Row.new(
      label: label, clicks: clicks, impressions: impressions, ctr: ctr, position: position
    )
  end

  def coverage_of(counted_clicks: 3, counted_impressions: 40, total_clicks: 10, total_impressions: 200)
    AhoyDashboard::SearchConsoleQuery::Coverage.new(
      counted_clicks: counted_clicks, counted_impressions: counted_impressions,
      total_clicks: total_clicks, total_impressions: total_impressions
    )
  end

  def result(rows: [ row ], totals: nil, coverage: coverage_of, connected: true)
    AhoyDashboard::SearchConsoleQuery::Result.new(
      range: query.range,
      queries: rows,
      pages: rows,
      totals: totals || AhoyDashboard::SearchConsoleQuery::Totals.new(
        clicks: 1_234, impressions: 20_000, ctr: 0.0617, position: 9.15
      ),
      coverage: coverage,
      connected: connected
    )
  end

  def presenter(**options)
    described_class.new(query: query, result: result(**options))
  end

  describe "the numbers" do
    it "reads ctr as the fraction Google sends and prints a percent" do
      expect(presenter.rows.first.values["ctr"]).to eq("7.5%")
    end

    it "keeps a small ctr off zero" do
      expect(presenter(rows: [ row(ctr: 0.003) ]).rows.first.values["ctr"]).to eq("0.3%")
    end

    it "rounds an average position to one place" do
      expect(presenter.rows.first.values["position"]).to eq(8.4)
    end

    it "delimits clicks and impressions" do
      values = presenter(rows: [ row(clicks: 1_234, impressions: 45_678) ]).rows.first.values

      expect(values["clicks"]).to eq("1,234")
      expect(values["impressions"]).to eq("45,678")
    end
  end

  describe "the rows" do
    it "names a withheld query rather than showing a blank" do
      expect(presenter(rows: [ row(label: "") ]).rows.first.display_label).to eq("(anonymized)")
    end

    it "scales the bar against the busiest row" do
      shares = presenter(rows: [ row(clicks: 10), row(clicks: 5) ]).rows.map(&:share)

      expect(shares).to eq([ 1.0, 0.5 ])
    end

    it "asks for no bar at all when nothing was clicked" do
      expect(presenter(rows: [ row(clicks: 0) ]).rows.first.share).to eq(0.0)
    end
  end

  describe "the coverage note" do
    it "says how much of the clicks the rows account for" do
      note = presenter.coverage_note

      expect(note).to include("30.0% of the clicks")
      expect(note).to include("7 clicks have no query")
    end

    it "names both causes of the gap, not just the anonymized queries" do
      note = presenter.coverage_note

      expect(note).to include("hides searches that were rare or that look personal")
      expect(note).to include("only sends the ones with the most clicks")
    end

    it "keeps the framing that the totals are the number to trust" do
      expect(presenter.coverage_note).to include("The totals are right")
    end

    it "is nil when the rows account for everything" do
      complete = coverage_of(counted_clicks: 10, counted_impressions: 200,
                             total_clicks: 10, total_impressions: 200)

      expect(presenter(coverage: complete).coverage_note).to be_nil
    end

    it "is nil when there is nothing to measure against" do
      nothing = coverage_of(counted_clicks: 0, counted_impressions: 0,
                            total_clicks: 0, total_impressions: 0)

      expect(presenter(coverage: nothing).coverage_note).to be_nil
    end
  end

  describe "the tabs" do
    it "opens on queries and labels the column for it" do
      expect(presenter.tab).to eq("queries")
      expect(presenter.label_column).to eq("Query")
    end

    it "falls back to queries on a tab nobody has" do
      expect(described_class.new(query: query, result: result, tab: "banana").tab).to eq("queries")
    end

    it "marks the tab that is showing" do
      showing = described_class.new(query: query, result: result, tab: "pages").tabs

      expect(showing.select(&:active?).map(&:value)).to eq([ "pages" ])
    end
  end

  describe "the frames" do
    it "names the card frame and the details frame apart" do
      expect(presenter.frame_id).to eq("report_search_console")
      expect(described_class.new(query: query, result: result, details: true).frame_id)
        .to eq("report_details_search_console")
    end
  end
end
