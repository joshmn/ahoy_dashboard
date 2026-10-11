require "rails_helper"
require "support/ahoy_dashboard/installation"

RSpec.describe AhoyDashboard::Serp::ImportCandidatesQuery do
  it "returns candidates when no keywords are tracked" do
    create(:dash_search_console_keyword, query: "first", impressions: 30, clicks: 4, position: 3.2)

    expect(described_class.call).to eq([
      described_class::Candidate.new(query: "first", impressions: 30, clicks: 4, position: 3.2)
    ])
  end

  it "excludes tracked queries before ranking and limiting the remaining aggregates" do
    create(:dash_serp_keyword, query: "tracked", enabled: false)
    create(:dash_search_console_keyword, query: "tracked", impressions: 1000)
    create(:dash_search_console_keyword, query: "first", impressions: 30, clicks: 4, position: 2)
    create(:dash_search_console_keyword, query: "first", date: Date.current - 1, impressions: 10, clicks: 2, position: 8)
    create(:dash_search_console_keyword, query: "second", impressions: 39)
    create(:dash_search_console_keyword, query: "old", date: Date.current - 91, impressions: 2000)

    expect(described_class.call(limit: 1)).to eq([
      described_class::Candidate.new(query: "first", impressions: 40, clicks: 6, position: 3.5)
    ])
  end

  it "offers nothing when Search Console is not installed" do
    uninstall_ahoy_dashboard(:search_console)

    expect(described_class.call).to eq([])
  end
end
