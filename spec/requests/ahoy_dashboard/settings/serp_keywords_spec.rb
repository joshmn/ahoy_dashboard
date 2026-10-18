require "rails_helper"

RSpec.describe "Dashboard serp keyword settings", type: :request do
  describe "as an admin" do
    let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

    before { sign_in create(:user, :admin) }

    it "says nothing is being fetched until a provider is set up" do
      get "/telemetry/settings/serp_keywords"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No search provider yet")
    end

    it "says nothing about sample results when a real provider is saved with its key" do
      create(:dash_serp_provider, :serpapi, :active)

      get "/telemetry/settings/serp_keywords"

      expect(response.body).not_to include("No search provider yet", "sample results")
    end

    it "says the provider has no credentials when the one in use has none" do
      create(:dash_serp_provider, :active, name: "serpapi")

      get "/telemetry/settings/serp_keywords"

      expect(response.body).to include("SerpApi has no credentials yet.")
      expect(response.body).not_to include("sample results")
    end

    it "keeps the tabs and the sweep out of the page head, on a row of their own" do
      create(:dash_serp_keyword)

      get "/telemetry/settings/serp_keywords"

      head = document.at_css(".page-head")
      tabs = document.at_css(".page-tabs")

      expect(head.at_css("nav.segmented")).to be_nil
      expect(head.css(".page-head-actions a").map(&:text)).to eq([ "Import a list", "Track keyword" ])
      expect(tabs.at_css("nav.segmented a[aria-current=page]").text).to eq("Keywords")
      expect(tabs.at_css(".page-tabs-actions").text).to include("Check all")
    end

    it "says a sweep just went out on the button and nowhere else" do
      keyword = create(:dash_serp_keyword)
      site = create(:dash_serp_site, name: "Us", domain: "example.com")
      AhoyDashboard::SerpKeywordTarget.create!(keyword: keyword, site: site)
      serp_enabled!
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(AhoyDashboard).to receive(:cache).and_return(cache)
      cache.write(AhoyDashboard::Serp::SweepPlanQuery.queued_key(keyword), Time.current.to_i)

      get "/telemetry/settings/serp_keywords"

      expect(document.at_css(".page-tabs-actions button[disabled]").text).to eq("Check all")
      expect(response.body).to include("Everything was sent for checking a moment ago")
      expect(document.at_css(".alert-warning")).to be_nil
    end

    it "names the cadence the way the form does" do
      create(:dash_serp_keyword, frequency: :biweekly)

      get "/telemetry/settings/serp_keywords"

      expect(response.body).to include("Every 2 weeks")
      expect(response.body).not_to include("Biweekly")
    end

    it "links each keyword to its own page, so the same phrase on two devices opens two pages" do
      desktop = create(:dash_serp_keyword, query: "visiting hours", device: "desktop")
      mobile = create(:dash_serp_keyword, query: "visiting hours", device: "mobile")

      get "/telemetry/settings/serp_keywords"

      expect(response.body).to include("/telemetry/rank_keyword?keyword=#{desktop.id}",
                                       "/telemetry/rank_keyword?keyword=#{mobile.id}", "Mobile, en")
    end

    describe "changing the search itself" do
      def change(keyword, **overrides)
        patch "/telemetry/settings/serp_keywords/#{keyword.id}",
          params: { serp_keyword: { query: keyword.query, locations: "us", pages: "1", frequency: "daily",
                                    device: keyword.device, language: keyword.language, engine: "google",
                                    enabled: "1", site_ids: [ site.id.to_s ] }.merge(overrides) }
      end

      let(:keyword) { create(:dash_serp_keyword, query: "visiting hours", last_checked_at: 1.hour.ago) }

      before do
        create(:dash_serp_keyword_target, keyword: keyword, site: site)
        create(:dash_serp_check, run: create(:dash_serp_run, keyword: keyword), keyword: keyword, site: site)
      end

      it "starts a new history and keeps the old one on a paused copy of the old search" do
        change(keyword, device: "mobile")

        archived = sole_item(AhoyDashboard::SerpKeyword.where.not(id: keyword.id))
        expect(archived).to have_attributes(query: "visiting hours", device: "desktop", enabled: false)
        expect(archived.runs.count).to eq(1)
        expect(sole_item(archived.checks).target.site).to eq(site)
        expect(keyword.reload).to have_attributes(device: "mobile", last_checked_at: nil)
        expect(keyword.runs).to be_empty
        expect(keyword.checks).to be_empty
        expect(keyword.sites).to eq([ site ])
        expect(flash[:notice]).to include("history starts over", "paused keyword, visiting hours (Desktop, en)")
      end

      it "moves the old readings when the phrase changes" do
        change(keyword, query: "visitation hours")

        expect(keyword.reload.checks).to be_empty
        expect(AhoyDashboard::SerpKeyword.find_by(query: "visiting hours").checks.count).to eq(1)
      end

      it "keeps the history when only the case of the phrase changes" do
        change(keyword, query: "Visiting Hours")

        expect(keyword.reload.checks.count).to eq(1)
        expect(AhoyDashboard::SerpKeyword.count).to eq(1)
      end

      it "keeps the history when only the places or the cadence change" do
        change(keyword, locations: "us\ngb", frequency: "weekly")

        expect(keyword.reload.checks.count).to eq(1)
        expect(AhoyDashboard::SerpKeyword.count).to eq(1)
      end

      it "leaves everything alone when the new search is already tracked" do
        create(:dash_serp_keyword, query: "visiting hours", device: "mobile")

        change(keyword, device: "mobile")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(keyword.reload.checks.count).to eq(1)
        expect(AhoyDashboard::SerpKeyword.count).to eq(2)
      end

      it "says so on the edit screen" do
        get "/telemetry/settings/serp_keywords/#{keyword.id}/edit"

        expect(response.body).to include("its history starts over", "paused copy of the old search")
      end
    end

    it "lists what is tracked with the places under it" do
      create(:dash_serp_keyword, query: "visiting hours",
             locations: [ "us", "city:us:Chicago,Illinois,United States" ])

      get "/telemetry/settings/serp_keywords"

      expect(response.body).to include("visiting hours", "Chicago, Illinois, United States")
    end

    it "prints what the whole list costs a month" do
      create(:dash_serp_keyword, pages: 1, locations: [ "us" ], frequency: :daily)

      get "/telemetry/settings/serp_keywords"

      expect(response.body).to include("a month")
    end

    it "creates one and attaches the sites that were ticked" do
      post "/telemetry/settings/serp_keywords",
        params: { serp_keyword: { query: "visiting hours", locations: "us", pages: "1",
                                  frequency: "weekly", device: "desktop", language: "en",
                                  engine: "google", enabled: "1", site_ids: [ site.id.to_s ] } }

      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
      keyword = sole_item(AhoyDashboard::SerpKeyword)
      expect(keyword.query).to eq("visiting hours")
      expect(keyword.frequency).to eq("weekly")
      expect(keyword.sites).to eq([ site ])
    end

    it "reads a place per line" do
      post "/telemetry/settings/serp_keywords",
        params: { serp_keyword: { query: "visiting hours", pages: "1", frequency: "daily",
                                  device: "desktop", language: "en", engine: "google",
                                  locations: "us\r\ngb\r\n" } }

      expect(sole_item(AhoyDashboard::SerpKeyword).locations).to eq(%w[us gb])
    end

    it "refuses a second copy of the same search" do
      create(:dash_serp_keyword, query: "visiting hours")

      post "/telemetry/settings/serp_keywords",
        params: { serp_keyword: { query: "visiting hours", locations: "us", pages: "1",
                                  frequency: "daily", device: "desktop", language: "en",
                                  engine: "google" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Attach another site")
    end

    it "refuses a depth past what the adapters will fetch" do
      post "/telemetry/settings/serp_keywords",
        params: { serp_keyword: { query: "deep", locations: "us", pages: "9", frequency: "daily",
                                  device: "desktop", language: "en", engine: "google" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SerpKeyword.count).to be_zero
    end

    it "reads the stored searches when a site is attached later, and says how many" do
      keyword = create(:dash_serp_keyword, query: "visiting hours")
      run = create(:dash_serp_run, keyword: keyword)
      create(:dash_serp_run_page, run: run)

      patch "/telemetry/settings/serp_keywords/#{keyword.id}",
        params: { serp_keyword: { query: keyword.query, locations: "us", pages: "1",
                                  frequency: "daily", device: "desktop", language: "en",
                                  engine: "google", enabled: "1", site_ids: [ site.id.to_s ] } }

      expect(flash[:notice]).to include("1 past search")
      expect(sole_item(site.checks).position).to eq(2)
    end

    it "detaches a site that was unticked" do
      keyword = create(:dash_serp_keyword)
      create(:dash_serp_keyword_target, keyword: keyword, site: site)

      patch "/telemetry/settings/serp_keywords/#{keyword.id}",
        params: { serp_keyword: { query: keyword.query, locations: "us", pages: "1",
                                  frequency: "daily", device: "desktop", language: "en",
                                  engine: "google", enabled: "1" } }

      expect(keyword.reload.sites).to be_empty
    end

    it "fills in the search it was sent from and remembers where that was" do
      get "/telemetry/settings/serp_keywords/new",
        params: { query: "visiting hours", return_to: "/telemetry/seo/keyword_research" }

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("#serp_keyword_query")["value"]).to eq("visiting hours")
      expect(document.at_css("input[name=return_to]")["value"]).to eq("/telemetry/seo/keyword_research")
    end

    it "goes back to the page it was sent from once saved" do
      post "/telemetry/settings/serp_keywords",
        params: { return_to: "/telemetry/seo/keyword_research?seed=visiting",
                  serp_keyword: { query: "visiting hours", locations: "us", pages: "1", frequency: "daily",
                                  device: "desktop", language: "en", engine: "google", enabled: "1",
                                  site_ids: [ site.id.to_s ] } }

      expect(response).to redirect_to("/telemetry/seo/keyword_research?seed=visiting")
    end

    it "ignores a return address that points off the dashboard" do
      post "/telemetry/settings/serp_keywords",
        params: { return_to: "//evil.example/steal",
                  serp_keyword: { query: "visiting hours", locations: "us", pages: "1", frequency: "daily",
                                  device: "desktop", language: "en", engine: "google", enabled: "1",
                                  site_ids: [ site.id.to_s ] } }

      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
    end

    describe "a return address a browser would read as another host" do
      let(:hostile) { [ "/\t/evil.example", "/\n/evil.example", "/\r/evil.example", "//evil.example", "/\\evil.example" ] }

      it "is left off the form, so Cancel stays on the dashboard" do
        hostile.each do |value|
          get "/telemetry/settings/serp_keywords/new", params: { return_to: value }

          cancel = document.css("a").find { |link| link.text.strip == "Cancel" }
          expect(document.at_css("input[name=return_to]")).to be_nil, value.inspect
          expect(cancel["href"]).to eq("/telemetry/settings/serp_keywords"), value.inspect
        end
      end

      it "is not followed once saved" do
        hostile.each_with_index do |value, index|
          post "/telemetry/settings/serp_keywords",
            params: { return_to: value,
                      serp_keyword: { query: "visiting hours #{index}", locations: "us", pages: "1", frequency: "daily",
                                      device: "desktop", language: "en", engine: "google", enabled: "1",
                                      site_ids: [ site.id.to_s ] } }

          expect(response).to redirect_to("/telemetry/settings/serp_keywords"), value.inspect
        end
      end
    end

    it "ticks the sites a keyword already has when editing it" do
      keyword = create(:dash_serp_keyword, query: "visiting hours", locations: [ "us" ])
      AhoyDashboard::SerpKeywordTarget.create!(keyword: keyword, site: site)

      get "/telemetry/settings/serp_keywords/#{keyword.id}/edit"

      box = document.at_css("input[name='serp_keyword[site_ids][]'][value='#{site.id}']")
      expect(box["checked"]).to be_present
    end

    it "deletes one and the searches stored under it" do
      keyword = create(:dash_serp_keyword)
      create(:dash_serp_run_page, run: create(:dash_serp_run, keyword: keyword))

      delete "/telemetry/settings/serp_keywords/#{keyword.id}"

      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
      expect(AhoyDashboard::SerpRunPage.count).to be_zero
    end

    describe "checking now from the list" do
      before { allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true) }

      it "offers a check for each tracked keyword and one for all of them" do
        keyword = create(:dash_serp_keyword, query: "botnet takedown")
        create(:dash_serp_keyword_target, keyword: keyword)

        get "/telemetry/settings/serp_keywords"
        actions = document.css("form").map { |form| form["action"] }

        expect(actions).to include("/telemetry/settings/serp_keywords/#{keyword.id}/check", "/telemetry/rank_check")
      end

      it "disables the check on a paused keyword and says why" do
        keyword = create(:dash_serp_keyword, enabled: false)
        create(:dash_serp_keyword_target, keyword: keyword)

        get "/telemetry/settings/serp_keywords"
        button = document.css("button[disabled]").find { |node| node.text.strip == "Check" }

        expect(button["title"]).to eq("This keyword is paused.")
        expect(document.css("form").map { |form| form["action"] }).not_to include("/telemetry/settings/serp_keywords/#{keyword.id}/check")
      end
    end

    describe "the spend card" do
      def spend_card
        document.css("section[aria-labelledby='tm-spend-title']").first
      end

      it "says where the month stands against the cap" do
        create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 500, units_spent: 137,
                                                       units_reset_on: Date.current.beginning_of_month)

        get "/telemetry/settings/serp_keywords"

        expect(spend_card.text).to include("137 units of 500 this month. 363 left.")
        expect(spend_card.css("[role='progressbar']").first["aria-valuenow"]).to eq("27.4")
      end

      it "draws a bar for each day of the month with a title saying what it went on" do
        create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 500, units_spent: 20,
                                                       units_reset_on: Date.current.beginning_of_month)
        create(:dash_serp_spend_day, provider: "serpapi", on: Date.current, kind: :checks, units: 18)
        create(:dash_serp_spend_day, provider: "serpapi", on: Date.current, kind: :keywords, units: 2)

        get "/telemetry/settings/serp_keywords"

        expect(spend_card.css("svg|svg svg|title", "svg" => "http://www.w3.org/2000/svg").map(&:text)).to include(
          "#{Date.current.strftime("%b %-d")}: rank checks 18, keyword ideas 2"
        )
        expect(spend_card.css(".spend__item").map { |item| item.text.split.join(" ") })
          .to eq([ "Rank checks 18", "Keyword ideas 2" ])
      end

      it "warns on the page once the month passes the threshold" do
        create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 500, units_spent: 440,
                                                       units_reset_on: Date.current.beginning_of_month)

        get "/telemetry/settings/serp_keywords"

        expect(spend_card.text).to include("88% of this month's cap is spent")
      end

      it "says sample results cost nothing" do
        serp_enabled!(provider: :fake)
        keyword = create(:dash_serp_keyword, frequency: :daily, last_checked_at: Time.current)
        create(:dash_serp_keyword_target, keyword: keyword)

        get "/telemetry/settings/serp_keywords"

        expect(spend_card.text).to include("Sample results cost nothing.")
      end
    end

    describe "the track keyword form" do
      it "builds each place from a country and an optional city" do
        post "/telemetry/settings/serp_keywords",
          params: { serp_keyword: { query: "visiting hours", pages: "1", frequency: "daily", device: "desktop",
                                    language: "en", engine: "google",
                                    place_countries: [ "us", "us", "" ],
                                    place_cities: [ "", "Chicago,Illinois,United States", "Denver" ] } }

        expect(sole_item(AhoyDashboard::SerpKeyword).locations).to eq([ "us", "city:us:Chicago,Illinois,United States" ])
      end

      it "refuses a country the search provider cannot search from, and names it" do
        serp_enabled!(provider: :dataforseo)

        post "/telemetry/settings/serp_keywords",
          params: { serp_keyword: { query: "visiting hours", pages: "1", frequency: "daily", device: "desktop",
                                    language: "en", engine: "google", place_countries: [ "is" ], place_cities: [ "" ] } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("DataForSEO cannot search from Iceland.")
        expect(AhoyDashboard::SerpKeyword.count).to be_zero
      end

      it "only offers the countries the search provider can search from" do
        serp_enabled!(provider: :dataforseo)

        get "/telemetry/settings/serp_keywords/new"

        options = document.css("#serp_keyword_place_country_0 option").map { |option| option["value"] }
        expect(options).to include("us", "gb")
        expect(options).not_to include("is")
      end

      it "starts with one place picked" do
        get "/telemetry/settings/serp_keywords/new"

        expect(document.at_css("#serp_keyword_place_country_0 option[selected]")["value"]).to eq("us")
        expect(document.at_css("#serp_keyword_place_country_1 option[selected]")&.[]("value").to_s).to eq("")
      end

      it "reads the stored places back into the picker when editing" do
        keyword = create(:dash_serp_keyword, locations: [ "gb", "city:us:Chicago,Illinois,United States" ])

        get "/telemetry/settings/serp_keywords/#{keyword.id}/edit"

        expect(document.at_css("#serp_keyword_place_country_0 option[selected]")["value"]).to eq("gb")
        expect(document.at_css("#serp_keyword_place_country_1 option[selected]")["value"]).to eq("us")
        expect(document.at_css("#serp_keyword_place_city_1")["value"]).to eq("Chicago,Illinois,United States")
      end

      it "says what a keyword costs a month before it is saved" do
        serp_enabled!(provider: :serpapi)

        get "/telemetry/settings/serp_keywords/new"

        expect(document.at_css(".kw-big").text.squish).to eq("30 searches a month")
        expect(document.at_css(".kw-cost").text.squish).to include("Through SerpApi. Each check is 1 search.")
      end

      it "says checks are free while results are samples" do
        serp_enabled!(provider: :fake)

        get "/telemetry/settings/serp_keywords/new"

        expect(document.at_css(".kw-big").text.squish).to eq("Free")
        expect(document.at_css(".kw-cost").text.squish).to include("About 30 checks a month, free while results are samples.")
      end

      it "says rank tracking is off when it is" do
        get "/telemetry/settings/serp_keywords/new"

        expect(response.body).to include("Rank tracking is off.")
      end

      it "suggests popular searches that are not tracked yet" do
        create(:dash_search_console_keyword, query: "commissary list", impressions: 400)
        create(:dash_search_console_keyword, query: "visiting hours", impressions: 900)
        create(:dash_serp_keyword, query: "visiting hours")

        get "/telemetry/settings/serp_keywords/new"

        chips = document.css(".kw-chip")
        expect(chips.map { |chip| chip.text.strip }).to eq([ "commissary list" ])
        expect(chips.first["href"]).to include("query=commissary+list")
      end
    end
  end
end
