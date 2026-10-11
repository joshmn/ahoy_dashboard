require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Reports::DigestQuery do
  let(:window) do
    AhoyDashboard::Reports::Digests::Window.new(period: :daily, starts_on: Date.new(2026, 8, 10),
                                                ends_on: Date.new(2026, 8, 10))
  end

  subject(:result) { described_class.call(window: window) }

  def visitor(day, token, path: "/", **attributes)
    at = dash_time(2026, 8, day, 9)
    visit = dash_visit(started_at: at, visitor: token, **attributes)
    dash_page_view(visit, path: path, at: at)
    visit
  end

  before do
    visitor(10, "a", path: "/going-to-federal-prison")
    visitor(10, "b", path: "/going-to-federal-prison")
    third = visitor(10, "c", path: "/for-families", referrer: "https://www.google.com/",
                    referring_domain: "google.com")
    dash_page_view(third, path: "/for-families/visiting", at: dash_time(2026, 8, 10, 9, 5))

    visitor(9, "d")
  end

  it "counts the window and the window before it" do
    expect(dash_value(result.stats, "visitors")).to eq(3)
    expect(dash_value(result.stats, "pageviews")).to eq(4)
    expect(dash_stat(result.stats, "visitors").comparison_value).to eq(1)
    expect(dash_stat(result.stats, "visitors").change).to eq(200)
  end

  it "answers the four metrics the email prints, in that order" do
    expect(result.stats.map { |stat| stat.metric.key }).to eq(%w[visitors visits pageviews bounce_rate])
  end

  it "ranks the pages by visitors" do
    rows = result.list(:pages).rows

    expect(rows.map(&:label).first).to eq("/going-to-federal-prison")
    expect(rows.first).to have_attributes(visitors: 2, share: 200.0 / 3)
  end

  it "keeps five rows at most" do
    6.times { |n| visitor(10, "extra-#{n}", path: "/page-#{n}") }

    expect(result.list(:pages).rows.size).to eq(5)
  end

  it "reads sources and countries off the visit" do
    expect(result.list(:sources).rows.map(&:label)).to include("Direct / None", "google.com")
    expect(result.list(:countries).rows.map(&:label)).to include("US")
  end

  # The email has no query string behind it, so there is nowhere for a default
  # segment or a remembered filter to come from. It is the whole site or it is
  # a number nobody asked for.
  it "leaves crawlers out" do
    crawler_visit = dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "bot")
    create(:page_view_event, :crawler, visit: crawler_visit, time: dash_time(2026, 8, 10, 10))

    expect(dash_value(result.stats, "visitors")).to eq(3)
  end

  it "says nothing happened rather than dividing by it" do
    empty = described_class.call(
      window: AhoyDashboard::Reports::Digests::Window.new(period: :daily, starts_on: Date.new(2026, 7, 1),
                                                          ends_on: Date.new(2026, 7, 1))
    )

    expect(empty).to be_empty
    expect(empty.lists.map(&:rows)).to all(be_empty)
  end
end
