require "rails_helper"

RSpec.describe AhoyDashboard::Seo::KeywordIdeasQuery do
  let(:site) { create(:dash_serp_site, domain: AhoyDashboard::Serp.own_domain) }

  before do
    create(:dash_keyword_idea, seed: "visiting", query: "visiting hours", location: "us", language: "en",
           volume: 1200, difficulty: 20, provider: "fake", fetched_at: 1.day.ago)
  end

  def reading(keyword, position:, at:, status: :success, site: self.site)
    run = create(:dash_serp_run, keyword: keyword, checked_at: at)
    create(:dash_serp_check, run: run, site: site, position: position, status: status)
  end

  def position
    sole_item(described_class.call(seed: "visiting", location: "us", language: "en").rows).position
  end

  it "joins our latest successful position for the idea" do
    keyword = create(:dash_serp_keyword, query: "visiting hours")
    reading(keyword, position: 9, at: 3.days.ago)
    reading(keyword, position: 4, at: 1.day.ago)
    reading(keyword, position: 1, at: 1.hour.ago, status: :failed)
    reading(keyword, position: 2, at: 1.hour.ago, site: create(:dash_serp_site))

    expect(position).to eq(4)
  end

  it "breaks a tie between two keywords read at the same moment by the later reading" do
    at = 1.day.ago
    reading(create(:dash_serp_keyword, query: "visiting hours", device: "desktop"), position: 7, at: at)
    reading(create(:dash_serp_keyword, query: "visiting hours", device: "mobile"), position: 3, at: at)

    expect(position).to eq(3)
  end

  it "leaves the position empty for an idea nobody tracks" do
    expect(position).to be_nil
  end
end
