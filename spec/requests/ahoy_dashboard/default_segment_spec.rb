require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard default segment", type: :request do
  def entry(dimension: "country", operator: "is", value: "US")
    { "dimension" => dimension, "operator" => operator, "value" => value }
  end

  def chips
    Nokogiri::HTML5(response.body).css(".chip").map { |chip| chip.text.squish }
  end

  def open_filter_dialog
    path = Nokogiri::HTML5(response.body).at_css("#tm-filter-modal")["data-dash--filter-modal-contents-value"]
    get(path, headers: { "Tm-Frame" => "tm-filter-controls" })
  end

  def form(params = {})
    AhoyDashboard::QueryForm.from_params(params)
  end

  before { sign_in create(:user, :admin) }

  describe "the query" do
    it "applies nothing when no segment is the default" do
      create(:dash_segment)

      expect(form.filters).to be_empty
      expect(form).not_to be_defaulted
      expect(form.to_query).not_to have_key(:filters)
    end

    it "applies the default's filters when the request carries no filters of its own" do
      create(:dash_segment, applied_by_default: true, filters: [ entry(value: "CA") ])

      expect(form.filters.map(&:label)).to eq([ "Country is CA" ])
      expect(form).to be_defaulted
      expect(form(period: "7d").filters.map(&:label)).to eq([ "Country is CA" ])
    end

    it "does not apply it when the request names its own filters" do
      create(:dash_segment, applied_by_default: true, filters: [ entry(value: "CA") ])

      explicit = form(filters: [ entry(dimension: "device", value: "mobile") ])

      expect(explicit.filters.map(&:label)).to eq([ "Device is mobile" ])
      expect(explicit).not_to be_defaulted
    end

    it "treats an explicit empty set as a choice rather than an absence" do
      create(:dash_segment, applied_by_default: true)

      cleared = form(filters: "none")

      expect(cleared.filters).to be_empty
      expect(cleared).not_to be_defaulted
      expect(cleared.to_query[:filters]).to eq("none")
    end

    it "leaves the filters out of a link while they are the default's own" do
      create(:dash_segment, applied_by_default: true)

      expect(form.to_query).not_to have_key(:filters)
      expect(form.with(period: "7d").to_query).to eq({ period: "7d" })
    end

    it "keeps the last chip's removal from bringing the default straight back" do
      create(:dash_segment, applied_by_default: true)

      expect(form.without_filter_params(0)).to include(filters: "none")
      expect(form.with(filters: nil).to_query[:filters]).to eq("none")
    end

    it "does not print the marker when there is no default to hold off" do
      expect(form.without_filter_params(0)).not_to have_key(:filters)
      expect(form.with(filters: nil).to_query).not_to have_key(:filters)
    end

    it "follows an edited default rather than the one a link was built against" do
      segment = create(:dash_segment, applied_by_default: true)
      link = form.to_query
      segment.update!(filters: [ entry(value: "CA") ])

      expect(form(link).filters.map(&:label)).to eq([ "Country is CA" ])
    end
  end

  describe "the dashboard" do
    it "opens with the default's chips on the bar and a way off it" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry"

      expect(response).to have_http_status(:ok)
      expect(chips).to eq([ "Country is US" ])
      expect(response.body).to include("Default filters")
      expect(response.body).to include(%(href="/telemetry/?filters=none&amp;period=30d"))
    end

    it "opens unfiltered when asked to" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry", params: { filters: "none" }

      expect(chips).to be_empty
      expect(response.body).not_to include("Default filters")
    end

    it "says nothing about a default when the filters are somebody's own" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry", params: { filters: [ entry(dimension: "device", value: "mobile") ] }

      expect(chips).to eq([ "Device is mobile" ])
      expect(response.body).not_to include("Default filters")
    end

    it "removes a default chip with a link that sticks" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry"
      remove = Nokogiri::HTML5(response.body).at_css(".chips .chip a.cx")["href"]

      expect(remove).to include("filters=none")

      get remove
      expect(chips).to be_empty
    end

    it "offers to save the applied filters as the default from the filter dialog" do
      get "/telemetry", params: { filters: [ entry(value: "CA") ] }
      open_filter_dialog

      expect(response.body).to include("Open with these")
      expect(response.body).to include(%(action="/telemetry/settings/default_segment"))
    end

    it "offers to stop instead once they are the default" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry"
      open_filter_dialog

      expect(response.body).to include("Stop opening with these")
      expect(response.body).not_to include("Open with these")
    end

    it "carries the default through Explore and an export the same way" do
      create(:dash_segment, applied_by_default: true)

      get "/telemetry/explore", params: { dimension: "country" }
      expect(response).to have_http_status(:ok)
      expect(chips).to eq([ "Country is US" ])
      expect(response.body).to include("Default filters")
      expect(response.body).to include(%(href="/telemetry/explore?dimension=country&amp;filters=none&amp;period=30d"))

      get "/telemetry/explore", params: { dimension: "country", filters: "none" }
      expect(chips).to be_empty
    end
  end

  describe "saving the default from the dashboard" do
    it "creates a segment called Default, marks it, and goes back to the view" do
      post "/telemetry/settings/default_segment", params: { period: "7d", filters: [ entry(value: "CA") ] }

      segment = AhoyDashboard::Segment.default
      expect(segment.name).to eq("Default")
      expect(segment.filters).to eq([ entry(value: "CA") ])
      expect(response).to redirect_to("/telemetry/?period=7d")
    end

    it "updates the existing default rather than making a second one" do
      existing = create(:dash_segment, name: "Home traffic", applied_by_default: true)

      post "/telemetry/settings/default_segment", params: { filters: [ entry(value: "CA") ] }

      expect(AhoyDashboard::Segment.count).to eq(1)
      expect(existing.reload.filters).to eq([ entry(value: "CA") ])
      expect(existing.name).to eq("Home traffic")
    end

    it "picks a free name when Default is taken" do
      create(:dash_segment, name: "Default")

      post "/telemetry/settings/default_segment", params: { filters: [ entry(value: "CA") ] }

      expect(AhoyDashboard::Segment.default.name).to eq("Default 2")
    end

    it "refuses an empty set" do
      post "/telemetry/settings/default_segment", params: { period: "7d" }

      expect(AhoyDashboard::Segment.default).to be_nil
      expect(response).to redirect_to("/telemetry/?period=7d")
      expect(flash[:alert]).to include("Add a filter first")
    end

    it "goes back to Explore when that is where it was asked from" do
      post "/telemetry/settings/default_segment",
           params: { return: "explore", dimension: "country", filters: [ entry(value: "CA") ] }

      expect(response).to redirect_to("/telemetry/explore?dimension=country&period=30d")
    end

    it "stops the default and keeps the view as it was" do
      create(:dash_segment, applied_by_default: true)

      delete "/telemetry/settings/default_segment", params: { filters: [ entry ] }

      expect(AhoyDashboard::Segment.default).to be_nil
      expect(response).to redirect_to("/telemetry/?filters%5B%5D%5Bdimension%5D=country&filters%5B%5D%5Boperator%5D=is&filters%5B%5D%5Bvalue%5D=US&period=30d")
    end
  end

  describe "from settings" do
    it "marks one segment as the default and unmarks the other" do
      first = create(:dash_segment, name: "First", applied_by_default: true)
      second = create(:dash_segment, name: "Second")

      post "/telemetry/settings/segments/#{second.id}/default"

      expect(response).to redirect_to("/telemetry/settings/segments")
      expect(AhoyDashboard::Segment.default).to eq(second)
      expect(first.reload).not_to be_applied_by_default
    end

    it "shows which one is the default on the list" do
      create(:dash_segment, name: "Canada", applied_by_default: true)
      create(:dash_segment, name: "Mobile")

      get "/telemetry/settings/segments"

      expect(response.body).to include("Default")
      expect(response.body).to include("Stop opening the dashboard with Canada")
      expect(response.body).to include("Open the dashboard with Mobile")
    end

    it "refuses to make a segment the default when the dashboard cannot read it" do
      broken = create(:dash_segment, :unreadable)

      post "/telemetry/settings/segments/#{broken.id}/default"

      expect(AhoyDashboard::Segment.default).to be_nil
      expect(flash[:alert]).to include("cannot read")
    end

    it "clears the default" do
      segment = create(:dash_segment, applied_by_default: true)

      delete "/telemetry/settings/segments/#{segment.id}/default"

      expect(AhoyDashboard::Segment.default).to be_nil
      expect(response).to redirect_to("/telemetry/settings/segments")
    end

    it "only ever allows one default" do
      create(:dash_segment, applied_by_default: true)

      expect { create(:dash_segment, applied_by_default: true) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is a 404 for a non admin" do
      segment = create(:dash_segment)
      sign_in create(:user)

      post "/telemetry/settings/segments/#{segment.id}/default"

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Segment.default).to be_nil
    end
  end
end
