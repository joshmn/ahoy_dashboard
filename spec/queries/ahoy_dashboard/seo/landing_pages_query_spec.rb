require "rails_helper"

RSpec.describe AhoyDashboard::Seo::LandingPagesQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:range) { (now - 7.days)..now }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:visiting) { create(:dash_serp_keyword, query: "visiting hours", tags: [ "guides" ]) }
  let(:mail) { create(:dash_serp_keyword, query: "mail rules", tags: [ "guides" ]) }
  let(:consult) { create(:dash_serp_keyword, query: "prison consultant", tags: [ "Brand" ]) }
  let(:money) { create(:dash_serp_keyword, query: "commissary money") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword, position:, url:, days_ago: 1, location: "us", site: self.site)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: now - days_ago.days)
    create(:dash_serp_check, run: run, site: site, position: position, url: url)
  end

  def call(**options)
    described_class.call(site: site, range: range, **options)
  end

  before do
    reading(visiting, position: 1, url: "https://example.com/visiting")
    reading(mail, position: 5, url: "https://example.com/visiting")
    reading(consult, position: 2, url: "https://example.com/")
    reading(money, position: 3, url: "https://example.com/money", days_ago: 4)
    reading(money, position: nil, url: nil, days_ago: 1)
  end

  it "groups each search's latest reading by the URL ranking for it" do
    pages = call.pages

    expect(pages.map(&:url)).to eq([ "https://example.com/visiting", "https://example.com/" ])
    expect(pages.first.held.map(&:query)).to eq([ "visiting hours", "mail rules" ])
    expect(pages.first.searches).to eq(2)
    expect(pages.first.best).to eq(1)
    expect(pages.first.median).to eq(3.0)
  end

  it "shares visibility out of everything the tracked searches earn, so the shares add to the whole" do
    pages = call.pages
    curve = AhoyDashboard::Seo::CtrCurve
    total = curve.at(1) + curve.at(5) + curve.at(2)

    expect(pages.first.share).to be_within(0.0001).of((curve.at(1) + curve.at(5)) / total)
    expect(pages.sum(&:share)).to be_within(0.0001).of(1.0)
  end

  it "keeps a page that lost every search, listing each one as gone and where it is now" do
    lost = call.lost

    expect(lost.map(&:url)).to eq([ "https://example.com/money" ])
    gone = sole_item(lost.first.gone)
    expect([ gone.query, gone.was, gone.ranked_elsewhere? ]).to eq([ "commissary money", 3, false ])
  end

  it "says which page a lost search moved to when another page took it" do
    reading(consult, position: 4, url: "https://example.com/about", days_ago: 5)

    gone = sole_item(call.lost.find { |page| page.url == "https://example.com/about" }.gone)

    expect([ gone.was, gone.now_position, gone.now_url ]).to eq([ 4, 2, "https://example.com/" ])
  end

  it "does not count historical whitespace-only URLs as lost pages" do
    reading(consult, position: 4, url: " \t\n", days_ago: 5)

    expect(call.lost.map(&:url)).to eq([ "https://example.com/money" ])
  end

  it "counts a search in each place separately" do
    reading(visiting, position: 3, url: "https://example.com/visiting", location: "gb")

    page = call.pages.first

    expect(page.held.map(&:location)).to contain_exactly("us", "us", "gb")
  end

  it "reads one tag at a time" do
    result = call(tag: "guides")

    expect(result.pages.map(&:url)).to eq([ "https://example.com/visiting" ])
    expect(sole_item(result.pages).share).to eq(1.0)
    expect(result.lost).to be_empty
  end

  it "reads only the site asked for" do
    rival = create(:dash_serp_site, name: "Them", domain: "rival.com")
    reading(visiting, position: 2, url: "https://rival.com/hours", site: rival)

    expect(described_class.call(site: rival, range: range).pages.map(&:url)).to eq([ "https://rival.com/hours" ])
  end

  it "reads nothing without a site" do
    expect(described_class.call(site: nil, range: range)).not_to be_any
  end
end
