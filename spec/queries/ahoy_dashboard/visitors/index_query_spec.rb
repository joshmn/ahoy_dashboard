require "rails_helper"

RSpec.describe AhoyDashboard::Visitors::IndexQuery do
  let(:range) { dash_day_range(2026, 8, 10) }

  def clock(hour, minute = 0)
    dash_time(2026, 8, 10, hour, minute)
  end

  def listed(**options)
    described_class.call(scope: dash_scope(range: range, **options.slice(:filters, :include_internal)),
                         **options.except(:filters, :include_internal))
  end

  before do
    dash_landing("/pricing", at: clock(9), visitor: "a", referring_domain: "google.com", referrer: "https://google.com/",
                             landing_page: "https://example.com/pricing?ref=x")
    dash_landing("/", at: clock(15), visitor: "a", user_id: 5, country: "CA")
    dash_landing("/", at: clock(11), visitor: "b")
    dash_landing("/", at: dash_time(2026, 8, 1, 9), visitor: "old")
  end

  it "lists visitors in the range, most recent visit first" do
    page = listed

    expect(page.rows.map(&:visitor_token)).to eq(%w[a b])
    expect(page.total).to eq(2)
  end

  it "sums each visitor's visits and keeps their first source and entry page" do
    row = listed.rows.first

    expect(row.visits).to eq(2)
    expect(row.source).to eq("google.com")
    expect(row.entry).to eq("/pricing")
    expect(row.country).to eq("CA")
    expect(row.user_id).to eq("5")
    expect(row.last_at).to eq(clock(15))
  end

  it "narrows to visitors who signed in" do
    expect(listed(identified: true).rows.map(&:visitor_token)).to eq(%w[a])
  end

  it "follows the dashboard filters" do
    page = listed(filters: dash_filters([ "country", "is", "CA" ]))

    expect(page.rows.map(&:visitor_token)).to eq(%w[a])
  end

  it "leaves out excluded traffic unless it's asked for" do
    dash_exclusion("Canada", [ "country", "is", "CA" ])

    expect(listed.rows.find { |row| row.visitor_token == "a" }.visits).to eq(1)
    expect(listed(include_internal: true).rows.find { |row| row.visitor_token == "a" }.visits).to eq(2)
  end

  it "pages" do
    first = listed(per_page: 1)
    second = listed(per_page: 1, page: 2)

    expect(first.rows.map(&:visitor_token)).to eq(%w[a])
    expect(first.pages).to eq(2)
    expect(second.rows.map(&:visitor_token)).to eq(%w[b])
  end
end
