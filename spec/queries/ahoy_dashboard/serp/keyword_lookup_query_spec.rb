require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::KeywordLookupQuery do
  it "finds a keyword by its id" do
    keyword = create(:dash_serp_keyword)

    expect(described_class.call(id: keyword.id.to_s)).to eq(keyword)
  end

  it "finds a keyword by its text whatever the case and spacing" do
    keyword = create(:dash_serp_keyword, query: "Visiting Hours")

    expect(described_class.call(text: "  visiting   hours ")).to eq(keyword)
  end

  it "prefers the exact spelling, then the place asked for, then desktop" do
    desktop = create(:dash_serp_keyword, query: "visiting hours", device: "desktop")
    mobile = create(:dash_serp_keyword, query: "visiting hours", device: "mobile", locations: %w[gb])
    shouted = create(:dash_serp_keyword, query: "VISITING HOURS", device: "tablet")

    expect(described_class.call(text: "visiting hours")).to eq(desktop)
    expect(described_class.call(text: "Visiting hours", location: "gb")).to eq(mobile)
    expect(described_class.call(text: "VISITING HOURS")).to eq(shouted)
  end

  it "finds nothing for text nobody tracks, or for nothing at all" do
    expect(described_class.call(text: "not tracked")).to be_nil
    expect(described_class.call).to be_nil
  end
end
