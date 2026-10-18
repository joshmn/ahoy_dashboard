require "rails_helper"

RSpec.describe "Dashboard seo site switcher", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let!(:rival) { create(:dash_serp_site, name: "Bop", domain: "bop.gov") }
  let!(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

  around { |example| travel_to(now) { example.run } }
  before { sign_in create(:user, :admin) }

  def reading(site:, position:)
    run = create(:dash_serp_run, keyword: keyword, checked_at: now - 1.day)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target, checked_at: now - 1.day, position: position)
  end

  it "lists your own site first and says the button is a site" do
    reading(site: site, position: 2)

    get "/telemetry/rankings"

    expect(document.at_css("#tm-rankings-site-button").text.squish).to eq("Site: Us")
    expect(document.css("#tm-rankings-site a").map { |link| link.text.squish }).to eq([ "Us (example.com)", "Bop (bop.gov)" ])
    expect(document.at_css("title").text).to start_with("Rankings")
    expect(document.at_css("title").text).not_to include("Bop")
  end

  it "names the site in the title and the lede when it is not yours" do
    reading(site: rival, position: 4)

    get "/telemetry/rankings", params: { site: rival.id }

    expect(document.at_css("title").text).to start_with("Rankings: Bop")
    expect(document.at_css("h1").text.squish).to eq("Rankings: Bop")
    expect(response.body).to include("Where Bop shows up for each tracked search.")
    expect(response.body).not_to include("Where your site shows up")
  end

  it "does the same on Visibility" do
    reading(site: rival, position: 4)

    get "/telemetry/seo/visibility", params: { site: rival.id }

    expect(document.at_css("title").text).to start_with("Visibility: Bop")
    expect(response.body).to include("read for Bop")
    expect(document.at_css("#tm-seo-site-button").text.squish).to eq("Site: Bop")
  end
end
