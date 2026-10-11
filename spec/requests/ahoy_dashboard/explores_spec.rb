require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard explore", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def page_at(path, visitor:, **attributes)
    visit = dash_visit(started_at: now - 1.day, visitor: visitor, **attributes)
    dash_page_view(visit, path: path, at: now - 1.day)
    visit
  end

  def explore(params = {})
    get "/telemetry/explore", params: params
    Nokogiri::HTML5(response.body)
  end

  def labels(document)
    document.css("tbody th").map { |cell| cell.text.strip }
  end

  def headings(document)
    document.css("thead th").map { |cell| cell.text.strip }
  end

  describe "the gate" do
    it "sends a stranger to sign in" do
      sign_out :user

      get "/telemetry/explore"

      expect(response).to redirect_to(Rails.application.routes.url_helpers.new_user_session_path)
    end

    it "404s somebody signed in without the flag" do
      sign_out :user
      sign_in create(:user)

      get "/telemetry/explore"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the question" do
    before do
      page_at("/going-in", visitor: "one", country: "US")
      page_at("/for-families", visitor: "two", country: "CA")
    end

    it "opens on visitors by page" do
      document = explore

      expect(response).to have_http_status(:ok)
      expect(labels(document)).to contain_exactly("/going-in", "/for-families")
      expect(headings(document).first).to eq("Page")
    end

    it "groups by whichever dimension the url names" do
      document = explore(dimension: "country")

      expect(labels(document)).to contain_exactly(a_string_including("United States"),
                                                  a_string_including("Canada"))
      expect(headings(document).first).to eq("Country")
    end

    it "falls back to the default dimension rather than raising on a nonsense one" do
      document = explore(dimension: "not-a-dimension")

      expect(response).to have_http_status(:ok)
      expect(headings(document).first).to eq("Page")
    end

    it "reads a custom property as a dimension" do
      visit = dash_visit(started_at: now - 1.day)
      dash_goal(visit, "site_searched", facility_id: "12")
      AhoyDashboard::Property.create!(key: "facility_id", position: 1)

      expect(labels(explore(dimension: "prop:facility_id"))).to eq([ "12" ])
    end

    it "answers the goal dimension out of the goals table" do
      create(:dash_goal, event_name: "consult_requested", display_name: "Consult requested")
      visit = dash_visit(started_at: now - 1.day)
      dash_goal(visit, "consult_requested")

      document = explore(dimension: "goal")

      expect(labels(document)).to include("Consult requested")
      expect(headings(document)).to include("Conversion rate")
    end
  end

  describe "the columns" do
    before { page_at("/going-in", visitor: "one") }

    it "prints what was asked for" do
      expect(headings(explore(columns: "visitors,bounce_rate"))).to eq(
        [ "Page", "Unique visitors", "Bounce rate" ]
      )
    end

    # The engagement event carries a path and nothing else, so grouping it by any
    # other event property returns nothing and the column would read as nobody
    # scrolled. exit_page reads a column off a join that carries no events.
    it "drops a metric the dimension cannot answer rather than printing zero" do
      expect(headings(explore(dimension: "controller", columns: "visitors,scroll_depth"))).to eq(
        [ "Rails controller", "Unique visitors" ]
      )
      expect(headings(explore(dimension: "exit_page", columns: "visitors,engagement_time"))).to eq(
        [ "Exit page", "Unique visitors" ]
      )
    end

    # A visit dimension can: the engagement event belongs to a visit and the
    # visit knows where it came from.
    it "keeps scroll depth on a dimension that can answer it" do
      expect(headings(explore(dimension: "country", columns: "visitors,scroll_depth"))).to eq(
        [ "Country", "Unique visitors", "Scroll depth" ]
      )
    end

    it "leads with the charted metric, so the bars and the chart agree" do
      expect(headings(explore(metric: "pageviews", columns: "bounce_rate"))).to eq(
        [ "Page", "Total pageviews", "Bounce rate" ]
      )
    end

    it "keeps the last column rather than letting the table have none" do
      document = explore(columns: "")

      expect(headings(document).size).to be > 1
    end
  end

  describe "on a phone" do
    before { page_at("/going-in", visitor: "one") }

    def narrow(document)
      document.css("thead th[data-narrow]").map { |cell| [ cell.text.strip, cell["data-narrow"] ] }
    end

    it "keeps the label and the first number and folds the rest away until the columns are chosen" do
      expect(narrow(explore)).to eq(
        [ [ "Unique visitors", "shown" ], [ "Total pageviews", "hidden" ], [ "Bounce rate", "hidden" ] ]
      )
    end

    it "shows every column somebody asked for by name" do
      expect(narrow(explore(columns: "visitors,pageviews,bounce_rate"))).to eq(
        [ [ "Unique visitors", "shown" ], [ "Total pageviews", "shown" ], [ "Bounce rate", "shown" ] ]
      )
    end

    it "wraps the table in a region a keyboard can scroll sideways" do
      region = explore.at_css("[role=region] > table")&.parent

      expect(region).to be_present
      expect(region["tabindex"]).to eq("0")
      expect(region["aria-label"]).to include("scrolls sideways")
    end
  end

  describe "the dimension menu" do
    before { page_at("/going-in", visitor: "one") }

    it "lists every dimension once, under its own group heading" do
      panel = explore.at_css("#tm-ask-dimension")
      groups = panel.css("[role=group]")
      hrefs = panel.css("a").map { |link| link["href"] }

      expect(groups.map { |group| panel.at_css("##{group['aria-labelledby']}").text.strip })
        .to start_with(*AhoyDashboard::Dimension::GROUPS)
      expect(hrefs.uniq.size).to eq(hrefs.size)
      expect(hrefs.count { |href| href.include?("dimension=goal") }).to eq(1)
      expect(groups.flat_map { |group| group.css("a").map { |link| link.text.squish } }).to include("Country", "Goal")
    end

    it "lists Goal once with goals defined and a property saved under its name" do
      create(:dash_goal, event_name: "consult_requested", display_name: "Consult requested")
      AhoyDashboard::Property.new(key: "goal", label: "Goal").save(validate: false)
      AhoyDashboard::Property.new(key: "Goal").save(validate: false)

      panel = explore.at_css("#tm-ask-dimension")
      texts = panel.css("a").map { |link| link.text.squish }

      expect(texts.count("Goal")).to eq(1)
      expect(panel.css("a").count { |link| link["href"].include?("dimension=goal") }).to eq(1)
    end

    it "lists a custom property under the behaviour heading, and a property already saved under a built in name only once" do
      AhoyDashboard::Property.create!(key: "facility_id", label: "Facility")
      AhoyDashboard::Property.new(key: "format", label: "Format").save(validate: false)

      panel = explore.at_css("#tm-ask-dimension")
      behaviour = panel.css("[role=group]").find { |group| panel.at_css("##{group['aria-labelledby']}").text.strip == "Behaviour" }
      hrefs = panel.css("a").map { |link| link["href"] }

      expect(behaviour.css("a").map { |link| link.text.squish }).to include("facility_id", "Page format")
      expect(hrefs.count { |href| href.include?("dimension=format") }).to eq(1)
      expect(hrefs.none? { |href| href.include?("prop%3Aformat") }).to be(true)
    end
  end

  describe "the pager" do
    it "states the total once there is more than a page of rows" do
      52.times { |index| page_at("/page-#{index}", visitor: "visitor-#{index}") }

      first = explore
      second = explore(page: 2)

      expect(first.at_css(".pager-status").text.squish).to eq("1 to 50 of 52")
      expect(second.at_css(".pager-status").text.squish).to eq("51 to 52 of 52")
    end

    it "states the total when everything fits on the page" do
      page_at("/going-in", visitor: "one")
      page_at("/for-families", visitor: "two")

      expect(explore.at_css(".pager-status").text.squish).to eq("1 to 2 of 2")
    end
  end

  describe "finding a row" do
    before do
      page_at("/going-in", visitor: "one")
      page_at("/for-families", visitor: "two")
    end

    it "narrows which rows are listed" do
      expect(labels(explore(q: "families"))).to eq([ "/for-families" ])
    end

    it "treats a blank term as no search" do
      expect(labels(explore(q: "   "))).to contain_exactly("/going-in", "/for-families")
    end

    it "says so when nothing matches" do
      expect(explore(q: "nothing like this").text).to include("Nothing matches that")
    end
  end

  describe "narrowing the question" do
    before do
      page_at("/going-in", visitor: "one", country: "US")
      page_at("/for-families", visitor: "two", country: "CA")
    end

    it "applies a filter that arrived in the url" do
      document = explore(filters: [ { dimension: "country", operator: "is", value: "US" } ])

      expect(labels(document)).to eq([ "/going-in" ])
    end

    # A row on a card throws you back to the dashboard. A row here is part of the
    # question, so it has to come back to the same question.
    it "keeps the question in every row's link" do
      link = explore(dimension: "country", metric: "pageviews").at_css("tbody th a")["href"]

      expect(link).to start_with("/telemetry/explore")
      expect(link).to include("dimension=country")
      expect(link).to include("metric=pageviews")
      expect(link).to include("filters")
    end
  end

  describe "the date range" do
    before { page_at("/going-in", visitor: "one") }

    # "Custom range" is the name of the menu item somebody picked, not the window
    # they are looking at, and on a range dragged off the dashboard chart that
    # window is the one thing on the page nothing else prints.
    it "says which window a custom range is, rather than that it is custom" do
      document = explore(period: "custom", from: "2026-08-10T01:11", to: "2026-08-10T01:29")

      expect(document.at_css("#tm-ask-period-button").text.strip).to eq("Aug 10, 1:11 AM to 1:29 AM")
    end

    it "offers the window back as fields somebody can change" do
      document = explore(period: "custom", from: "2026-08-10T01:11", to: "2026-08-10T01:29")
      values = %w[#tm-range-from #tm-range-from-time #tm-range-to #tm-range-to-time]
        .map { |id| document.at_css(id)["value"] }

      expect(values).to eq(%w[2026-08-10 01:11 2026-08-10 01:29])
    end

    it "keeps whole days as days rather than inventing a time on them" do
      document = explore(period: "custom", from: "2026-08-01", to: "2026-08-10")
      from = document.at_css("#tm-range-from")

      expect(from["type"]).to eq("date")
      expect(from["value"]).to eq("2026-08-01")
      expect(document.at_css("#tm-range-from-time")["value"]).to be_nil
      expect(document.at_css("#tm-range-to")["value"]).to eq("2026-08-10")
    end

    it "carries the breakdown through applying a range, so the question survives it" do
      document = explore(period: "custom", from: "2026-08-01", to: "2026-08-10",
                         dimension: "country", columns: "visitors,visits")
      form = document.at_css("form[aria-label='Custom date range']")
      carried = form.css("input[type=hidden]").map { |field| [ field["name"], field["value"] ] }.to_h

      expect(form["action"]).to eq("/telemetry/explore")
      expect(carried).to include("dimension" => "country", "columns" => "visitors,visits", "period" => "custom")
    end

    it "has no range fields on a named period" do
      expect(explore(period: "7d").at_css("#tm-range-from")).to be_nil
    end
  end

  describe "the filter chips" do
    before { page_at("/going-in", visitor: "one", country: "US") }

    def chips(document)
      document.css(".ex-ask .chip")
    end

    # The whole sentence used to go in the value slot, where a 200px clamp cut it
    # mid URL: "Entry URL is https://exampl...". The parts are separate now, the
    # same way the dashboard bar says them.
    it "says the dimension, how it is matched and the value apart from each other" do
      chip = chips(explore(filters: [ { dimension: "country", operator: "is_not", value: "US" } ])).first

      expect(chip.at_css(".cd").text.strip).to eq("Country")
      expect(chip.at_css(".cis").text.strip).to eq("is not")
      expect(chip.at_css(".cv").text.strip).to eq("US")
    end

    it "carries the whole value in a title, because the value itself is clamped" do
      long = "https://example.com/#{'a' * 120}"
      chip = chips(explore(filters: [ { dimension: "entry_url", operator: "is", value: long } ])).first

      expect(chip.at_css(".cv")["title"]).to eq(long)
    end

    it "reopens the form that made it" do
      chip = chips(explore(filters: [ { dimension: "country", operator: "is", value: "US" } ])).first
      link = chip.at_css(".cv")

      expect(link["href"]).to include("category=location", "edit=0", "return=explore")
    end

    it "takes one filter off without touching the rest" do
      document = explore(filters: [
        { dimension: "country", operator: "is", value: "US" },
        { dimension: "os", operator: "is", value: "Mac" }
      ])
      href = chips(document).first.at_css(".cx")["href"]

      expect(href).to include("Mac")
      expect(href).not_to include("country")
    end

    it "offers one way off the whole list" do
      document = explore(filters: [ { dimension: "country", operator: "is", value: "US" } ])
      clear = document.css(".ex-ask__views a").find { |link| link.text.strip == "Clear filters" }

      expect(clear["href"]).to start_with("/telemetry/explore")
      expect(clear["href"]).not_to include("filters")
    end

    it "offers no way off a list that is empty" do
      expect(explore.text).not_to include("Clear filters")
    end

    it "shows a group as one cluster and keeps the question when a member comes off" do
      document = explore(dimension: "browser", filters: [
        { dimension: "country", operator: "is", value: "US", group: 0 },
        { dimension: "country", operator: "is", value: "CA", group: 0 }
      ])
      cluster = document.at_css(".ex-ask [role=group][aria-label='Country is US or CA']")
      remove = cluster.at_css("a[aria-label='Remove the filter Country is US']")["href"]

      expect(remove).to start_with("/telemetry/explore")
      expect(Rack::Utils.parse_nested_query(URI.parse(remove).query)).to include(
        "dimension" => "browser",
        "filters" => [ { "dimension" => "country", "operator" => "is", "value" => "CA" } ]
      )
    end

    it "sends another option for a group back to the same question" do
      document = explore(dimension: "browser", filters: [ { dimension: "country", operator: "is", value: "US" } ])
      href = document.at_css(".ex-ask a[aria-label='Add another option to Country is US']")["href"]

      expect(Rack::Utils.parse_nested_query(URI.parse(href).query))
        .to include("return" => "explore", "for_dimension" => "browser", "dimension" => "country")
    end
  end

  describe "the shell" do
    it "wears the dashboard's layout rather than the settings one" do
      document = explore

      expect(document.css(".set-wrap")).to be_empty
      expect(document.css(".set-nav")).to be_empty
      expect(document.at_css("header .search-btn")).to be_present
    end

    it "marks its own header link as the page somebody is on" do
      expect(explore.at_css("header .hd-nav[aria-current=page]").text.strip).to eq("Explore")
    end

    it "is linked from the dashboard header, carrying the view" do
      get "/telemetry", params: { period: "day" }
      link = Nokogiri::HTML5(response.body).css("header .hd-nav").find { |node| node.text.strip == "Explore" }

      expect(link["href"]).to start_with("/telemetry/explore")
      expect(link["href"]).to include("period=day")
      expect(link["aria-current"]).to be_nil
    end

    it "marks no header tab as current on a settings page" do
      get "/telemetry/settings/goals"

      expect(Nokogiri::HTML5(response.body).at_css("header .hd-nav[aria-current=page]")).to be_nil
    end
  end

  describe "the view cookie" do
    it "is never written, because a question is not the dashboard's remembered view" do
      get "/telemetry/explore", params: { period: "day" }

      expect(response.cookies["dash_view"]).to be_nil
    end
  end

  describe "the csv" do
    before do
      page_at("/going-in", visitor: "one")
      page_at("/for-families", visitor: "two")
    end

    it "downloads the grouping on screen" do
      get "/telemetry/explore.csv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("ahoy-dashboard-explore-page-")
      expect(response.body).to include("Page", "/going-in", "/for-families")
    end

    it "honours the find term, because the term is in the url it was built from" do
      get "/telemetry/explore.csv", params: { q: "families" }

      expect(response.body).to include("/for-families")
      expect(response.body).not_to include("/going-in")
    end

    it "exports every matching row even when the current page is the second page" do
      paths = 52.times.map { |index| "/matching-#{index}" }
      paths.each_with_index { |path, index| page_at(path, visitor: "match-#{index}", country: "US") }
      page_at("/matching-excluded", visitor: "excluded", country: "CA")

      get("/telemetry/explore.csv", params: { page: 2, q: "matching", columns: "visitors",
        filters: [{ dimension: "country", operator: "is", value: "US" }] })

      expect(CSV.parse(response.body, headers: true).map { |row| row[0] }).to match_array(paths)
    end

    it "exports all matching goals without the screen's page limit or offset" do
      names = 52.times.map { |index| "Matching goal #{index}" }
      names.each_with_index do |name, index|
        create(:dash_goal, event_name: "matching-#{index}", display_name: name)
      end
      create(:dash_goal, event_name: "excluded", display_name: "Excluded goal")

      get("/telemetry/explore.csv", params: { dimension: "goal", page: 2, q: "matching" })

      expect(CSV.parse(response.body, headers: true).map { |row| row[0] }).to match_array(names)
    end

    it "downloads a goal breakdown narrowed by the find term" do
      create(:dash_goal, event_name: "consult_requested", display_name: "Consult requested")
      create(:dash_goal, event_name: "alert_signup", display_name: "Alert signup")
      visit = page_at("/pricing", visitor: "three")
      dash_goal(visit, "consult_requested", at: now - 1.day)
      dash_goal(visit, "alert_signup", at: now - 1.day)

      get "/telemetry/explore.csv", params: { dimension: "goal", q: "consult" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Consult requested")
      expect(response.body).not_to include("Alert signup")
    end
  end

  describe "getting here from a card" do
    it "hands the details modal's grouping over" do
      page_at("/going-in", visitor: "one")

      get "/telemetry/reports/sources", params: { view: "details", tab: "channels" }
      link = Nokogiri::HTML5(response.body).css("a").find { |a| a.text.include?("Open in Explore") }

      expect(link["href"]).to include("/telemetry/explore")
      expect(link["href"]).to include("dimension=channel")
    end
  end
end
