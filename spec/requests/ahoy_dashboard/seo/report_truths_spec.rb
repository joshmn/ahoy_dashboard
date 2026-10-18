require "rails_helper"

RSpec.describe "Dashboard seo report truths", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }
  before { sign_in create(:user, :admin) }

  it "says no results page was saved on SERP features instead of calling the page plain" do
    keyword = create(:dash_serp_keyword, query: "fci thomson visiting")
    create(:dash_serp_keyword_target, keyword: keyword, site: site)
    run = create(:dash_serp_run, keyword: keyword, checked_at: now - 1.day)
    create(:dash_serp_run_page, run: run, response: nil)

    get "/telemetry/seo/serp_feature", params: { site: site.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No results pages saved in this range", "none of them saved the results page")
    expect(response.body).not_to include("Plain results only")
  end

  it "keeps the note under striking distance honest about the estimated upside" do
    on = now.to_date - 2
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: on, query: "halfway house rules", clicks: 2, impressions: 400, ctr: 0.005, position: 14.0 }
    ])

    get "/telemetry/seo/opportunity"

    expect(response.body).to include("Positions 11 to 20", "Upside is an estimate from typical click rates.")
    expect(response.body).not_to include("Nothing here is estimated")
  end
end
