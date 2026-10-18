require "rails_helper"

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

  it "leaves out a query already tracked with different capitals" do
    create(:dash_serp_keyword, query: "Prison Consultant")
    create(:dash_search_console_keyword, query: "prison consultant", impressions: 500)
    create(:dash_search_console_keyword, query: "halfway house", impressions: 20)

    expect(described_class.call.map(&:query)).to eq([ "halfway house" ])
  end

  describe "caching" do
    before { allow(AhoyDashboard).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "answers from the cache until a keyword is tracked" do
      create(:dash_search_console_keyword, query: "first", impressions: 30)
      described_class.call
      create(:dash_search_console_keyword, query: "second", impressions: 900)

      expect(described_class.call.map(&:query)).to eq([ "first" ])

      create(:dash_serp_keyword, query: "First")

      expect(described_class.call.map(&:query)).to eq([ "second" ])
    end

    it "reads again when Search Console lands another day" do
      create(:dash_search_console_keyword, query: "first", impressions: 30)
      described_class.call
      create(:dash_search_console_keyword, query: "second", impressions: 900)
      create(:dash_search_console_day, date: Date.current, scanned_at: Time.current)

      expect(described_class.call.map(&:query)).to eq([ "second", "first" ])
    end

    it "reads again once the stored queries are cleared for another property" do
      create(:dash_search_console_keyword, query: "first", impressions: 30)
      described_class.call
      AhoyDashboard::SearchConsoleKeyword.delete_all

      expect(described_class.call).to eq([])
    end

    it "keeps a short list and a long one apart" do
      create(:dash_search_console_keyword, query: "first", impressions: 30)
      create(:dash_search_console_keyword, query: "second", impressions: 900)

      expect(described_class.call(limit: 1).size).to eq(1)
      expect(described_class.call(limit: 5).size).to eq(2)
    end
  end

  it "offers nothing when Search Console is not installed" do
    uninstall_ahoy_dashboard(:search_console)

    expect(described_class.call).to eq([])
  end
end
