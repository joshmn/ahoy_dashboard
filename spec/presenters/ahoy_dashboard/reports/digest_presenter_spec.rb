require "rails_helper"

RSpec.describe AhoyDashboard::Reports::DigestPresenter do
  def stat(key, value, comparison = nil)
    AhoyDashboard::TopStatsQuery.stat(metric: AhoyDashboard::Metric.find(key), value: value,
                                      comparison_value: comparison)
  end

  def window(period, starts_on, ends_on)
    AhoyDashboard::Reports::Digests::Window.new(period: period, starts_on: starts_on, ends_on: ends_on)
  end

  def result(window:, stats: [], lists: [])
    AhoyDashboard::Reports::DigestQuery::Result.new(window: window, stats: stats, lists: lists)
  end

  def present(window:, stats: [], lists: [])
    described_class.new(result(window: window, stats: stats, lists: lists), host: "federalprisondude.com")
  end

  describe "the subject" do
    it "names a day" do
      view = present(window: window(:daily, Date.new(2026, 9, 18), Date.new(2026, 9, 18)),
                     stats: [ stat("visitors", 1_204) ])

      expect(view.subject).to eq("Traffic for Sep 18: 1,204 visitors")
    end

    it "names both ends of a week" do
      view = present(window: window(:weekly, Date.new(2026, 9, 8), Date.new(2026, 9, 14)),
                     stats: [ stat("visitors", 12) ])

      expect(view.subject).to eq("Traffic for Sep 8 to Sep 14: 12 visitors")
    end

    it "names the month" do
      view = present(window: window(:monthly, Date.new(2026, 8, 1), Date.new(2026, 8, 31)),
                     stats: [ stat("visitors", 1) ])

      expect(view.subject).to eq("Traffic for August: 1 visitor")
    end
  end

  describe "the line under the headline" do
    def summary(value, comparison, views: 0)
      present(window: window(:weekly, Date.new(2026, 9, 8), Date.new(2026, 9, 14)),
              stats: [ stat("visitors", value, comparison), stat("pageviews", views, nil) ]).summary
    end

    it "says which way it went and against what" do
      expect(summary(120, 100, views: 400)).to eq("Up 20% on the week before. 400 pageviews in all.")
    end

    it "says so when it fell" do
      expect(summary(80, 100)).to eq("Down 20% on the week before.")
    end

    it "says level rather than up nothing" do
      expect(summary(100, 100)).to eq("Level with the week before.")
    end

    it "admits there is nothing behind it yet" do
      expect(summary(100, 0)).to eq("There is nothing to compare it with yet.")
    end

    it "says nothing came in, and whether that is new" do
      expect(summary(0, 40)).to eq("Nothing came in. 40 visitors the week before.")
      expect(summary(0, 0)).to eq("Nothing came in, and nothing came in the week before either.")
    end
  end

  describe "the tiles" do
    # Bounce rate is the one that reads the other way round, which is the whole
    # reason the colour comes off the metric rather than off the sign.
    it "colours a falling bounce rate as the good news and a falling visitor count as the bad" do
      view = present(window: window(:daily, Date.new(2026, 9, 18), Date.new(2026, 9, 18)),
                     stats: [ stat("visitors", 80, 100), stat("bounce_rate", 40.0, 50.0) ])
      visitors, bounce = view.tiles

      expect(visitors).to have_attributes(change: "-20%", direction: :down, color: described_class::DOWN)
      expect(bounce).to have_attributes(change: "-20%", direction: :down, color: described_class::UP)
    end

    it "leaves the change off when there is nothing behind it" do
      view = present(window: window(:daily, Date.new(2026, 9, 18), Date.new(2026, 9, 18)),
                     stats: [ stat("visitors", 80) ])

      expect(sole_item(view.tiles)).to have_attributes(value: "80", change: nil, direction: :none)
    end
  end

  it "drops a list with nothing in it rather than printing an empty heading" do
    lists = [
      AhoyDashboard::Reports::DigestQuery::List.new(
        key: :pages, title: "Top pages", dimension: AhoyDashboard::Dimension.find("page"),
        rows: [ AhoyDashboard::Reports::DigestQuery::Row.new(label: "/faq", value: "/faq", visitors: 3, share: 60.0) ]
      ),
      AhoyDashboard::Reports::DigestQuery::List.new(
        key: :sources, title: "Top sources", dimension: AhoyDashboard::Dimension.find("source"), rows: []
      )
    ]
    view = present(window: window(:daily, Date.new(2026, 9, 18), Date.new(2026, 9, 18)),
                   stats: [ stat("visitors", 5) ], lists: lists)

    expect(view.lists.map(&:key)).to eq([ :pages ])
    expect(sole_item(sole_item(view.lists).rows)).to have_attributes(label: "/faq", value: "3 visitors", share: 60)
    expect(view).not_to be_nothing_listed
  end

  it "says why there is nothing to list when nobody came" do
    view = present(window: window(:daily, Date.new(2026, 9, 18), Date.new(2026, 9, 18)),
                   stats: [ stat("visitors", 0) ])

    expect(view).to be_nothing_listed
    expect(view.nothing_listed_note).to eq("Nobody came, so there is nothing to list.")
  end

  it "says who it is for and what it covers" do
    view = present(window: window(:monthly, Date.new(2026, 8, 1), Date.new(2026, 8, 31)),
                   stats: [ stat("visitors", 5) ])

    expect(view.cadence).to eq("Monthly")
    expect(view.period_heading).to eq("August 2026")
    expect(view.footer).to eq("You get this monthly because traffic emails are on for federalprisondude.com.")
  end
end
