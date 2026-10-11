require "rails_helper"

# The filter dialog's rail is what renders this partial. It is rendered on its
# own here rather than read out of the page, because everything asserted is the
# partial's own contract.
RSpec.describe "Dashboard dashboard filter segments", type: :request do
  def entry(dimension: "country", operator: "is", value: "US")
    { "dimension" => dimension, "operator" => operator, "value" => value }
  end

  def menu(params = {})
    AhoyDashboard::DashboardsController.renderer.new(script_name: AhoyDashboard.mount_path).render(
      partial: "ahoy_dashboard/dashboards/filter_segments",
      locals: { query: AhoyDashboard::QueryForm.from_params(params) }
    )
  end

  it "renders nothing at all when nothing is saved and nothing is filtered" do
    expect(menu.strip).to be_empty
  end

  it "lists every saved segment under one heading, in position order" do
    create(:dash_segment, name: "Later", position: 2)
    create(:dash_segment, name: "Sooner", position: 1, filters: [ entry(value: "CA") ])

    html = menu

    expect(Nokogiri::HTML5.fragment(html).text.scan("Segments").size).to eq(1)
    expect(html).to include("Segments")
    expect(html.index("Sooner")).to be < html.index("Later")
  end

  it "says what kind each one is and when it was made" do
    create(:dash_segment, name: "Non-customer traffic")

    expect(menu).to include("Site segment. Created")
  end

  it "links a segment at the dashboard carrying its own filters" do
    create(:dash_segment, filters: [ entry(operator: "is_not", value: "US") ])

    html = menu

    expect(html).to include("filters%5B%5D%5Bdimension%5D=country")
    expect(html).to include("filters%5B%5D%5Boperator%5D=is_not")
    expect(html).to include("filters%5B%5D%5Bvalue%5D=US")
  end

  # Replacing rather than adding, the same call Filters#replacing makes for a
  # clicked row: two "is" filters on one dimension ask for rows that are two
  # things at once, which is nothing.
  # Asserted on the segment's own link rather than on the whole partial, because
  # the save-these-filters link beside it carries the applied filters on purpose:
  # that is the whole point of it.
  it "replaces the filters already applied rather than adding to them" do
    create(:dash_segment, filters: [ entry(value: "CA") ])

    html = menu(filters: [ entry(value: "US") ])
    href = Nokogiri::HTML5.fragment(html).at_css("a")["href"]

    expect(href).to include("filters%5B%5D%5Bvalue%5D=CA")
    expect(href).not_to include("filters%5B%5D%5Bvalue%5D=US")
  end

  it "keeps the rest of the view somebody is looking at" do
    create(:dash_segment)

    expect(menu(period: "7d", metric: "pageviews")).to include("period=7d")
  end

  it "ticks the segment whose filters are the ones applied" do
    create(:dash_segment, name: "Canada", filters: [ entry(value: "CA") ])

    html = menu(filters: [ entry(value: "CA") ])

    expect(html).to include(%(aria-current="true"))
  end

  it "ticks nothing when the dashboard is filtered by something else" do
    create(:dash_segment, filters: [ entry(value: "CA") ])

    expect(menu(filters: [ entry(value: "US") ])).not_to include("active")
  end

  describe "a segment whose property is gone" do
    it "is still on the menu, disabled, with the reason" do
      create(:dash_segment, :unreadable, name: "Broken")

      html = menu

      expect(html).to include("Broken")
      expect(html).to include("disabled")
      expect(html).to include("Not being applied")
    end

    it "is not a link, so it cannot be applied as no filters at all" do
      create(:dash_segment, :unreadable)

      expect(menu).not_to include("<a")
    end
  end

  it "says the actions act on the filters already applied, under a heading of their own" do
    create(:dash_segment)

    html = Nokogiri::HTML5.fragment(menu(filters: [ entry(value: "CA") ]))
    applied = html.at_css("section[aria-labelledby=tm-filter-rail-applied]")

    expect(html.at_css("#tm-filter-rail-applied").text).to eq("Applied filters")
    expect(applied.text).to include("Save as a segment")
    expect(html.at_css("section[aria-labelledby=tm-filter-rail-segments]").text).not_to include("Save as a segment")
  end

  it "puts no segments heading over the actions when none are saved" do
    html = menu(filters: [ entry(value: "CA") ])

    expect(html).to include("Applied filters")
    expect(html).not_to include("Segments")
  end

  describe "saving what is already filtered" do
    it "offers it when the dashboard is filtered" do
      html = menu(filters: [ entry(value: "CA") ])

      expect(html).to include("Save as a segment")
      expect(html).to include("/telemetry/settings/segments/new")
    end

    it "carries the applied filters to the form" do
      expect(menu(filters: [ entry(value: "CA") ])).to include("filters%5B%5D%5Bvalue%5D=CA")
    end

    it "does not offer it when nothing is filtered" do
      create(:dash_segment)

      expect(menu).not_to include("Save as a segment")
    end
  end

  describe "hiding what is already filtered" do
    it "offers it when the dashboard is filtered, carrying the filters to the exclusion form" do
      html = menu(filters: [ entry(dimension: "asn", operator: "contains", value: "CLOUD") ])
      link = Nokogiri::HTML5.fragment(html).css("a").find { |node| node.text.strip == "Hide traffic like this..." }

      expect(link["href"]).to start_with("/telemetry/settings/exclusions/new?")
      expect(link["href"]).to include("filters%5B%5D%5Bvalue%5D=CLOUD")
    end

    it "does not offer it when nothing is filtered" do
      create(:dash_segment)

      expect(menu).not_to include("Hide traffic like this")
    end

    it "does not offer it for an exit page filter, which an exclusion cannot use" do
      html = menu(filters: [ entry(dimension: "exit_page", value: "/") ])

      expect(html).to include("Save as a segment")
      expect(html).not_to include("Hide traffic like this")
    end
  end

  describe "on the dashboard" do
    before { sign_in create(:user, :admin) }

    it "renders with segments saved" do
      create(:dash_segment)

      get "/telemetry"

      expect(response).to have_http_status(:ok)
    end

    it "keeps saving a segment inside the mounted dashboard" do
      get "/telemetry/filter_dialog", params: { filters: [entry(value: "CA")] }, headers: { "Tm-Frame" => "tm-filter-controls" }
      link = Nokogiri::HTML5(response.body).at_css("a[href*='/settings/segments/new']")

      expect(URI.parse(link["href"]).path).to eq("/telemetry/settings/segments/new")
    end

    it "keeps hiding filtered traffic inside the mounted dashboard" do
      get "/telemetry/filter_dialog", params: { filters: [entry(value: "CA")] }, headers: { "Tm-Frame" => "tm-filter-controls" }
      link = Nokogiri::HTML5(response.body).at_css("a[href*='/settings/exclusions/new']")

      expect(URI.parse(link["href"]).path).to eq("/telemetry/settings/exclusions/new")
    end

    it "puts no segments heading on the filter dialog with none saved" do
      get "/telemetry/filter_dialog", headers: { "Tm-Frame" => "tm-filter-controls" }

      rail = Nokogiri::HTML5(response.body).at_css("#tm-filter-modal nav[aria-label=Dimensions]").text

      expect(rail).to include("Page")
      expect(rail).not_to include("Segments")
    end
  end
end
