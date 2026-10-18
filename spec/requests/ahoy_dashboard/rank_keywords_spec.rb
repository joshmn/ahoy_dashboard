require "rails_helper"

RSpec.describe "Dashboard rank keyword", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

  around { |example| travel_to(now) { example.run } }

  def reading(position:, at: nil, location: "us", overview: nil, cited: nil, domains: [])
    at ||= now - 1.day
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target,
           location: location, checked_at: at, position: position, url: "https://example.com/page",
           ai_overview_present: overview, ai_overview_cited: cited)
    domains.each_with_index do |domain, index|
      create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x",
             domain: domain, checked_at: at)
    end
    run
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "is a 404 for a keyword nobody tracks" do
      get "/telemetry/rank_keyword", params: { q: "not tracked" }

      expect(response).to have_http_status(:not_found)
    end

    it "sends somebody with no keyword to look up back to the rankings" do
      get "/telemetry/rank_keyword", params: { period: "7d" }

      expect(response).to redirect_to(%r{/telemetry/rankings\?.*period=7d})
    end

    it "treats a blank keyword as no keyword" do
      get "/telemetry/rank_keyword", params: { q: "  " }

      expect(response).to redirect_to(%r{/telemetry/rankings})
    end

    it "says nothing was recorded when the range holds no readings" do
      site
      keyword

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing recorded in this range")
    end

    it "draws the series with the axis the other way round" do
      reading(at: now - 3.days, position: 8)
      reading(at: now - 2.days, position: 6)
      reading(at: now - 1.day, position: 4)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to include("&quot;reverse&quot;:true")
      expect(response.body).to include("up 2 on the reading before")
    end

    it "prints the readings instead of a chart while there are fewer than three" do
      reading(at: now - 3.days, position: 8)
      reading(at: now - 1.day, position: 4)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).not_to include("&quot;reverse&quot;:true")
      expect(response.body).to include("Two readings so far", "The chart starts at the third.")
    end

    it "keeps a reading where the site was nowhere out of the line without losing the row" do
      reading(at: now - 2.days, position: 6)
      reading(at: now - 1.day, position: nil)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to include("Every reading")
      expect(response.body).to include("leaves a hole in the line")
    end

    it "lists who else ranked on the last reading" do
      reading(position: 2, domains: %w[bop.gov example.com justice.gov])

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to include("Who else ranked", "bop.gov", "justice.gov")
    end

    it "marks a subdomain of a site that matches subdomains as yours" do
      site.update!(match_subdomains: true)
      reading(position: 2, domains: %w[bop.gov blog.example.com])

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }
      rivals = document.at_css("[aria-label='Who else ranked']")
      yours = rivals.css("tbody tr").select { |row| row.at_css(".badge")&.text == "You" }

      expect(yours.map { |row| row.at_css(".t-main .seo-label").text.squish }).to eq([ "blog.example.com" ])
    end

    it "does not mark a subdomain as yours when the site matches its own domain only" do
      reading(position: 2, domains: %w[blog.example.com example.com])

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }
      rivals = document.at_css("[aria-label='Who else ranked']")
      yours = rivals.css("tbody tr").select { |row| row.at_css(".badge")&.text == "You" }

      expect(yours.map { |row| row.at_css(".t-main .seo-label").text.squish }).to eq([ "example.com" ])
    end

    it "lists who the overview quoted" do
      run = reading(position: 2, overview: true, cited: true)
      create(:dash_serp_ai_citation, run: run, slot: 1, domain: "bop.gov",
             link: "https://bop.gov/a", checked_at: run.checked_at)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to include("The AI overview", "bop.gov")
    end

    it "reads the place that was asked for" do
      keyword.update!(locations: %w[us gb])
      reading(position: 3, location: "us")
      reading(position: 30, location: "gb")

      get "/telemetry/rank_keyword", params: { keyword: keyword.id, at: "gb" }

      expect(response.body).to include("Searched from")
    end

    it "links each place in the place menu to that place" do
      keyword.update!(locations: %w[us gb])
      reading(position: 3, location: "us")
      reading(position: 30, location: "gb")

      get "/telemetry/rank_keyword", params: { keyword: keyword.id, at: "us" }

      expect(response.body).to include("at=gb")
    end

    it "sends an old link by text to the keyword's own page, whatever the case" do
      keyword

      get "/telemetry/rank_keyword", params: { q: "VISITING Hours", period: "7d" }

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to include("keyword=#{keyword.id}", "period=7d")
      expect(response.location).not_to include("q=")
    end

    it "opens the same phrase tracked on desktop and on mobile as two pages" do
      mobile = create(:dash_serp_keyword, query: keyword.query, device: "mobile")

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }
      expect(response.body).to include("Desktop, en", "keyword=#{mobile.id}")

      get "/telemetry/rank_keyword", params: { keyword: mobile.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mobile, en", "keyword=#{keyword.id}")
    end

    it "sends a text link to the desktop search when the phrase is tracked on both" do
      mobile = create(:dash_serp_keyword, query: keyword.query, device: "mobile")

      get "/telemetry/rank_keyword", params: { q: keyword.query }

      expect(response.location).to include("keyword=#{keyword.id}")
      expect(response.location).not_to include("keyword=#{mobile.id}")
    end

    it "is a 404 for a keyword id nobody tracks" do
      get "/telemetry/rank_keyword", params: { keyword: 0 }

      expect(response).to have_http_status(:not_found)
    end

    it "keeps reading the site it was opened for" do
      rival = create(:dash_serp_site, name: "Rival", domain: "rival.com")
      reading(position: 4)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id, site: rival.id }

      expect(response.body).to include("for Rival, not your site")
    end

    it "names the cadence the way the form does" do
      keyword.update!(frequency: :biweekly)
      reading(position: 4)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to include("Checked every 2 weeks")
    end

    it "offers no date range too short to hold a check" do
      reading(position: 4)

      get "/telemetry/rank_keyword", params: { keyword: keyword.id }

      expect(response.body).to match(%r{/telemetry/rank_keyword\?[^"]*period=7d})
      expect(response.body).not_to match(%r{/telemetry/rank_keyword\?[^"]*period=(realtime|yesterday)})
    end
  end
end
