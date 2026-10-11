require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/search_console"

RSpec.describe "Dashboard Search Console report", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  # Three tables at three grains. The page reads all three and says which is
  # which, so the fixtures have to be all three too.
  def stored!(days: 5)
    days.times do |back|
      on = now.to_date - back - 1

      AhoyDashboard::SearchConsoleTotal.absorb([
        { date: on, clicks: 100 + back, impressions: 1_000 + back, ctr: 0.1, position: 5.0 + (back * 0.1) }
      ])
      AhoyDashboard::SearchConsoleKeyword.absorb([
        { date: on, query: "federal prison consultant", clicks: 40, impressions: 400, ctr: 0.1, position: 2.0 },
        { date: on, query: "halfway house rules", clicks: 10, impressions: 200, ctr: 0.05, position: 8.0 }
      ])
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: on, query: "federal prison consultant", page: "/consult", clicks: 30, impressions: 300, ctr: 0.1, position: 2.0 },
        { date: on, query: "federal prison consultant", page: "/", clicks: 10, impressions: 100, ctr: 0.1, position: 2.0 }
      ])
    end
  end

  # The same length of time before the range, which is what every delta compares
  # against.
  def earlier!(clicks:, from: 80, to: 35)
    AhoyDashboard::SearchConsoleTotal.absorb((to..from).map do |back|
      { date: now.to_date - back, clicks: clicks, impressions: 5_000, ctr: 0.1, position: 9.0 }
    end)
  end

  def pill(tile)
    tile.at_css("[title^='vs ']")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/search_console_report"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is closed to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/search_console_report"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "keeps Sync now on the page and says Google has to be connected first" do
      search_console_enabled!

      get "/telemetry/search_console_report"

      document = Nokogiri::HTML5(response.body)
      button = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == "Sync now" }

      expect(button).to be_present
      expect(document.at_css("##{button['aria-describedby']}").text).to include("Connect Google first.")
      expect(response.body).to include("/telemetry/settings/google_connection")
    end

    it "keeps Sync now off while Search Console is switched off, even with a property picked" do
      store_google_client
      search_console_settings(enabled: false) do
        create(:dash_google_account, :with_property)

        get "/telemetry/search_console_report"
      end

      button = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == "Sync now" }

      expect(button).to be_present
      expect(document.at_css("##{button['aria-describedby']}").text).to include("Search Console is off.")
    end

    it "renders against an empty database" do
      get "/telemetry/search_console_report"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Search Console")
    end

    describe "the four numbers" do
      it "reads them off the day totals" do
        stored!

        get "/telemetry/search_console_report"
        tiles = document.css(".seo-chart-card nav a").map { |tile| tile.text.split.join(" ") }

        expect(tiles.first).to start_with("Clicks 510")
        expect(tiles[1]).to start_with("Impressions 5.0k")
      end

      # Position counts the wrong way round: one is the best a page can do, so a
      # fall in it is the site doing better and reads green.
      it "reads a fall in position as the good direction" do
        stored!
        earlier!(clicks: 1)

        get "/telemetry/search_console_report", params: { period: "30d" }
        position = document.css(".seo-chart-card nav a").last

        expect(position.text).to include("Avg position")
        expect(pill(position).text.squish).to include("down", "better")
      end

      it "reads a fall in clicks as the bad direction" do
        stored!
        earlier!(clicks: 100_000)

        get "/telemetry/search_console_report", params: { period: "30d" }
        clicks = document.at_css(".seo-chart-card nav a")

        expect(pill(clicks).text.squish).to include("down", "worse")
      end

      it "prints no pill at all when there is nothing to compare against" do
        stored!

        get "/telemetry/search_console_report"

        expect(document.at_css(".seo-chart-card nav a [title^='vs ']")).to be_nil
      end

      it "moves click through rate in points and position in places rather than percents" do
        stored!
        earlier!(clicks: 250)

        get "/telemetry/search_console_report", params: { period: "30d" }
        clicks, _impressions, ctr, position = document.css(".seo-chart-card nav a").to_a

        expect(pill(clicks).text.squish).to include("%")
        expect(pill(ctr).text.squish).to include("5.2 pts", "up")
        expect(pill(ctr).text).not_to include("%")
        expect(pill(position).text.squish).to include("3.8", "down", "better")
        expect(pill(position).text).not_to include("%")
      end

      it "names the dates it compared against" do
        stored!
        earlier!(clicks: 250)

        get "/telemetry/search_console_report", params: { period: "30d" }

        expect(pill(document.at_css(".seo-chart-card nav a"))["title"]).to match(/\Avs \w{3} \d{1,2} to \w{3} \d{1,2}\z/)
      end

      it "compares nothing when the earlier period was only partly pulled" do
        stored!
        earlier!(clicks: 1, from: 45, to: 35)

        get "/telemetry/search_console_report", params: { period: "30d" }

        expect(document.at_css(".seo-chart-card nav a [title^='vs ']")).to be_nil
      end
    end

    describe "the chart" do
      def options
        JSON.parse(document.at_css("[data-dash--chart-options-value]")["data-dash--chart-options-value"])
      end

      it "draws clicks by default and never names a table" do
        stored!

        get "/telemetry/search_console_report"

        expect(document.at_css(".seo-chart-card nav a[aria-current=true]").text.squish).to start_with("Clicks")
        expect(response.body).not_to include("ahoy_dashboard_search_console")
        expect(options.dig("library", "scales", "y", "reverse")).to be(false)
        expect(options.dig("library", "tmFill")).to be(true)
      end

      # A banded axis running the wrong way is not the same kind of picture as a
      # count rising off zero, and filling under it would read as a quantity.
      it "turns the axis round for position and takes the fill off" do
        stored!

        get "/telemetry/search_console_report", params: { measure: "position" }

        expect(options.dig("library", "scales", "y", "reverse")).to be(true)
        expect(options.dig("library", "tmFill")).to be(false)
        expect(options.dig("library", "tmStroke")).to be_present
      end

      it "says where the line stops, because Google lands days late" do
        stored!

        get "/telemetry/search_console_report"

        expect(document.at_css(".sc-data-note").text).to include("Data runs through", "two to three days late")
      end

      it "falls back to clicks on a measure nobody registered" do
        stored!

        get "/telemetry/search_console_report", params: { measure: "vibes" }

        expect(document.at_css(".seo-chart-card nav a[aria-current=true]").text.squish).to start_with("Clicks")
      end
    end

    describe "the rows" do
      def labels
        document.css("tbody tr .sc-label .seo-label").map { |node| node["title"] }
      end

      # Queries come off the keyword table, not the row table: Google withholds
      # far more at query by page than at query alone.
      it "reads queries off the keyword table, ranked by clicks" do
        stored!

        get "/telemetry/search_console_report"

        expect(labels).to eq([ "federal prison consultant", "halfway house rules" ])
        expect(document.at_css("tbody tr .sc-label .mono")).to be_nil
      end

      it "names an anonymized query the same way the card does, and opens nothing for it" do
        stored!
        AhoyDashboard::SearchConsoleKeyword.absorb([
          { date: now.to_date - 1, query: "", clicks: 90, impressions: 900, ctr: 0.1, position: 3.0 }
        ])

        get "/telemetry/search_console_report"
        cell = document.css("tbody tr .sc-label").find { |node| node.text.include?("(anonymized)") }

        expect(cell).to be_present
        expect(cell.at_css("a")).to be_nil
        expect(document.css("tbody tr .sc-label").map(&:text).join).not_to include("—")
      end

      it "names an anonymized query the same way on the seo overview" do
        stored!
        AhoyDashboard::SearchConsoleKeyword.absorb([
          { date: now.to_date - 1, query: "", clicks: 90, impressions: 900, ctr: 0.1, position: 3.0 }
        ])

        get "/telemetry/seo"
        cell = document.css("tbody tr td").find { |node| node.text.include?("(anonymized)") }

        expect(cell).to be_present
        expect(cell.at_css("a")).to be_nil
      end

      it "reads pages off the row table" do
        stored!

        get "/telemetry/search_console_report", params: { tab: "pages" }

        expect(labels).to contain_exactly("/consult", "/")
        expect(document.at_css("tbody tr .sc-label .mono")).to be_present
      end

      it "falls back to queries on a tab nobody registered" do
        stored!

        get "/telemetry/search_console_report", params: { tab: "banana" }

        expect(labels).to include("federal prison consultant")
      end

      it "narrows to the filter term" do
        stored!

        get "/telemetry/search_console_report", params: { q: "halfway" }

        expect(labels).to eq([ "halfway house rules" ])
        expect(document.at_css("form[role=search]").parent.text).to include("1 query")
      end

      it "says so rather than going blank when nothing matches" do
        stored!

        get "/telemetry/search_console_report", params: { q: "nothing like this" }

        expect(document.css("tbody tr")).to be_empty
        expect(response.body).to include("Nothing matches")
      end

      # Only a query has a series of its own stored, so only a query gets a
      # sparkline and only a query opens.
      it "gives a query a trend and a way in, and a page a way to its traffic" do
        stored!

        get "/telemetry/search_console_report"
        expect(document.at_css("tbody tr .sc-spark")).to be_present
        expect(document.at_css("tbody tr a[data-action*='modal#open']")).to be_present

        get "/telemetry/search_console_report", params: { tab: "pages" }
        expect(document.at_css("tbody tr .sc-spark")).to be_nil
        expect(document.at_css("tbody tr a[data-action*='modal#open']")).to be_nil
        expect(document.at_css("tbody tr a.seo-link")["href"]).to start_with("/telemetry")
      end

      it "leaves the trend off a query that got no clicks" do
        stored!
        AhoyDashboard::SearchConsoleKeyword.absorb([
          { date: now.to_date - 1, query: "never clicked", clicks: 0, impressions: 90, ctr: 0.0, position: 30.0 },
          { date: now.to_date - 2, query: "never clicked", clicks: 0, impressions: 80, ctr: 0.0, position: 31.0 }
        ])

        get "/telemetry/search_console_report"
        row = document.css("tbody tr").find { |node| node.at_css(".seo-label[title='never clicked']") }

        expect(row.at_css(".sc-spark")).to be_nil
      end
    end

    it "carries the range, the measure and the tab through every link it builds" do
      stored!

      get "/telemetry/search_console_report", params: { period: "7d", measure: "ctr", tab: "pages" }
      tabs = document.css('nav[aria-label="Which rows to list"] a').map { |node| node["href"] }

      expect(tabs).to all(include("period=7d"))
      expect(tabs.last).to include("measure=ctr")
    end

    it "falls back rather than erroring on nonsense in the query string" do
      stored!

      [ { period: "banana" }, { measure: "vibes" }, { tab: "banana" }, { q: "%" }, { period: "custom" } ].each do |params|
        get "/telemetry/search_console_report", params: params

        expect(response).to have_http_status(:ok), "expected #{params.inspect} to still render"
      end
    end
  end

  describe "one keyword, in its dialog" do
    before { sign_in create(:user, :admin) }

    it "serves the frame rather than the page when the dialog asks" do
      stored!

      get "/telemetry/search_console_keyword",
          params: { q: "federal prison consultant", view: "details" }

      expect(response).to have_http_status(:ok)
      expect(document.at_css("tm-frame##{AhoyDashboard::SearchConsoleKeywordPresenter::DETAILS_FRAME}")).to be_present
      expect(document.at_css("#tm-modal-keyword-title").text.strip).to eq("federal prison consultant")
      expect(document.at_css("#tm-modal-keyword-title + p").text).not_to include("ahoy_dashboard")
    end

    it "still serves the whole page without it" do
      stored!

      get "/telemetry/search_console_keyword", params: { q: "federal prison consultant" }

      expect(response).to have_http_status(:ok)
      expect(document.at_css("#tm-modal-keyword-title")).to be_nil
    end

    it "lists the landing pages and what each took of them" do
      stored!

      get "/telemetry/search_console_keyword",
          params: { q: "federal prison consultant", view: "details" }
      shares = document.css("tbody tr").map { |row| row.css("td.num")[1].text.strip }

      expect(document.at_css(".kw-heading").text.strip).to eq("Landing pages")
      expect(shares).to eq([ "75.0%", "25.0%" ])
    end

    it "draws the sparkline off the days it was actually pulled for" do
      stored!(days: 4)

      get "/telemetry/search_console_keyword",
          params: { q: "federal prison consultant", view: "details" }
      values = JSON.parse(document.at_css(".kw-spark svg|svg", "svg" => "http://www.w3.org/2000/svg")["data-dash--spark-values-value"])

      expect(values.size).to eq(4)
    end
  end
end

RSpec.describe "Dashboard Search Console report by device and country", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }
  let(:day) { now.to_date - 5 }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def document
    Nokogiri::HTML5(response.body)
  end

  def tile(label)
    document.css("nav[aria-label='Which measure the chart draws'] a")
      .map { |node| node.text.split.join(" ") }
      .find { |text| text.start_with?(label) }
  end

  def menu_links(id)
    document.css("##{id} a")
  end

  def row_labels
    document.css("tbody tr .sc-label").map { |cell| cell.text.strip }
  end

  def slice!(device, country, clicks:, query:)
    AhoyDashboard::SearchConsoleTotal.absorb([
      { date: day, device: device, country: country, clicks: clicks, impressions: clicks * 10, ctr: 0.1, position: 4.0 }
    ])
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: day, query: query, device: device, country: country, clicks: clicks, impressions: clicks * 10,
        ctr: 0.1, position: 4.0 }
    ])
  end

  def stored!
    slice!("desktop", "usa", clicks: 40, query: "desk search")
    slice!("mobile", "usa", clicks: 25, query: "phone search")
    slice!("mobile", "can", clicks: 5, query: "canada phone search")
    slice!("", "", clicks: 7, query: "old search")
  end

  it "offers every device and the countries with rows in the range, by name" do
    stored!

    get "/telemetry/search_console_report"

    expect(menu_links("tm-sc-device").map { |link| link.text.strip })
      .to eq([ "All devices", "Desktop", "Mobile", "Tablet" ])
    expect(menu_links("tm-sc-country").map { |link| link.text.strip })
      .to eq([ "All countries", "United States", "Canada" ])
  end

  it "counts rows stored before device and country under all of them" do
    stored!

    get "/telemetry/search_console_report"

    expect(tile("Clicks")).to start_with("Clicks 77")
    expect(row_labels).to include("old search", "desk search", "phone search")
  end

  it "narrows the tiles and the rows to one device and leaves the old rows out" do
    stored!

    get "/telemetry/search_console_report", params: { device: "mobile" }

    expect(tile("Clicks")).to start_with("Clicks 30")
    expect(row_labels).to contain_exactly("phone search", "canada phone search")
    expect(document.text).to include("Days stored before device and country were pulled have neither")
  end

  it "narrows to one device in one country" do
    stored!

    get "/telemetry/search_console_report", params: { device: "mobile", country: "can" }

    expect(tile("Clicks")).to start_with("Clicks 5")
    expect(row_labels).to eq([ "canada phone search" ])
    expect(document.text).to include("Showing Mobile in Canada only.")
  end

  it "ignores a device it does not know" do
    stored!

    get "/telemetry/search_console_report", params: { device: "phone" }

    expect(tile("Clicks")).to start_with("Clicks 77")
    expect(menu_links("tm-sc-device").find { |link| link["aria-current"] == "true" }.text.strip).to eq("All devices")
  end

  it "carries the device and country on every link it builds" do
    stored!

    get "/telemetry/search_console_report", params: { device: "mobile", country: "usa" }

    hrefs = [
      *document.css("nav[aria-label='Which measure the chart draws'] a"),
      *menu_links("sc-period"),
      *document.css("tbody tr td:first-child a")
    ].map { |link| Rack::Utils.parse_query(URI(link["href"]).query) }

    expect(hrefs).not_to be_empty
    expect(hrefs).to all(include("device" => "mobile", "country" => "usa"))

    form = document.at_css("form[role='search']")
    expect(form.at_css("input[name='device']")["value"]).to eq("mobile")
    expect(form.at_css("input[name='country']")["value"]).to eq("usa")
  end

  it "switches one menu and keeps the other" do
    stored!

    get "/telemetry/search_console_report", params: { device: "mobile" }
    canada = menu_links("tm-sc-country").find { |link| link.text.strip == "Canada" }

    expect(Rack::Utils.parse_query(URI(canada["href"]).query)).to include("device" => "mobile", "country" => "can")
  end

  it "says a picked device has nothing yet rather than calling the days unstored" do
    slice!("", "", clicks: 7, query: "old search")

    get "/telemetry/search_console_report", params: { device: "tablet" }

    expect(response.body).to include("Nothing in this range for Tablet.")
    expect(response.body).not_to include("Nothing stored for these dates")
    reset = document.css("a").find { |link| link.text.strip == "Show all devices and countries" }
    expect(Rack::Utils.parse_query(URI(reset["href"]).query)).not_to include("device")
  end
end
