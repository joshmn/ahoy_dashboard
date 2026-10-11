require "rails_helper"

RSpec.describe "Dashboard places", type: :request do
  def place(name, code:, parent: nil, country: "us", kind: "city", children: 0)
    create(:dash_place, code: code, name: name, label: name.split(",").first, parent_code: parent,
                        country_code: country, kind: kind, depth: name.split(",").size - 1,
                        children_count: children)
  end

  def document
    Nokogiri::HTML5(response.body)
  end

  def rows
    document.css("[data-dash--place-picker-target='item']")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/places"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is closed to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/places"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    let!(:us) { place("United States", code: 2840, kind: "country", children: 1) }
    let!(:illinois) { place("Illinois,United States", code: 21147, parent: 2840, kind: "state", children: 1) }
    let!(:chicago) { place("Chicago,Illinois,United States", code: 101, parent: 21147) }

    it "offers the countries when nothing is named" do
      get "/telemetry/settings/places"

      expect(response).to have_http_status(:ok)
      expect(rows.map { |row| row["data-label"] }).to eq([ "United States" ])
    end

    it "opens a place into what is inside it" do
      get "/telemetry/settings/places", params: { parent: us.code }

      expect(rows.map { |row| row["data-label"] }).to eq([ "Illinois, United States" ])
    end

    # Both, because a state is somewhere you can search from and a list of
    # cities, and a row that only did one of them would make half of them
    # unreachable.
    it "gives a place with something inside it a way to pick it and a way to open it" do
      get "/telemetry/settings/places", params: { parent: us.code }

      expect(rows.first["data-action"]).to include("choose")
      expect(document.css("[data-action*='dash--place-picker#into']").map { |node| node["data-parent"] })
        .to eq([ illinois.code.to_s ])
    end

    it "gives a place with nothing inside it no way to open it" do
      get "/telemetry/settings/places", params: { parent: illinois.code }

      expect(document.css("[data-action*='dash--place-picker#into']")).to be_empty
    end

    it "carries what the form has to write back" do
      get "/telemetry/settings/places", params: { parent: illinois.code }

      expect(rows.first["data-country"]).to eq("us")
      expect(rows.first["data-name"]).to eq("Chicago,Illinois,United States")
      expect(rows.first["data-parent"]).to eq(illinois.code.to_s)
      expect(rows.first["data-parent-label"]).to eq("Illinois, United States")
    end

    # A country searches the whole country, which is the empty city field the
    # form has always posted.
    it "writes no city back for a country" do
      get "/telemetry/settings/places"

      expect(rows.first["data-country"]).to eq("us")
      expect(rows.first["data-name"]).to eq("")
    end

    it "offers a way back out of a place" do
      get "/telemetry/settings/places", params: { parent: illinois.code }

      back = document.css(".pop-hd [data-parent]").first

      expect(back["data-parent"]).to eq(us.code.to_s)
    end

    it "searches rather than listing when something is typed" do
      get "/telemetry/settings/places", params: { q: "chic" }

      expect(rows.map { |row| row["data-label"] }).to eq([ "Chicago, Illinois, United States" ])
    end

    it "says so when nothing matches" do
      get "/telemetry/settings/places", params: { q: "nowhere" }

      expect(rows).to be_empty
      expect(document.text).to include("nowhere")
    end

    it "answers an unknown parent with the countries rather than an error" do
      get "/telemetry/settings/places", params: { parent: "999999" }

      expect(response).to have_http_status(:ok)
      expect(rows.map { |row| row["data-label"] }).to eq([ "United States" ])
    end
  end
end
