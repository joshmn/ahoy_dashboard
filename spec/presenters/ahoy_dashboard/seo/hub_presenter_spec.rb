# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Seo::HubPresenter do
  it "formats the prepared panels and setup steps without SQL" do
    query = AhoyDashboard::QueryForm.from_params({ period: "7d" })
    create(:dash_search_console_total)
    create(:dash_search_console_keyword, impressions: 1000, clicks: 1, position: 12)
    check = create(:dash_serp_check)
    reading = AhoyDashboard::Seo::HubQuery.call(range: query.range, site: check.site)
    context = AhoyDashboard::SearchConsole::PageContextQuery.call(range: query.range)
    shown = described_class.new(query: query, surface: nil, site: check.site, sites: [check.site], reading: reading,
                                search_console_context: context)
    statements = captured_sql(/\ASELECT/, cached: true) do
      shown.top_queries
      shown.opportunities
      shown.rank_tiles
      shown.sample_rankings?
      shown.steps
      shown.steps_done
    end

    expect(statements).to be_empty
  end
end
