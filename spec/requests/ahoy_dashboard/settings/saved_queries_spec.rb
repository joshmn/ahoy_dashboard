require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard saved query settings", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  def submit_form(typed = {}, check: [])
    form = document.css("form").find { |candidate| candidate["action"].to_s.start_with?("/telemetry/settings/saved_queries") }
    fields = form.css("input[name]").reject do |input|
      input["type"].in?(%w[checkbox radio]) && !input.key?("checked") && check.exclude?(input["name"])
    end
    pairs = fields.map { |input| [ input["name"], typed.fetch(input["name"], input["value"].to_s) ] }

    post form["action"], params: URI.encode_www_form(pairs),
                         headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/saved_queries"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "sends a signed out visitor to sign in on a write too" do
      post "/telemetry/settings/saved_queries",
           params: { saved_query: { name: "x", params: { period: "7d" } } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::SavedQuery.count).to be_zero
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says there is nothing saved yet" do
      get "/telemetry/settings/saved_queries"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing saved yet")
    end

    # The sentence is read back out of the question every time, so it cannot
    # describe itself as something it is not.
    it "says what each question asks, read off its own params" do
      create(:dash_saved_query, name: "Organic readers",
             params: { "period" => "7d", "metric" => "pageviews", "dimension" => "country" })

      get "/telemetry/settings/saved_queries"
      said = document.at_css("tbody tr .t-when").text.strip

      expect(said).to include("Total pageviews", "by country", "last 7 days")
    end

    it "opens one in Explore, which is the whole record" do
      question = create(:dash_saved_query, params: { "period" => "7d", "dimension" => "page" })

      get "/telemetry/settings/saved_queries"
      opener = document.at_css("tbody tr .t-main a")

      expect(opener["href"]).to start_with("/telemetry/explore")
      expect(opener["href"]).to include("period=7d", "dimension=page")
      expect(opener.text.strip).to eq(question.name)
    end

    it "creates one from the params the explore handed it" do
      post "/telemetry/settings/saved_queries",
           params: { saved_query: { name: "Organic", pinned: "1",
                                    params: { period: "7d", dimension: "page", metric: "visitors" } } }

      expect(response).to redirect_to("/telemetry/settings/saved_queries")
      expect(sole_item(AhoyDashboard::SavedQuery)).to have_attributes(name: "Organic", pinned: true)
      expect(sole_item(AhoyDashboard::SavedQuery).params).to eq(
        "period" => "7d", "dimension" => "page", "metric" => "visitors"
      )
    end

    # These params end up in url_for. A stored :host or :controller would build a
    # link somewhere nobody asked for.
    it "keeps anything it was not offered out of the stored question" do
      post "/telemetry/settings/saved_queries",
           params: { saved_query: { name: "Odd", params: { period: "7d", host: "example.com" } } }

      expect(sole_item(AhoyDashboard::SavedQuery).params.keys).to eq([ "period" ])
    end

    it "refuses a question with nothing in it" do
      post "/telemetry/settings/saved_queries", params: { saved_query: { name: "Empty" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SavedQuery.count).to be_zero
    end

    it "refuses a name already taken" do
      create(:dash_saved_query, name: "Organic")

      post "/telemetry/settings/saved_queries",
           params: { saved_query: { name: "Organic", params: { period: "7d" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::SavedQuery.count).to eq(1)
    end

    it "reorders, because the order here is the order they sit in on the dashboard" do
      first = create(:dash_saved_query, name: "First", position: 1)
      create(:dash_saved_query, name: "Second", position: 2)

      patch "/telemetry/settings/saved_queries/#{first.id}", params: { saved_query: { nudge: "down" } }

      expect(AhoyDashboard::SavedQuery.ordered.map(&:name)).to eq([ "Second", "First" ])
    end

    it "deletes one" do
      question = create(:dash_saved_query)

      delete "/telemetry/settings/saved_queries/#{question.id}"

      expect(AhoyDashboard::SavedQuery.count).to be_zero
    end
  end

  # A question is composed in Explore, so it is changed in Explore. Without this
  # trip a saved question could only ever be renamed, and getting one wrong meant
  # deleting it and starting again.
  describe "changing what a saved question asks" do
    before { sign_in create(:user, :admin) }

    it "offers the way out to Explore, carrying the question and the record" do
      question = create(:dash_saved_query,
                        params: { "period" => "30d", "dimension" => "page" })

      get "/telemetry/settings/saved_queries/#{question.id}/edit"
      out = Nokogiri::HTML5(response.body).css("a").find { |a| a.text.include?("Change the question") }

      expect(out["href"]).to start_with("/telemetry/explore")
      expect(out["href"]).to include("saved=#{question.id}", "dimension=page")
    end

    # Explore offers to change the one you came from rather than to write a
    # second question saying nearly the same thing.
    it "turns Explore's save control into a save-changes for that record" do
      question = create(:dash_saved_query, name: "Readers")

      get "/telemetry/explore", params: { saved: question.id, dimension: "browser" }
      control = Nokogiri::HTML5(response.body).at_css("a[title*='Save']")

      expect(control.text.strip).to eq("Save changes")
      expect(control["href"]).to start_with("/telemetry/settings/saved_queries/#{question.id}/edit")
      expect(control["href"]).to include("dimension%5D=browser")
    end

    it "offers a plain save when nothing is being edited" do
      get "/telemetry/explore", params: { dimension: "browser" }
      control = Nokogiri::HTML5(response.body).at_css("a[title*='Save']")

      expect(control.text.strip).to eq("Save")
      expect(control["href"]).to start_with("/telemetry/settings/saved_queries/new")
    end

    it "shows the changed question on the form, unsaved, until it is saved" do
      question = create(:dash_saved_query, params: { "period" => "30d", "dimension" => "page" })

      get "/telemetry/settings/saved_queries/#{question.id}/edit",
          params: { question: { period: "7d", dimension: "browser" } }

      expect(response.body).to include("by browser", "last 7 days")
      expect(question.reload.params).to eq("period" => "30d", "dimension" => "page")
    end

    it "saves the changed question when the form is submitted" do
      question = create(:dash_saved_query, params: { "period" => "30d", "dimension" => "page" })

      patch "/telemetry/settings/saved_queries/#{question.id}",
            params: { saved_query: { name: question.name, params: { period: "7d", dimension: "browser" } } }

      expect(response).to redirect_to("/telemetry/settings/saved_queries")
      expect(question.reload.params).to eq("period" => "7d", "dimension" => "browser")
    end

    it "keeps offering to save changes after anything else on the page is changed" do
      question = create(:dash_saved_query, name: "Readers")

      get "/telemetry/explore", params: { saved: question.id, dimension: "browser" }
      links = Nokogiri::HTML5(response.body).css("main a[href^='/telemetry/explore']").map { |a| a["href"] }
      links.reject! { |href| href.start_with?("/telemetry/explore.csv") }

      expect(links).not_to be_empty
      expect(links).to all(include("saved=#{question.id}"))

      country = Nokogiri::HTML5(response.body).css("a").find { |a| a.text.strip == "Country" && a["href"].include?("dimension=country") }
      get country["href"]
      control = Nokogiri::HTML5(response.body).at_css("a[title*='Save']")

      expect(control.text.strip).to eq("Save changes")
      expect(control["href"]).to start_with("/telemetry/settings/saved_queries/#{question.id}/edit")
      expect(control["href"]).to include("dimension%5D=country")
    end

    it "carries the record through the filter dialog and the filter form" do
      question = create(:dash_saved_query, name: "Readers")
      visit = dash_visit(started_at: now - 1.day, visitor: "reader")
      dash_page_view(visit, path: "/going-in/faq", at: now - 1.day)
      filter = { dimension: "page", operator: "is", value: "/going-in/faq" }

      get "/telemetry/explore", params: { saved: question.id, filters: [ filter ] }
      page = Nokogiri::HTML5(response.body)
      editor = page.css("a[href^='/telemetry/filters/new']").first
      popover = page.css("a[href^='/telemetry/filter_values']").find do |a|
        Rack::Utils.parse_nested_query(URI.parse(a["href"]).query)["dimension"] == "page"
      end

      get editor["href"]
      expect(Nokogiri::HTML5(response.body).at_css("input[type=hidden][name=saved]")["value"]).to eq(question.id.to_s)

      get popover["href"]
      picks = Nokogiri::HTML5(response.body).css("[role=group][aria-label='Page values'] a").map { |a| a["href"] }
      expect(picks).not_to be_empty
      expect(picks).to all(include("saved=#{question.id}"))
    end

    it "updates the record rather than making a second one" do
      question = create(:dash_saved_query, name: "Readers", params: { "period" => "30d", "dimension" => "page" })

      get "/telemetry/explore", params: { saved: question.id, period: "30d" }
      browser = Nokogiri::HTML5(response.body).css("a").find { |a| a["href"].to_s.include?("dimension=browser") }
      get browser["href"]
      get Nokogiri::HTML5(response.body).at_css("a[title*='Save']")["href"]
      submit_form

      expect(AhoyDashboard::SavedQuery.count).to eq(1)
      expect(question.reload.params).to include("dimension" => "browser")
    end

    # A stale link is a link to a question somebody deleted, and everything
    # needed to read it is in the query string either way.
    it "still answers when the record it names is gone" do
      get "/telemetry/explore", params: { saved: 999_999, dimension: "browser" }

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML5(response.body).at_css("a[title*='Save']").text.strip).to eq("Save")
    end
  end

  describe "a question with filters on it" do
    before { sign_in create(:user, :admin) }

    let(:faq_filter) { { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq" } }

    def traffic!
      2.times do |index|
        visit = dash_visit(started_at: now - 1.day, visitor: "faq-#{index}")
        dash_page_view(visit, path: "/going-in/faq", at: now - 1.day)
      end
      3.times do |index|
        visit = dash_visit(started_at: now - 1.day, visitor: "home-#{index}")
        dash_page_view(visit, path: "/", at: now - 1.day)
      end
    end

    def pinned_value(name)
      get "/telemetry/pinned_questions"
      card = document.css("a[href^='/telemetry/explore']").find { |link| link.text.include?(name) }

      card.css("b").first.text.strip
    end

    it "keeps the filters when it is saved from Explore" do
      traffic!

      get "/telemetry/explore", params: { period: "30d", dimension: "browser", filters: [ faq_filter ] }
      get document.at_css("a[title*='Save']")["href"]
      submit_form({ "saved_query[name]" => "FAQ readers" }, check: [ "saved_query[pinned]" ])

      expect(response).to redirect_to("/telemetry/settings/saved_queries")
      question = sole_item(AhoyDashboard::SavedQuery)
      expect(question.params["filters"]).to eq([ faq_filter ])
      expect(question.sentence).to include("/going-in/faq")
      expect(pinned_value("FAQ readers")).to eq("2")
    end

    it "keeps the filters when it is edited" do
      traffic!
      question = create(:dash_saved_query, name: "FAQ readers", pinned: true,
                        params: { "period" => "30d", "metric" => "visitors", "filters" => [ faq_filter ] })

      get "/telemetry/settings/saved_queries/#{question.id}/edit"
      submit_form

      expect(response).to redirect_to("/telemetry/settings/saved_queries")
      expect(question.reload.params["filters"]).to eq([ faq_filter ])
      expect(pinned_value("FAQ readers")).to eq("2")
    end

    it "keeps an explicit no filters" do
      question = create(:dash_saved_query, params: { "period" => "30d", "filters" => "none" })

      get "/telemetry/settings/saved_queries/#{question.id}/edit"
      submit_form

      expect(question.reload.params["filters"]).to eq("none")
    end

    describe "with an or group in it" do
      let(:grouped) do
        [ { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq", "group" => 0 },
          { "dimension" => "page", "operator" => "is", "value" => "/", "group" => 0 },
          { "dimension" => "country", "operator" => "is", "value" => "US" } ]
      end

      it "saves the group, reads it back as or, and replays it" do
        get "/telemetry/settings/saved_queries/new",
            params: { question: { period: "30d", dimension: "browser", filters: grouped } }
        expect(document.css("input[name='saved_query[params][filters][0][group]']").map { |input| input["value"] }).to eq([ "0" ])
        expect(document.css("input[name='saved_query[params][filters][1][group]']").map { |input| input["value"] }).to eq([ "0" ])
        expect(document.at_css("input[name='saved_query[params][filters][2][group]']")).to be_nil

        submit_form({ "saved_query[name]" => "FAQ or home, in the US" })

        expect(response).to redirect_to("/telemetry/settings/saved_queries")
        question = sole_item(AhoyDashboard::SavedQuery)
        expect(question.params["filters"]).to eq(grouped)
        expect(question.sentence).to include("(Page is /going-in/faq or /) and Country is US")

        replayed = AhoyDashboard::QueryForm.from_params(Rack::Utils.parse_nested_query(
          URI.parse(AhoyDashboard::Engine.routes.url_helpers.explore_path(question.to_query)).query
        ))
        expect(replayed.filters.groups.map(&:size)).to eq([ 2, 1 ])
        expect(replayed.filters.sentence).to eq("(Page is /going-in/faq or /) and Country is US")
      end

      it "keeps the group through an edit" do
        question = create(:dash_saved_query, name: "FAQ or home, in the US",
                          params: { "period" => "30d", "filters" => grouped })

        get "/telemetry/settings/saved_queries/#{question.id}/edit"
        submit_form

        expect(response).to redirect_to("/telemetry/settings/saved_queries")
        expect(question.reload.params["filters"]).to eq(grouped)
      end
    end
  end

  describe "pinned to the dashboard" do
    before { sign_in create(:user, :admin) }

    def traffic!
      2.times do |index|
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-#{index}")
        dash_page_view(visit, path: "/going-in/faq", at: now - 1.day)
      end
    end

    it "draws nothing at all when nothing is pinned" do
      create(:dash_saved_query, pinned: false)

      get "/telemetry/pinned_questions"

      expect(response).to have_http_status(:ok)
      expect(document.at_css(".pinned-qs")).to be_nil
    end

    it "draws a card per pinned question, with its number and a sparkline" do
      traffic!
      create(:dash_saved_query, name: "Readers", pinned: true,
             params: { "period" => "30d", "metric" => "visitors" })

      get "/telemetry/pinned_questions"
      card = document.at_css(".pq-grid .pq")

      expect(card.at_css(".pq-name").text.strip).to eq("Readers")
      expect(card.at_css(".pq-val b").text.strip).to eq("2")
      expect(card["href"]).to start_with("/telemetry/explore")
      expect(JSON.parse(card.at_css(".pq-spark")["data-dash--spark-values-value"])).to be_an(Array)
    end

    it "shows no more than the cap, in the order on the list" do
      traffic!
      4.times { |index| create(:dash_saved_query, name: "Q#{index}", pinned: true, position: index) }

      get "/telemetry/pinned_questions"
      names = document.css(".pq-grid .pq-name").map { |node| node.text.strip }

      expect(names).to eq([ "Q0", "Q1", "Q2" ])
    end

    # A saved question is a hash somebody could have hand edited, and a dashboard
    # card is not the place to find that out.
    it "leaves a question it cannot read off the strip rather than falling over" do
      traffic!
      good = create(:dash_saved_query, name: "Fine", pinned: true, position: 1)
      create(:dash_saved_query, name: "Broken", pinned: true, position: 2)
        .update_column(:params, { "period" => "banana", "metric" => "vibes" })

      get "/telemetry/pinned_questions"

      expect(response).to have_http_status(:ok)
      expect(document.css(".pq-name").map { |node| node.text.strip }).to include(good.name)
    end

    it "is embedded on the dashboard between the chart and the cards" do
      create(:dash_saved_query, pinned: true)

      get "/telemetry"
      body = response.body

      expect(body.index(AhoyDashboard::PinnedQuestionsController::FRAME)).to be < body.index('id="panels"')
    end
  end
end
