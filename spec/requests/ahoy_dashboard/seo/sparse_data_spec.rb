require "rails_helper"

RSpec.describe "Dashboard seo sparse data", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }
  before { sign_in create(:user, :admin) }

  def reading(keyword:, position:, at:, domains: [], overview: nil, cited: nil)
    run = create(:dash_serp_run, keyword: keyword, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target, checked_at: at,
           position: position, ai_overview_present: overview, ai_overview_cited: cited)
    domains.each_with_index do |domain, index|
      create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x", domain: domain, checked_at: at)
    end
    run
  end

  def headers(label)
    document.at_css("[role=group][aria-label='#{label}'] table thead").css("th").map { |th| th.text.strip }
  end

  describe "under three points" do
    let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

    it "prints the readings on Visibility instead of drawing a chart" do
      reading(keyword: keyword, position: 3, at: now - 2.days)
      reading(keyword: keyword, position: 2, at: now - 1.day)

      get "/telemetry/seo/visibility", params: { site: site.id }

      expect(response.body).to include("Two readings so far", "The chart starts at the third.")
      expect(document.at_css("svg|svg[role=img]", "svg" => "http://www.w3.org/2000/svg")).to be_nil
    end

    it "draws the chart from the third reading" do
      reading(keyword: keyword, position: 3, at: now - 3.days)
      reading(keyword: keyword, position: 2, at: now - 2.days)
      reading(keyword: keyword, position: 2, at: now - 1.day)

      get "/telemetry/seo/visibility", params: { site: site.id }

      expect(response.body).not_to include("readings so far")
      expect(document.at_css("svg|svg[role=img]", "svg" => "http://www.w3.org/2000/svg")).to be_present
    end

    it "prints the readings on Backlinks after two syncs" do
      allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
      create(:dash_backlink_sample, on: now.to_date - 2, domains: 12, links: 40, provider: "fake")
      create(:dash_backlink_sample, on: now.to_date - 1, domains: 14, links: 44, provider: "fake")

      get "/telemetry/seo/backlink"

      expect(response.body).to include("Two readings so far", "Aug 18", "Aug 19")
      expect(document.at_css("svg|svg[role=img]", "svg" => "http://www.w3.org/2000/svg")).to be_nil
    end

    it "gives Top contributors an empty state rather than a bare table" do
      reading(keyword: keyword, position: nil, at: now - 1.day)

      get "/telemetry/seo/visibility", params: { site: site.id }

      expect(response.body).to include("Nothing is earning clicks yet")
    end
  end

  describe "shares" do
    it "hides Share on Who else is on page one until three searches are behind it" do
      reading(keyword: create(:dash_serp_keyword, query: "one"), position: 2, at: now - 1.day, domains: %w[bop.gov example.com])

      get "/telemetry/rankings", params: { site: site.id }

      expect(headers("Who else is on page one")).to eq([ "Domain", "Searches", "Best" ])
      expect(response.body).to include("Share shows once 3 searches are behind it")
    end

    it "shows Share once three searches are behind it" do
      %w[one two three].each do |query|
        reading(keyword: create(:dash_serp_keyword, query: query), position: 2, at: now - 1.day, domains: %w[bop.gov example.com])
      end

      get "/telemetry/rankings", params: { site: site.id }

      expect(headers("Who else is on page one")).to eq([ "Domain", "Searches", "Share", "Best" ])
      expect(response.body).not_to include("Share shows once")
    end

    it "hides Share on AI overviews until three overviews have been seen" do
      run = reading(keyword: create(:dash_serp_keyword, query: "one"), position: 2, at: now - 1.day, overview: true, cited: true)
      create(:dash_serp_ai_citation, run: run, link: "https://example.com/b")

      get "/telemetry/rankings", params: { site: site.id }

      expect(headers("AI overviews")).to eq([ "Cited domain", "Citations" ])
    end
  end

  describe "Volatility" do
    let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

    def results(at, *domains)
      run = create(:dash_serp_run, keyword: keyword, checked_at: at)
      domains.each_with_index do |domain, index|
        create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x", domain: domain, checked_at: at)
      end
      run
    end

    before do
      site
      results(now - 4.days, "bop.gov", "example.com", "justice.gov")
      results(now - 3.days, "bop.gov", "quora.com", "marshallproject.org")
      results(now - 2.days, "quora.com", "sentencing.us", "justice.gov")
      results(now - 1.day, "reddit.com", "prisonprofessors.com", "findlaw.com")
    end

    it "labels each new domain on its own instead of one comma joined path" do
      get "/telemetry/seo/volatility"
      row = document.css("[role=group][aria-label='Most changed searches'] tbody tr").first

      expect(row.css("td").last.css("span").map { |badge| badge.text.strip }).to eq(%w[reddit.com prisonprofessors.com findlaw.com])
      expect(row.css("td").last.css("[title]").map { |badge| badge["title"] }).to eq(%w[reddit.com prisonprofessors.com findlaw.com])
    end

    it "draws the score bands on the chart with their names down the side" do
      get "/telemetry/seo/volatility"
      svg = document.at_css("svg|svg[role=img]", "svg" => "http://www.w3.org/2000/svg")

      expect(svg.css("svg|line", "svg" => "http://www.w3.org/2000/svg").size).to eq(5)
      expect(svg.parent.text.squish.split(" ")).to eq(%w[Still Normal Choppy Rough Storm])
    end
  end

  describe "SERP features" do
    def page(keyword, items, at: now - 1.day)
      run = create(:dash_serp_run, keyword: keyword, checked_at: at)
      create(:dash_serp_run_page, run: run, response: { "tasks" => [ { "result" => [ { "items" => items } ] } ] })
      run
    end

    it "hides Share of searches until three searches have been read" do
      page(create(:dash_serp_keyword, query: "one"), [ { "type" => "featured_snippet", "domain" => "bop.gov" } ])

      get "/telemetry/seo/serp_feature"

      expect(headers("Features on your results pages")).to eq([ "Feature", "Searches", "Yours", "Held most by" ])
      expect(response.body).to include("Share of searches shows once 3 searches have been read")
    end

    it "shows Share of searches from the third search" do
      %w[one two three].each do |query|
        page(create(:dash_serp_keyword, query: query), [ { "type" => "featured_snippet", "domain" => "bop.gov" } ])
      end

      get "/telemetry/seo/serp_feature"

      expect(headers("Features on your results pages")).to eq([ "Feature", "Share of searches", "Searches", "Yours", "Held most by" ])
    end

    it "leaves Answered by out of People also ask when no check saved who answered" do
      page(create(:dash_serp_keyword, query: "one"), [ { "type" => "people_also_ask", "items" => [ { "title" => "Who qualifies?" } ] } ])

      get "/telemetry/seo/serp_feature"

      expect(headers("People also ask")).to eq([ "Question", "Track" ])
      expect(response.body).to include("that column is left out")
    end

    it "keeps Answered by once a check names a site" do
      page(create(:dash_serp_keyword, query: "one"),
           [ { "type" => "people_also_ask",
               "items" => [ { "title" => "Who qualifies?", "expanded_element" => [ { "url" => "https://bop.gov/faq", "description" => "Anyone." } ] } ] } ])

      get "/telemetry/seo/serp_feature"

      expect(headers("People also ask")).to eq([ "Question", "Answered by", "Track" ])
    end
  end
end
