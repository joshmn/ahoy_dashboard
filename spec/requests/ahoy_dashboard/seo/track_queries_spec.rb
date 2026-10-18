require "rails_helper"

RSpec.describe "Dashboard track queries from search console", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }
  let(:on) { now.to_date - 2 }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  around { |example| travel_to(now) { example.run } }

  def metrics(clicks, impressions, position: 14.0)
    { clicks: clicks, impressions: impressions, ctr: clicks.to_f / impressions, position: position }
  end

  def stored!(*queries)
    AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, device: "", country: "", **metrics(100, 4_000) } ])
    AhoyDashboard::SearchConsoleKeyword.absorb(queries.map do |query|
      { date: on, query: query, device: "", country: "", **metrics(10, 1_000) }
    end)
    AhoyDashboard::SearchConsoleRow.absorb(queries.flat_map do |query|
      [
        { date: on, query: query, page: "https://example.com/one", device: "", country: "", **metrics(6, 600) },
        { date: on, query: query, page: "https://example.com/two", device: "", country: "", **metrics(4, 400) }
      ]
    end)
  end

  def box(query)
    document.css("input[type=checkbox][name='track[]']").find { |input| input["value"] == query }
  end

  def track_form(id)
    document.at_css("form##{id}")
  end

  describe "on the reports" do
    before do
      sign_in create(:user, :admin)
      stored!("visiting hours", "halfway house rules")
      create(:dash_serp_keyword, query: "halfway house rules")
    end

    {
      "Performance" => [ "/telemetry/search_console_report", "sc-track" ],
      "Opportunities" => [ "/telemetry/seo/opportunity", "opp-track" ],
      "Cannibalization" => [ "/telemetry/seo/cannibalization", "cannibal-track" ],
      "Brand vs. non-brand" => [ "/telemetry/seo/brand_split", "non-brand-track" ]
    }.each do |name, (path, form_id)|
      describe name do
        it "gives an untracked query a box that belongs to the track form" do
          get path

          expect(response).to have_http_status(:ok)
          expect(box("visiting hours")["form"]).to eq(form_id)
          expect(box("visiting hours")["aria-label"]).to eq("Track visiting hours")
        end

        it "shows a tracked query as tracked with nothing to tick" do
          get path

          expect(box("halfway house rules")).to be_nil
          keyword = AhoyDashboard::SerpKeyword.find_by!(query: "halfway house rules")
          expect(document.css("a").map { |link| [ link.text.squish, link["href"] ] })
            .to include([ "Tracked", "/telemetry/rank_keyword?keyword=#{keyword.id}" ])
        end

        it "sends the ticked queries to the batch form and comes back here after" do
          get path

          form = track_form(form_id)
          expect(form["action"]).to eq("/telemetry/settings/serp_keyword_import/new")
          expect(form["method"]).to eq("get")
          expect(form.at_css("input[name=batch]")["value"]).to eq("1")
          expect(form.at_css("input[name=return_to]")["value"]).to eq(path)
          expect(form.at_css("button[type=submit]").text.squish).to eq("Track these")
        end
      end
    end

    it "puts a box on every opportunities table, each wired to its own form" do
      get "/telemetry/seo/opportunity"

      ids = document.css("input[type=checkbox][name='track[]']").map { |input| input["form"] }.uniq
      expect(ids).to include("opp-track", "striking-track")
      ids.each { |id| expect(track_form(id)).to be_present }
    end

    it "leaves the anonymized query on performance with nothing to tick" do
      AhoyDashboard::SearchConsoleKeyword.absorb([ { date: on, query: "", device: "", country: "", **metrics(50, 900) } ])

      get "/telemetry/search_console_report"

      expect(document.css("input[type=checkbox][name='track[]']").map { |input| input["value"] }).not_to include("")
    end

    it "has no track form on the pages tab" do
      get "/telemetry/search_console_report", params: { tab: "pages" }

      expect(track_form("sc-track")).to be_nil
      expect(document.css("input[name='track[]']")).to be_empty
    end
  end

  describe "the batch form" do
    before { sign_in create(:user, :admin) }

    def batch_params(*queries, return_to: "/telemetry/seo/opportunity")
      { batch: "1", track: queries, return_to: return_to }
    end

    it "lists the picked queries, all ticked, and leaves out the ones already tracked" do
      create(:dash_serp_keyword, query: "halfway house rules")

      get "/telemetry/settings/serp_keyword_import/new",
        params: batch_params("visiting hours", "Halfway  House Rules", "commissary list")

      expect(response).to have_http_status(:ok)
      ticked = document.css("input[name='serp_keyword_import[selected][]']")
      expect(ticked.map { |input| input["value"] }).to eq([ "visiting hours", "commissary list" ])
      expect(ticked.map { |input| input["checked"] }).to all(be_present)
      expect(document.css("input[name='track[]']").map { |input| input["value"] })
        .to eq([ "visiting hours", "commissary list" ])
    end

    it "does not offer the paste box or the search console candidates" do
      AhoyDashboard::SearchConsoleKeyword.absorb([ { date: on, query: "prison phone rates", **metrics(3, 500) } ])

      get "/telemetry/settings/serp_keyword_import/new", params: batch_params("visiting hours")

      expect(document.at_css("textarea[name='serp_keyword_import[pasted]']")).to be_nil
      expect(response.body).not_to include("prison phone rates")
    end

    it "says what the batch costs a month before it runs" do
      serp_enabled!(provider: :serpapi)

      get "/telemetry/settings/serp_keyword_import/new", params: batch_params("visiting hours", "commissary list")

      expect(document.at_css(".kw-cost").text.squish).to include("10 units a month", "Through SerpApi")
      expect(document.at_css("input[type=submit]")["value"]).to eq("Track 2 keywords")
    end

    it "says a batch is free while results are samples" do
      serp_enabled!(provider: :fake)

      get "/telemetry/settings/serp_keyword_import/new", params: batch_params("visiting hours", "commissary list")

      expect(document.at_css(".kw-cost").text.squish).to include("10 checks a month", "Free while results are samples.")
    end

    it "warns when the batch would run past what is left of the cap" do
      serp_enabled!(provider: :serpapi)
      allow_any_instance_of(AhoyDashboard::Settings::KeywordPlanPresenter).to receive(:capped?).and_return(true)
      allow_any_instance_of(AhoyDashboard::Settings::KeywordPlanPresenter).to receive(:cap).and_return(100)
      allow_any_instance_of(AhoyDashboard::Settings::KeywordPlanPresenter).to receive(:remaining).and_return(8)

      get "/telemetry/settings/serp_keyword_import/new", params: batch_params("visiting hours", "commissary list")

      over = document.at_css(".kw-over")
      expect(over["hidden"]).to be_nil
      expect(over.text.squish).to eq("That is more than what is left of your cap this month.")
    end

    it "sends somebody who ticked nothing back where they came from" do
      get "/telemetry/settings/serp_keyword_import/new", params: { batch: "1", return_to: "/telemetry/seo/opportunity" }

      expect(response).to redirect_to("/telemetry/seo/opportunity")
      expect(flash[:alert]).to eq("Tick at least one search to track.")
    end

    it "does not follow a return_to off the site" do
      get "/telemetry/settings/serp_keyword_import/new", params: { batch: "1", return_to: "//evil.example" }

      expect(response).to redirect_to("/telemetry/settings/serp_keywords")
    end

    describe "a return_to a browser would read as another host" do
      let(:hostile) { [ "/\t/evil.example", "/\n/evil.example", "/\r/evil.example", "//evil.example", "/\\evil.example" ] }

      it "is not followed" do
        hostile.each do |value|
          get "/telemetry/settings/serp_keyword_import/new", params: { batch: "1", return_to: value }

          expect(response).to redirect_to("/telemetry/settings/serp_keywords"), value.inspect
        end
      end

      it "is left off the form, so Cancel stays on the dashboard" do
        hostile.each do |value|
          get "/telemetry/settings/serp_keyword_import/new", params: batch_params("visiting hours", return_to: value)

          cancel = document.css("a").find { |link| link.text.strip == "Cancel" }
          expect(document.at_css("input[name=return_to]")).to be_nil, value.inspect
          expect(cancel["href"]).to eq("/telemetry/settings/serp_keywords"), value.inspect
        end
      end
    end

    it "tracks the ticked ones under one set of settings and goes back to the report" do
      post "/telemetry/settings/serp_keyword_import",
        params: batch_params("visiting hours", "commissary list").merge(
          serp_keyword_import: { selected: [ "visiting hours" ], locations: "us", pages: "2",
                                 frequency: "daily", device: "mobile", language: "en", engine: "google",
                                 site_ids: [ site.id.to_s ], tags: [ "Visiting" ] }
        )

      expect(response).to redirect_to("/telemetry/seo/opportunity")
      keyword = sole_item(AhoyDashboard::SerpKeyword)
      expect(keyword.query).to eq("visiting hours")
      expect([ keyword.frequency, keyword.pages, keyword.device, keyword.tags ]).to eq([ "daily", 2, "mobile", [ "Visiting" ] ])
      expect(keyword.sites).to eq([ site ])
      expect(flash[:notice]).to eq("1 keyword now tracked.")
    end

    it "keeps the batch on screen when the settings are refused" do
      post "/telemetry/settings/serp_keyword_import",
        params: batch_params("visiting hours", "commissary list").merge(
          serp_keyword_import: { selected: [ "visiting hours" ], locations: "us", pages: "1",
                                 frequency: "hourly", device: "desktop", language: "en", engine: "google" }
        )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(document.css("input[name='serp_keyword_import[selected][]']").map { |input| [ input["value"], input["checked"].present? ] })
        .to eq([ [ "visiting hours", true ], [ "commissary list", false ] ])
      expect(document.at_css("input[name=return_to]")["value"]).to eq("/telemetry/seo/opportunity")
      expect(AhoyDashboard::SerpKeyword.count).to be_zero
    end
  end

  describe "the search card and the whole list behind it" do
    before do
      sign_in create(:user, :admin)
      stored!("visiting hours", "halfway house rules")
      create(:dash_serp_keyword, query: "halfway house rules")
    end

    def tracked_link(query)
      keyword = AhoyDashboard::SerpKeyword.find_by!(query: query)
      document.css("a").find { |link| link["href"] == "/telemetry/rank_keyword?keyword=#{keyword.id}" }
    end

    it "leaves the nine rows on the card alone" do
      get "/telemetry/search_console"

      expect(response).to have_http_status(:ok)
      expect(track_form("gsc-track")).to be_nil
      expect(document.css("input[name='track[]']")).to be_empty
    end

    it "gives an untracked query a box once the whole list is open" do
      get "/telemetry/search_console", params: { view: "details" }

      expect(response).to have_http_status(:ok)
      expect(box("visiting hours")["form"]).to eq("gsc-track")
      expect(document.at_css("#gsc-track-all")).to be_present
    end

    it "comes back to the dashboard rather than to the frame the list is drawn in" do
      get "/telemetry/search_console", params: { view: "details" }

      return_to = track_form("gsc-track").at_css("input[name=return_to]")["value"]
      expect(return_to).to start_with("/telemetry")
      expect(return_to).not_to include("search_console")
    end

    it "marks a query it already tracks with a tick that says so" do
      get "/telemetry/search_console", params: { view: "details" }

      expect(box("halfway house rules")).to be_nil
      expect(tracked_link("halfway house rules").text.squish).to eq("halfway house rules is already tracked")
    end

    it "has nothing to tick on the pages tab" do
      get "/telemetry/search_console", params: { view: "details", tab: "pages" }

      expect(track_form("gsc-track")).to be_nil
      expect(document.css("input[name='track[]']")).to be_empty
    end
  end

  describe "on the stored rows" do
    before do
      sign_in create(:user, :admin)
      stored!("visiting hours", "halfway house rules")
      create(:dash_serp_keyword, query: "halfway house rules")
    end

    it "gives an untracked query a box and a form that comes back here" do
      get "/telemetry/settings/search_console_rows"

      expect(response).to have_http_status(:ok)
      expect(box("visiting hours")["form"]).to eq("rows-track")
      expect(document.at_css("#rows-track-all")).to be_present
      expect(track_form("rows-track").at_css("input[name=return_to]")["value"])
        .to eq("/telemetry/settings/search_console_rows")
    end

    it "shows a tracked query as tracked with nothing to tick" do
      get "/telemetry/settings/search_console_rows"

      expect(box("halfway house rules")).to be_nil
      keyword = AhoyDashboard::SerpKeyword.find_by!(query: "halfway house rules")
      expect(document.css("a").map { |link| [ link.text.squish, link["href"] ] })
        .to include([ "Tracked", "/telemetry/rank_keyword?keyword=#{keyword.id}" ])
    end
  end

  describe "cannibalization" do
    before do
      sign_in create(:user, :admin)
      stored!("visiting hours")
    end

    it "can tick every search at once even though each one is its own card" do
      get "/telemetry/seo/cannibalization"

      master = document.at_css("#cannibal-track-all")
      expect(master).to be_present
      expect(document.at_css("label[for='cannibal-track-all']").text.squish).to eq("Select every search")
      expect(master.ancestors("[data-controller='dash--check-all']")).to be_present
      expect(box("visiting hours").ancestors("[data-controller='dash--check-all']")).to be_present
    end
  end
end
