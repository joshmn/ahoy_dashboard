require "rails_helper"

RSpec.describe "Dashboard rankings", type: :request do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def reading(keyword:, position:, at: nil, location: "us", overview: nil, cited: nil, domains: [])
    at ||= now - 1.day
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    target = AhoyDashboard::SerpKeywordTarget.find_or_create_by!(keyword: keyword, site: site)
    create(:dash_serp_check, run: run, keyword: keyword, site: site, target: target,
           location: location, checked_at: at, position: position,
           ai_overview_present: overview, ai_overview_cited: cited)
    domains.each_with_index do |domain, index|
      create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x",
             domain: domain, checked_at: at)
    end
    run
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "asks for a site first when nothing is set up" do
      get "/telemetry/rankings"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add your site to get started", "/telemetry/settings/serp_sites/new")
    end

    it "asks for a site when keywords exist without one" do
      create(:dash_serp_keyword)

      get "/telemetry/rankings"

      expect(response.body).to include("Add your site to get started")
    end

    it "asks for keywords once a site exists" do
      create(:dash_serp_site)

      get "/telemetry/rankings"

      expect(response.body).to include("Add your keywords to get started", "/telemetry/settings/serp_keywords/new")
    end

    describe "Check now" do
      def unavailable
        document = Nokogiri::HTML5(response.body)
        button = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == "Check now" }

        [ button, button && document.at_css("##{button['aria-describedby']}") ]
      end

      it "stays on the page and says rank tracking is off" do
        get "/telemetry/rankings"
        button, reason = unavailable

        expect(button).to be_present
        expect(reason.text).to include("Rank tracking is off")
      end

      it "says a keyword has to be tracked first and points at the first step" do
        allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)

        get "/telemetry/rankings"
        button, reason = unavailable

        expect(button).to be_present
        expect(reason.text).to include("Track a keyword first.")
        expect(response.body).to include("/telemetry/settings/serp_sites/new")
      end

      it "explains a blocked check in a notice once the page is set up" do
        allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
        create(:dash_serp_keyword_target, site: site)
        create(:dash_serp_provider, :active, :spent)

        get "/telemetry/rankings"
        notice = document.css("[role=status]").find { |node| node.text.include?("Check now is off.") }

        expect(notice.text).to include("This month's search limit is used up.")
        expect(notice.at_css("a")["href"]).to eq("/telemetry/settings/serp_providers")
      end

      it "is a real button once something can be checked" do
        allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
        create(:dash_serp_keyword_target, site: site)

        get "/telemetry/rankings"
        button, = unavailable
        form = document.at_css("form[action='/telemetry/rank_check']")

        expect(button).to be_nil
        expect(form.at_css("button")["disabled"]).to be_nil
      end
    end

    it "lists where the site comes, best first" do
      good = create(:dash_serp_keyword, query: "visiting hours")
      poor = create(:dash_serp_keyword, query: "commissary list")
      reading(keyword: good, position: 2)
      reading(keyword: poor, position: 18)

      get "/telemetry/rankings"

      expect(response).to have_http_status(:ok)
      expect(response.body.index("visiting hours")).to be < response.body.index("commissary list")
    end

    it "reads a fall in the number as up, because position runs backwards" do
      keyword = create(:dash_serp_keyword)
      reading(keyword: keyword, at: now - 2.days, position: 9)
      reading(keyword: keyword, at: now - 1.day, position: 4)

      get "/telemetry/rankings"

      badge = document.at_css(".seo-delta")

      expect(badge.text.squish).to eq("up 5")
    end

    it "shows who else is on page one" do
      keyword = create(:dash_serp_keyword)
      reading(keyword: keyword, position: 2, domains: %w[bop.gov example.com])

      get "/telemetry/rankings"

      expect(response.body).to include("Who else is on page one", "bop.gov")
    end

    it "marks a subdomain of a site that matches subdomains as yours on page one" do
      site.update!(match_subdomains: true)
      keyword = create(:dash_serp_keyword)
      reading(keyword: keyword, position: 2, domains: %w[bop.gov blog.example.com])

      get "/telemetry/rankings"
      share = document.at_css("[aria-label='Who else is on page one']")
      yours = share.css("tbody tr").select { |row| row.at_css(".badge")&.text == "You" }

      expect(yours.map { |row| row.at_css(".seo-label").text.squish }).to eq([ "blog.example.com" ])
    end

    it "says whether an overview showed and whether it quoted us" do
      keyword = create(:dash_serp_keyword)
      run = reading(keyword: keyword, position: 2, overview: true, cited: true)
      create(:dash_serp_ai_citation, run: run, domain: "example.com",
             link: "https://example.com/a", checked_at: run.checked_at)

      get "/telemetry/rankings"

      expect(response.body).to include("AI overviews", "Cited")
    end

    it "reads another site when one is asked for" do
      rival = create(:dash_serp_site, name: "Them", domain: "rival.com")
      keyword = create(:dash_serp_keyword)
      reading(keyword: keyword, position: 2)

      get "/telemetry/rankings", params: { site: rival.id }

      expect(response.body).to include("Nothing recorded in this range")
    end

    it "links a row through to the keyword" do
      keyword = create(:dash_serp_keyword, query: "visiting hours")
      reading(keyword: keyword, position: 2)

      get "/telemetry/rankings"

      expect(response.body).to include("/telemetry/rank_keyword?")
    end

    describe "the rankings distribution" do
      def legend
        document.at_css("[aria-label='Filter tracked searches by band']")
      end

      def band(label)
        legend.css("li > *").find { |node| node.text.squish.start_with?("#{label} ") }
      end

      def listed
        document.css("##{AhoyDashboard::Serp::RankingsPresenter::TABLE_ANCHOR} tbody tr a[href*='/rank_keyword']").map { |node| node.text.strip }
      end

      before do
        { "visiting hours" => 2, "commissary list" => 7, "mail rules" => 15, "halfway house" => nil }.each do |query, position|
          reading(keyword: create(:dash_serp_keyword, query: query), position: position)
        end
      end

      it "counts each band off the latest readings" do
        get "/telemetry/rankings"

        expect(legend.css("li").map { |item| item.text.squish })
          .to eq([ "Top 3 1", "4 to 10 1", "11 to 20 1", "Past 20 0", "Not found 1" ])
      end

      it "draws one bar per day with a description of the latest one" do
        get "/telemetry/rankings", params: { period: "7d" }

        plot = document.at_css("svg|svg[role='img'][aria-label^='Tracked searches by position band']", "svg" => "http://www.w3.org/2000/svg")

        expect(plot.css("svg|g", "svg" => "http://www.w3.org/2000/svg").size).to eq(7)
        expect(plot["aria-label"]).to include("Top 3: 1", "Not found: 1")
      end

      it "links a band with searches in it to the list filtered to that band, and an empty band to nothing" do
        get "/telemetry/rankings"

        expect(band("4 to 10").name).to eq("a")
        expect(band("4 to 10")["href"]).to include("band=4-10").and(end_with("#tracked-searches"))
        expect(band("Past 20").name).to eq("div")
      end

      it "filters the tracked searches to the band asked for" do
        get "/telemetry/rankings", params: { band: "11-20" }

        expect(listed).to eq([ "mail rules" ])
        expect(band("11 to 20")["aria-current"]).to eq("true")
        expect(band("11 to 20")["href"]).not_to include("band=")
        expect(document.css("a").map { |link| link.text.strip }).to include("Show all")
      end

      it "keeps the tiles counting every search while a band is picked" do
        get "/telemetry/rankings", params: { band: "top-3" }

        expect(listed).to eq([ "visiting hours" ])
        expect(document.at_css("[aria-label='Summary figures']").text.squish).to include("Searches 4")
      end

      it "carries the band through the date and site menus" do
        get "/telemetry/rankings", params: { band: "not-found" }

        expect(document.css("#tm-rankings-period a").map { |link| link["href"] }).to all(include("band=not-found"))
      end

      it "shows everything for a band it does not know" do
        get "/telemetry/rankings", params: { band: "page-nine" }

        expect(listed.size).to eq(4)
      end

      it "says so when the band asked for is empty" do
        get "/telemetry/rankings", params: { band: "past-20" }

        expect(response.body).to include("Nothing in Past 20 on the latest reading")
        expect(listed).to be_empty
      end
    end

    describe "the tracked searches" do
      def table
        document.at_css("##{AhoyDashboard::Serp::RankingsPresenter::TABLE_ANCHOR} table")
      end

      def row_for(query)
        table.css("tbody tr").find { |row| row.text.include?(query) }
      end

      it "opens a keyword on the site that was picked" do
        rival = create(:dash_serp_site, name: "Rival", domain: "rival.com")
        keyword = create(:dash_serp_keyword, query: "visiting hours")
        reading(keyword: keyword, position: 3)
        target = AhoyDashboard::SerpKeywordTarget.create!(keyword: keyword, site: rival)
        create(:dash_serp_check, run: keyword.runs.first, keyword: keyword, site: rival, target: target, position: 5)

        get "/telemetry/rankings", params: { site: rival.id }

        href = row_for("visiting hours").at_css("a[href*='/rank_keyword']")["href"]
        expect(href).to include("keyword=#{keyword.id}", "site=#{rival.id}")
      end

      it "marks a search the site came into as new and one it dropped out of as gone" do
        came = create(:dash_serp_keyword, query: "came in")
        left = create(:dash_serp_keyword, query: "dropped out")
        reading(keyword: came, position: nil, at: now - 2.days)
        reading(keyword: came, position: 6)
        reading(keyword: left, position: 4, at: now - 2.days)
        reading(keyword: left, position: nil)

        get "/telemetry/rankings"

        expect(row_for("came in").text).to include("New")
        expect(row_for("dropped out").text).to include("Gone")
      end

      it "leaves out a place the keyword no longer searches from" do
        keyword = create(:dash_serp_keyword, query: "visiting hours", locations: %w[us gb])
        reading(keyword: keyword, position: 3, location: "us")
        reading(keyword: keyword, position: 9, location: "gb")
        keyword.update!(locations: %w[us])

        get "/telemetry/rankings"

        expect(table.css("tbody tr").size).to eq(1)
        expect(table.css("a[href*='/rank_keyword']").map { |link| link["href"] }).to all(include("at=us"))
      end

      it "counts who else is on page one only from the picked site's searches" do
        rival = create(:dash_serp_site, name: "Rival", domain: "rival.com")
        ours = create(:dash_serp_keyword, query: "ours")
        theirs = create(:dash_serp_keyword, query: "theirs")
        reading(keyword: ours, position: 1, domains: %w[example.com bop.gov])
        run = create(:dash_serp_run, keyword: theirs, checked_at: now - 1.day)
        create(:dash_serp_result, run: run, position: 1, link: "https://justice.gov/x", domain: "justice.gov",
               checked_at: run.checked_at)
        create(:dash_serp_check, run: run, keyword: theirs, site: rival, position: nil)

        get "/telemetry/rankings"

        share = document.at_css("table[aria-label='Who else is on page one']") ||
                document.css("table").find { |node| node.text.include?("Domain") }
        expect(share.text).to include("bop.gov")
        expect(share.text).not_to include("justice.gov")
      end
    end

    it "offers no date range too short to hold a check" do
      get "/telemetry/rankings"

      expect(response.body).not_to match(%r{/telemetry/rankings\?[^"]*period=(realtime|yesterday)})
    end
  end
end
