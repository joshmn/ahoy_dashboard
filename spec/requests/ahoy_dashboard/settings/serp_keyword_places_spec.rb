require "rails_helper"

RSpec.describe "Dashboard keyword places", type: :request do
  def catalogue!
    dash_place("United States", code: 2840, kind: "country", children: 1)
    dash_place("Illinois,United States", code: 21147, parent: 2840, kind: "state", children: 1)
    dash_place("Chicago,Illinois,United States", code: 101, parent: 21147)
  end

  def switch(on)
    AhoyDashboard::Preferences.write(:places, enabled: on)
    yield
  end

  before { sign_in create(:user, :admin) }

  describe "with the place list off" do
    it "keeps the country select and the typed city" do
      catalogue!

      get "/telemetry/settings/serp_keywords/new"

      expect(document.css("select[name='serp_keyword[place_countries][]']")).to be_present
      expect(document.css("#tm-places")).to be_empty
    end
  end

  describe "with the place list on but nothing built" do
    it "keeps the old fields and says where to build it" do
      switch(true) { get "/telemetry/settings/serp_keywords/new" }

      expect(document.css("select[name='serp_keyword[place_countries][]']")).to be_present
      expect(document.css("#tm-places")).to be_empty
      expect(document.css("a[href='/telemetry/settings/job_runs/places']")).to be_present
    end
  end

  describe "with a list to pick from" do
    it "swaps the two fields for one picker over the same posted values" do
      catalogue!

      switch(true) { get "/telemetry/settings/serp_keywords/new" }

      expect(document.css("select[name='serp_keyword[place_countries][]']")).to be_empty
      expect(document.css("input[type=hidden][name='serp_keyword[place_countries][]']")).to be_present
      expect(document.css("input[type=hidden][name='serp_keyword[place_cities][]']")).to be_present
      expect(document.css("#tm-places")).to be_present
    end

    it "opens the picker for the row whose button was pressed" do
      catalogue!

      switch(true) { get "/telemetry/settings/serp_keywords/new" }

      opener = document.css("[data-tm-place]").first

      expect(document.css("##{opener['data-tm-place']}")).to be_present
    end

    it "carries the place a keyword already has, and its parent" do
      catalogue!
      keyword = create(:dash_serp_keyword, locations: [ "city:us:Chicago,Illinois,United States" ])

      switch(true) { get "/telemetry/settings/serp_keywords/#{keyword.id}/edit" }

      row = document.css(".kw-place").first

      expect(row["data-place-name"]).to eq("Chicago, Illinois, United States")
      expect(row["data-place-parent"]).to eq("21147")
      expect(row["data-place-parent-label"]).to eq("Illinois, United States")
    end

    it "leaves a place that is not in the list pickable but with nowhere to start from" do
      catalogue!
      keyword = create(:dash_serp_keyword, locations: [ "city:us:Nowhere,Illinois,United States" ])

      switch(true) { get "/telemetry/settings/serp_keywords/#{keyword.id}/edit" }

      row = document.css(".kw-place").first

      expect(row["data-place-name"]).to eq("Nowhere,Illinois,United States")
      expect(row["data-place-parent"]).to eq("")
    end

    it "is on the import form too" do
      catalogue!

      switch(true) { get "/telemetry/settings/serp_keyword_import/new" }

      expect(document.css("input[type=hidden][name='serp_keyword_import[place_countries][]']")).to be_present
      expect(document.css("#tm-places")).to be_present
    end

    it "saves a picked place as the location the adapters already want" do
      catalogue!
      site = create(:dash_serp_site)

      switch(true) do
        post "/telemetry/settings/serp_keywords", params: {
          serp_keyword: {
            query: "federal prison", place_countries: [ "us" ],
            place_cities: [ "Chicago,Illinois,United States" ],
            device: "desktop", language: "en", pages: 1, frequency: "weekly",
            enabled: "1", site_ids: [ site.id.to_s ]
          }
        }
      end

      expect(AhoyDashboard::SerpKeyword.last.locations).to eq([ "city:us:Chicago,Illinois,United States" ])
    end
  end
end
