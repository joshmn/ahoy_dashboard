require "rails_helper"

RSpec.describe "Dashboard serp keyword import screen", type: :request do
  def searched(query, impressions:, clicks: 0, position: 12.0)
    create(:dash_search_console_keyword, query: query, impressions: impressions, clicks: clicks,
           position: position, date: Date.current - 3)
  end

  before { sign_in create(:user, :admin) }

  describe "the list" do
    before do
      searched("commissary list", impressions: 900, clicks: 30, position: 4.5)
      searched("visiting hours", impressions: 40, clicks: 2, position: 18.2)

      get "/telemetry/settings/serp_keyword_import/new"
    end

    it "gives every row what a search and a sort need, so neither has to ask the server" do
      rows = document.css("[data-dash--keyword-list-target='row']")

      expect(rows.size).to eq(2)
      expect(rows.map { |row| row["data-term"] }).to include("commissary list")
      expect(rows.first["data-impressions"]).to be_present
      expect(rows.first["data-clicks"]).to be_present
      expect(rows.first["data-position"]).to be_present
    end

    it "offers a way to search the list" do
      expect(document.css("[data-dash--keyword-list-target='search']")).to be_present
      expect(document.css("label[for='kwi-find']")).to be_present
    end

    it "offers the three ways of reading the list as a sort, with one of them on" do
      sorts = document.css("[data-dash--keyword-list-target='sort']")

      expect(sorts.map { |node| node["data-key"] }).to eq(%w[impressions clicks position])
      expect(sorts.map { |node| node["aria-pressed"] }).to eq(%w[true false false])
    end

    it "offers select all and clear rather than one bare checkbox in a header" do
      actions = document.css(".kwi-acts button").map(&:text).map(&:strip)

      expect(actions).to include("Select all", "Clear")
    end

    it "wires every row into the running count" do
      boxes = document.css("[data-dash--keyword-form-target='pick']")

      expect(boxes.size).to eq(2)
    end
  end

  describe "the summary" do
    before do
      searched("commissary list", impressions: 900)

      get "/telemetry/settings/serp_keyword_import/new"
    end

    it "says what the whole import costs, not only what one keyword costs" do
      summary = document.css(".kw-sum")

      expect(summary).to be_present
      expect(summary.css("[data-dash--keyword-form-target='total']")).to be_present
      expect(summary.css("[data-dash--keyword-form-target='count']").text).to include("Nothing picked yet")
    end

    it "keeps the button with the summary rather than under the list" do
      expect(document.css(".kw-sum input[type=submit]")).to be_present
    end

    it "carries the cap on one import, so the warning can appear before it is hit" do
      expect(document.css("[data-dash--keyword-form-limit-value]").first["data-dash--keyword-form-limit-value"])
        .to eq(AhoyDashboard::Serp::KeywordImportForm::MAX_QUERIES.to_s)
    end
  end

  describe "pasting" do
    it "keeps the paste box shut until it is wanted" do
      searched("commissary list", impressions: 900)

      get "/telemetry/settings/serp_keyword_import/new"

      expect(document.css("details.disclosure[open]")).to be_empty
      expect(document.css("[data-dash--keyword-form-target='pasted']")).to be_present
    end

    it "opens it again when what was pasted did not save" do
      post "/telemetry/settings/serp_keyword_import",
        params: { serp_keyword_import: { pasted: "one\ntwo", place_countries: [ "chicago" ], place_cities: [ "" ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(document.css("details.disclosure[open]")).to be_present
    end
  end

  describe "a batch ticked in Search Console" do
    it "shows the ticked searches and keeps them on the form" do
      get "/telemetry/settings/serp_keyword_import/new",
        params: { batch: 1, track: [ "commissary list", "visiting hours" ] }

      expect(document.css("[data-dash--keyword-list-target='row']").size).to eq(2)
      expect(document.css("input[type=hidden][name='track[]']").size).to eq(2)
      expect(document.css(".kw-sum")).to be_present
    end

    it "sorts nothing, because a batch has no numbers to sort by" do
      get "/telemetry/settings/serp_keyword_import/new", params: { batch: 1, track: [ "commissary list" ] }

      expect(document.css("[data-dash--keyword-list-target='sort']")).to be_empty
      expect(document.css("[data-dash--keyword-list-target='search']")).to be_present
    end
  end
end
