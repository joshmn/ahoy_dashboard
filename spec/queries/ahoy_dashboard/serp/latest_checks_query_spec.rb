require "rails_helper"

RSpec.describe AhoyDashboard::Serp::LatestChecksQuery do
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:rival) { create(:dash_serp_site, name: "Them", domain: "rival.com") }
  let(:keyword) { create(:dash_serp_keyword, locations: %w[us gb]) }

  def reading(position:, at:, location: "us", site: self.site, status: :success)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    create(:dash_serp_check, run: run, site: site, position: position, status: status)
  end

  def call(site: self.site, keyword_ids: [ keyword.id ])
    described_class.call(keyword_ids: keyword_ids, site: site)
  end

  it "keeps the newest successful reading for each place of each keyword" do
    reading(position: 9, at: 3.days.ago)
    newest = reading(position: 4, at: 1.day.ago)
    reading(position: 1, at: 1.hour.ago, status: :failed)
    there = reading(position: 6, at: 2.days.ago, location: "gb")

    expect(call).to eq([ keyword.id, "us" ] => newest, [ keyword.id, "gb" ] => there)
  end

  it "breaks a tie on the reading time by the later id" do
    at = 1.day.ago
    reading(position: 9, at: at)
    later = reading(position: 2, at: at)

    expect(call.fetch([ keyword.id, "us" ])).to eq(later)
  end

  it "reads only the site asked for" do
    reading(position: 9, at: 2.days.ago)
    reading(position: 1, at: 1.day.ago, site: rival)

    expect(call.fetch([ keyword.id, "us" ]).position).to eq(9)
  end

  it "reads nothing without a site rather than borrowing a rival's position" do
    reading(position: 1, at: 1.day.ago, site: rival)

    expect(call(site: nil)).to eq({})
  end

  it "reads nothing for no keywords" do
    reading(position: 1, at: 1.day.ago)

    expect(call(keyword_ids: [])).to eq({})
  end

  it "leaves out a place the keyword no longer searches" do
    keyword.update!(locations: %w[us gb ca])
    reading(position: 3, at: 1.day.ago, location: "ca")
    keyword.update!(locations: %w[us gb])

    expect(call).to eq({})
  end
end
