require "rails_helper"

RSpec.describe AhoyDashboard::TrackedKeywordsQuery do
  it "returns only keywords represented by the visible phrases" do
    wanted = create(:dash_serp_keyword, query: "visiting hours")
    create(:dash_serp_keyword, query: "another search")

    expect(described_class.call(phrases: ["visiting hours"]).map(&:id)).to eq([wanted.id])
  end

  it "normalizes repeated spaces and letter case in visible phrases" do
    wanted = create(:dash_serp_keyword, query: "Visiting Hours")

    expect(described_class.call(phrases: [" visiting  HOURS "]).map(&:id)).to eq([wanted.id])
  end

  it "prefers the default device when the search has several configurations" do
    create(:dash_serp_keyword, query: "visiting hours", device: "mobile")
    wanted = create(:dash_serp_keyword, query: "visiting hours", device: "desktop")

    expect(described_class.call(phrases: ["visiting hours"]).map(&:id)).to eq([wanted.id])
  end

  it "prefers the default language on the preferred device" do
    create(:dash_serp_keyword, query: "visiting hours", language: "es")
    wanted = create(:dash_serp_keyword, query: "visiting hours", language: "en")

    expect(described_class.call(phrases: ["visiting hours"]).map(&:id)).to eq([wanted.id])
  end

  it "does not look up keywords when the displayed list is empty" do
    create(:dash_serp_keyword, query: "visiting hours")

    expect(described_class.call(phrases: [])).to be_empty
  end
end
