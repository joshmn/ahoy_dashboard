require "rails_helper"

RSpec.describe AhoyDashboard::Serp::RecentChecksQuery do
  let(:site) { create(:dash_serp_site) }
  let(:keyword) { create(:dash_serp_keyword, locations: %w[us gb]) }

  def reading(position:, at:, location: "us", status: :success)
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    create(:dash_serp_check, run: run, site: site, position: position, status: status)
  end

  def searches
    AhoyDashboard::SerpCheck.where(site_id: site.id).distinct.select(:target_id, :location)
  end

  it "takes the newest successful readings of each search, newest first" do
    reading(position: 9, at: 3.days.ago)
    middle = reading(position: 5, at: 2.days.ago)
    newest = reading(position: 4, at: 1.day.ago)
    reading(position: 1, at: 1.hour.ago, status: :failed)
    there = reading(position: 6, at: 2.days.ago, location: "gb")

    expect(described_class.call(searches: searches, count: 2).to_a).to eq([ there, newest, middle ])
  end

  it "takes one reading by default" do
    reading(position: 9, at: 3.days.ago)
    newest = reading(position: 4, at: 1.day.ago)

    expect(described_class.call(searches: searches).to_a).to eq([ newest ])
  end

  it "reads only what came before a moment when given one" do
    earlier = reading(position: 9, at: 3.days.ago)
    reading(position: 4, at: 1.day.ago)

    expect(described_class.call(searches: searches, before: 2.days.ago).to_a).to eq([ earlier ])
  end

  it "reads nothing for no searches" do
    reading(position: 9, at: 3.days.ago)

    nothing = AhoyDashboard::SerpCheck.where(site_id: create(:dash_serp_site).id).distinct.select(:target_id, :location)

    expect(described_class.call(searches: nothing).to_a).to eq([])
  end
end
