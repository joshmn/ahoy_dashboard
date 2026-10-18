require "rails_helper"

RSpec.describe AhoyDashboard::Seo::BacklinksQuery do
  let(:day) { Date.new(2026, 8, 10) }
  let(:range) { Time.utc(2026, 8, 10)..Time.utc(2026, 8, 20) }

  def domain(name, **attributes)
    create(:dash_backlink_domain, domain: "#{name}.example", first_seen_on: day - 1,
           last_seen_on: day, provider: "dataforseo", links: 2,
           **attributes)
  end

  it "counts all live, gained and lost domains in one aggregate with the original date boundaries" do
    domain("older", links: 3)
    domain("boundary", first_seen_on: day, follow: false, links: 4)
    domain("future", first_seen_on: day + 30, links: 5)
    domain("lost-now", lost_on: day, links: 100)
    domain("lost-before", lost_on: day - 1, links: 100)
    domain("lost-future", lost_on: day + 30, links: 100)
    result = nil
    sql = captured_sql(/\ASELECT/, cached: true) { result = described_class.call(range: range) }

    expect(result.totals).to have_attributes(domains: 3, links: 12, followed: 2, gained: 2, lost: 2, nofollow: 1)
    expect(result).not_to be_sample
    expect(sql.count { |statement| statement.include?("count(*)") && statement.include?("backlink_domains") }).to eq(1)
  end

  it "includes old lost sample domains when deciding whether the data contains samples" do
    domain("sample", lost_on: day - 30, provider: "fake")

    result = described_class.call(range: range)

    expect(result).to be_sample
    expect(result.totals).to have_attributes(domains: 0, links: 0, gained: 0, lost: 0, followed: 0, nofollow: 0)
  end

  it "also detects sample snapshots only inside the requested range" do
    create(:dash_backlink_sample, on: day - 1, provider: "fake", domains: 1, links: 1)
    expect(described_class.call(range: range)).not_to be_sample

    create(:dash_backlink_sample, on: day, provider: "fake", domains: 1, links: 1)
    expect(described_class.call(range: range)).to be_sample
  end
end
