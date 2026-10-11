require "rails_helper"

# The place picker on the keyword forms. It is optional twice over: off in the
# host's settings, and off until the list has actually been built. Either way
# the form falls back to the country select and the typed city it has always
# had, and the wire format never changes, so a keyword saved through the picker
# is the same row as a keyword typed in by hand.
RSpec.describe "Dashboard keyword places", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  def place(name, code:, parent: nil, kind: "city", children: 0)
    create(:dash_place, code: code, name: name, label: name.split(",").first, parent_code: parent,
                        country_code: "us", kind: kind, depth: name.split(",").size - 1,
                        children_count: children)
  end

  def catalogue!
    place("United States", code: 2840, kind: "country", children: 1)
    place("Illinois,United States", code: 21147, parent: 2840, kind: "state", children: 1)
    place("Chicago,Illinois,United States", code: 101, parent: 21147)
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

    # What the row already holds is where the picker opens, and where adding
    # another place starts from.
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

    # The whole point of not changing the wire format: a picked place saves
    # through the same params a typed one always did.
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
