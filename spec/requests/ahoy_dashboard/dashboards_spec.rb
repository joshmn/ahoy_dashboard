require "rails_helper"

RSpec.describe "Dashboard dashboard", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    first = dash_visit(started_at: now - 2.days, visitor: "a", country: "US",
                            referring_domain: "google.com", browser: "Chrome")
    dash_page_view(first, path: "/going-in/faq", at: now - 2.days)
    dash_page_view(first, path: "/resources", at: now - 2.days + 3.minutes)
    dash_goal(first, "site_searched", at: now - 2.days + 4.minutes, query: "thomson")

    second = dash_visit(started_at: now - 1.day, visitor: "b", country: "CA",
                             referring_domain: nil, browser: "Safari")
    dash_page_view(second, path: "/going-in/faq", at: now - 1.day)
  end

  describe "gating" do
    it "lets an admin in" do
      sign_in create(:user, :admin)

      get "/telemetry"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "renders with nothing recorded at all" do
      get "/telemetry?loading=complete"

      expect(response).to have_http_status(:ok)
      expect(document.at_css("[role=group][aria-label=Metrics]")).to be_present
    end

    it "renders the strip, the chart and a frame per card" do
      traffic!

      get "/telemetry?loading=complete"

      expect(response).to have_http_status(:ok)
      AhoyDashboard::Metric::ALL.each do |metric|
        expect(response.body).to include(metric.label), "expected the #{metric.key} tile"
      end
      (AhoyDashboard::Report::CARD_ORDER - [ AhoyDashboard::Report::BEHAVIOURS ]).each do |key|
        expect(response.body).to include("report_#{key}"), "expected a frame for the #{key} card"
      end
    end

    it "draws goals under the journey rather than as a card in the grid" do
      traffic!

      get "/telemetry"
      body = response.body
      frame = Nokogiri::HTML5(body).at_css("tm-frame##{AhoyDashboard::GoalConversionsPresenter::FRAME}")

      expect(frame).to be_present
      expect(frame["src"]).to start_with("/telemetry/goal_conversions")
      expect(frame["loading"]).to eq("lazy")
      expect(body).not_to include("report_#{AhoyDashboard::Report::BEHAVIOURS}")
      expect(body.index(AhoyDashboard::GoalConversionsPresenter::FRAME)).to be > body.index("dash_journey")
    end

    it "renders a frame and a dialog for each configured funnel" do
      funnel = create(:dash_funnel, name: "Reached the consult")

      get "/telemetry"

      expect(response.body).to include(AhoyDashboard::FunnelPresenter.frame_id(funnel))
      expect(response.body).to include(AhoyDashboard::FunnelPresenter.details_frame_id(funnel))
      expect(response.body).to include("tm-modal-#{AhoyDashboard::FunnelPresenter.modal_key(funnel)}")
      expect(response.body).to include("Reached the consult")
    end

    it "loads the funnel card when it approaches the viewport" do
      funnel = create(:dash_funnel)

      get "/telemetry"

      frame = document.at_css("tm-frame##{AhoyDashboard::FunnelPresenter.frame_id(funnel)}")

      expect(frame["src"]).to start_with("/telemetry/funnels/#{funnel.id}")
      expect(frame["loading"]).to eq("lazy")
    end

    it "preloads funnel steps in one batch before rendering every card" do
      goals = create_list(:dash_goal, 4)
      funnels = (2..4).map { |size| create(:dash_funnel, goals: goals.first(size)) }
      statements = captured_sql(%(FROM "ahoy_dashboard_funnel_steps")) { get "/telemetry?loading=complete" }

      expect(response).to have_http_status(:ok)
      expect(statements.size).to eq(1)
      expect(statements.first).to include(%(WHERE "ahoy_dashboard_funnel_steps"."funnel_id" IN))
      document = Nokogiri::HTML5(response.body)
      completed = funnels.map do |funnel|
        frame = document.at_css("tm-frame##{AhoyDashboard::FunnelPresenter.frame_id(funnel)}")
        frame.key?("complete") && frame.css(".placeholder").empty?
      end
      expect(completed).to eq([ true, true, true ])
    end

    it "renders with no funnels configured" do
      get "/telemetry"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("report_funnel_")
    end

    it "keeps itself out of the index" do
      get "/telemetry"

      expect(response.body).to match(/noindex/)
    end

    it "renders every period without falling over" do
      traffic!

      AhoyDashboard::Period::ALL.each do |period|
        get "/telemetry", params: { period: period.key, from: "2026-07-01", to: "2026-07-31" }

        expect(response).to have_http_status(:ok), "expected the #{period.key} period to render"
      end
    end

    it "renders every metric as the charted one" do
      traffic!

      AhoyDashboard::Metric::ALL.each do |metric|
        get "/telemetry", params: { metric: metric.key }

        expect(response).to have_http_status(:ok), "expected the #{metric.key} chart to render"
      end
    end

    it "renders both comparison modes" do
      traffic!

      %w[previous_period year_over_year].each do |mode|
        get "/telemetry", params: { period: "7d", comparison: mode }

        expect(response).to have_http_status(:ok), "expected the #{mode} comparison to render"
      end
    end

    it "renders with a filter applied" do
      traffic!

      get "/telemetry", params: { filters: [ { dimension: "page", operator: "is", value: "/going-in/faq" } ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/going-in/faq")
    end

    it "renders with crawlers switched on" do
      traffic!
      bot = dash_visit(started_at: now - 1.day, visitor: "bot")
      dash_page_view(bot, path: "/crawled-only", at: now - 1.day, crawler: "Googlebot")

      get "/telemetry", params: { loading: "complete" }
      expect(document.at_css("#report_pages").text).not_to include("/crawled-only")

      get "/telemetry", params: { crawlers: "1" }

      expect(response).to have_http_status(:ok)
      open_palette
      expect(response.body).to include("Hide crawlers")

      get "/telemetry", params: { crawlers: "1", loading: "complete" }
      expect(document.at_css("#report_pages").text).to include("/crawled-only")
    end

    it "falls back rather than erroring on nonsense in the query string" do
      traffic!

      [
        { period: "banana" },
        { metric: "vibes" },
        { interval: "fortnight" },
        { period: "day", interval: "month" },
        { comparison: "lol" },
        { period: "custom", from: "yesterday", to: "tomorrow" },
        { period: "custom" },
        { crawlers: "maybe" },
        { filters: "banana" },
        { filters: [ { dimension: "hairstyle", operator: "is", value: "mullet" } ] },
        { filters: [ { dimension: "page", operator: "sounds_like", value: "/x" } ] },
        { filters: [ { dimension: "prop:x'); drop table ahoy_events; --", operator: "is", value: "1" } ] },
        { page: "-4" }
      ].each do |params|
        get "/telemetry", params: params

        expect(response).to have_http_status(:ok), "expected #{params.inspect} to still render"
      end

      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end
  end

  describe "picking a range off the chart" do
    before { sign_in create(:user, :admin) }

    def chart_selection(body = response.body)
      dash_chart_plugin("tmSelect", dash_chart(body))
    end

    it "hands the chart a custom range link that keeps the rest of the view" do
      get "/telemetry?loading=complete", params: {
        period: "30d", interval: "week", metric: "pageviews", comparison: "previous_period",
        filters: [ { dimension: "page", operator: "is", value: "/going-in/faq" } ]
      }

      selection = chart_selection
      link = URI.parse(selection["url"])
      params = Rack::Utils.parse_nested_query(link.query)

      expect(link.path).to eq("/telemetry/dashboard")
      expect(params).to include("period" => "custom", "metric" => "pageviews", "comparison" => "previous_period")
      expect(params["filters"]).to eq([ { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq" } ])
      expect(params.keys).not_to include("from", "to", "interval")
      expect(selection).to include("from" => "2026-07-13", "to" => "2026-08-11")
    end

    it "lands on the range the chart asks for" do
      traffic!
      get "/telemetry?loading=complete", params: { period: "30d", metric: "pageviews" }

      link = URI.parse(chart_selection["url"])
      params = Rack::Utils.parse_nested_query(link.query).merge("from" => "2026-08-01", "to" => "2026-08-05")
      get link.path, params: params.merge(loading: "complete")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aug 1 to Aug 5")
      expect(chart_selection).to include("from" => "2026-08-01", "to" => "2026-08-05")
    end

    it "offers a range to pick on a single day and on realtime" do
      %w[day yesterday realtime].each do |period|
        get "/telemetry?loading=complete", params: { period: period }

        expect(chart_selection).to be_present, "expected range picking on #{period}"
      end
    end

    it "lands on the times a drag across a single day asks for, grouped as finely as fits" do
      traffic!
      get "/telemetry?loading=complete", params: { period: "yesterday" }

      link = URI.parse(chart_selection["url"])
      params = Rack::Utils.parse_nested_query(link.query).merge("from" => "2026-08-10T09:00", "to" => "2026-08-10T16:00")
      get link.path, params: params.merge(loading: "complete")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aug 10, 9 AM to 4 PM")
      expect(dash_chart_points.size).to eq(84)
      expect(dash_chart_points.first.first).to start_with("2026-08-10T09:00")
      expect(dash_chart_points.last.first).to start_with("2026-08-10T15:55")
    end

    it "keeps drilling down to the minute" do
      traffic!
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-10T09:00", to: "2026-08-10T10:00" }

      expect(response).to have_http_status(:ok)
      expect(dash_chart_points.size).to eq(60)
      expect(chart_selection).to be_present
    end

    it "offers a dragged window back at the minute rather than rounded to the day" do
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-10T09:00", to: "2026-08-10T16:00" }
      document = Nokogiri::HTML5(response.body)

      expect(document.at_css("#tm-range-from")["value"]).to eq("2026-08-10")
      expect(document.at_css("#tm-range-from-time")["value"]).to eq("09:00")
      expect(document.at_css("#tm-range-to")["value"]).to eq("2026-08-10")
      expect(document.at_css("#tm-range-to-time")["value"]).to eq("16:00")
    end

    it "puts a dragged window back exactly as it was handed in" do
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-10T09:00", to: "2026-08-10T16:00" }
      document = Nokogiri::HTML5(response.body)

      get "/telemetry?loading=complete", params: {
        period: "custom",
        from: document.at_css("#tm-range-from")["value"], from_time: document.at_css("#tm-range-from-time")["value"],
        to: document.at_css("#tm-range-to")["value"], to_time: document.at_css("#tm-range-to-time")["value"]
      }

      expect(response.body).to include("Aug 10, 9 AM to 4 PM")
    end

    it "keeps whole days whole, rather than putting a time on them" do
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-01", to: "2026-08-05" }
      document = Nokogiri::HTML5(response.body)

      expect(document.at_css("#tm-range-from")["type"]).to eq("date")
      expect(document.at_css("#tm-range-from-time")["value"]).to be_nil
      expect(document.at_css("#tm-range-to")["value"]).to eq("2026-08-05")
      expect(document.at_css("#tm-range-to-time")["value"]).to be_nil
    end

    it "takes a time on either end of a range typed by hand" do
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-10", from_time: "08:30", to: "2026-08-10", to_time: "17:00" }

      expect(response.body).to include("Aug 10, 8:30 AM to 5 PM")
      expect(response.body).to include("from=2026-08-10T08%3A30")
    end

    it "reads a blank time as the whole day, and ignores one that is not a time" do
      get "/telemetry?loading=complete", params: { period: "custom", from: "2026-08-01", from_time: "", to: "2026-08-05", to_time: "noon" }

      expect(response.body).to include("Aug 1 to Aug 5")
    end

    it "keeps the link on the metric a switch moves to" do
      get "/telemetry/dashboard.json", params: { period: "7d", metric: "visits" }

      url = JSON.parse(response.body).dig("options", "library", "plugins", "tmSelect", "url")

      expect(link_query(url)).to include("metric" => "visits", "period" => "custom")
    end

    it "leaves the explore chart alone, since its link would drop the question" do
      traffic!

      get "/telemetry/explore"

      expect(response).to have_http_status(:ok)
      expect(chart_selection).to be_nil
    end
  end

  describe "the json format" do
    before { sign_in create(:user, :admin) }

    it "returns the stats and the series the metric switcher swaps in" do
      traffic!

      get "/telemetry/dashboard.json", params: { period: "7d", metric: "visitors" }

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)

      expect(payload).to have_key("stats")
      expect(payload).to have_key("series")
      expect(payload["stats"]).to be_an(Array)
      expect(payload["stats"].size).to eq(AhoyDashboard::Metric::ALL.size)
    end

    it "returns json against an empty database" do
      get "/telemetry/dashboard.json"

      expect(response).to have_http_status(:ok)
      expect { JSON.parse(response.body) }.not_to raise_error
    end
  end

  describe "keeping itself out of its own data" do
    before { sign_in create(:user, admin: true) }

    it "records no visit and no event for any of its own entry points" do
      paths = [
        "/telemetry",
        "/telemetry/reports/pages",
        "/telemetry/dashboard.json",
        "/telemetry/realtime.json"
      ]

      visits = Ahoy::Visit.count
      events = Ahoy::Event.count

      paths.each { |path| get path }

      expect(Ahoy::Visit.count).to eq(visits)
      expect(Ahoy::Event.count).to eq(events)
    end

    it "serves its own front end rather than the host's" do
      get "/telemetry"

      sources = response.body.scan(/<script[^>]*src="([^"]+)"/).flatten

      expect(sources).to contain_exactly(a_string_starting_with("/telemetry/assets/"))
      expect(response.body).to include(%(type="module"))
      expect(response.body).not_to include("importmap")
    end

    it "loads no tracking script of its own" do
      get "/telemetry"

      sources = response.body.scan(/<script[^>]*src="([^"]+)"/).flatten
      outside = sources.reject { |src| src.start_with?("/telemetry/assets/") }

      expect(outside).to be_empty
      expect(sources.grep(%r{/(mom|ahoy|ahoy\.min)\.js})).to be_empty
      expect(response.body).not_to include("ahoy.js")
    end
  end

  describe "a group of filters any one of which is enough" do
    before { sign_in create(:user, :admin) }

    let(:either) do
      [
        { dimension: "country", operator: "is", value: "US", group: 0 },
        { dimension: "country", operator: "is", value: "CA", group: 0 },
        { dimension: "page", operator: "is", value: "/going-in/faq" }
      ]
    end

    def countries!
      %w[US CA DE].each_with_index do |country, index|
        dash_landing("/going-in/faq", at: now - 1.day + index.minutes, visitor: country, country: country)
      end
    end

    def bar
      document.at_css(".toolbar")
    end
    it "shows the group as one cluster with both filters in it, joined by or" do
      get "/telemetry", params: { filters: either }

      cluster = bar.at_css("[role=group][aria-label='Country is US or CA']")
      expect(cluster).to be_present
      expect(cluster.text.squish).to include("or")
      expect(cluster.css("a[aria-label^='Change the filter']").map { |link| link["aria-label"] })
        .to eq([ "Change the filter Country is US", "Change the filter Country is CA" ])
      expect(cluster.css("a[aria-label^='Remove the filter']").map { |link| link["aria-label"] })
        .to eq([ "Remove the filter Country is US", "Remove the filter Country is CA" ])
      expect(bar.at_css("[role=group][aria-label='Page is /going-in/faq']")).to be_present
    end

    it "keeps every member's own place in the list on its edit link" do
      get "/telemetry", params: { filters: either }

      edits = bar.css("a[aria-label^='Change the filter']").map { |link| link_query(link["href"])["edit"] }
      expect(edits).to eq(%w[0 1 2])
    end

    it "leaves a plain filter behind when one of two is removed" do
      get "/telemetry", params: { filters: either }

      href = bar.at_css("a[aria-label='Remove the filter Country is CA']")["href"]
      expect(link_query(href)["filters"]).to eq([
        { "dimension" => "country", "operator" => "is", "value" => "US" },
        { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq" }
      ])
    end

    it "offers another option on every group, opening the filter dialog on its dimension" do
      get "/telemetry", params: { filters: either }

      country = bar.at_css("a[aria-label='Add another option to Country is US or CA']")
      page = bar.at_css("a[aria-label='Add another option to Page is /going-in/faq']")

      expect(link_query(country["href"])).to include("dimension" => "country")
      expect(link_query(page["href"])).to include("dimension" => "page")
      expect(country["data-tm-filter-dimension"]).to eq("country")
      expect(country["data-tm-filter-operator"]).to eq("is")
      expect(country["aria-haspopup"]).to eq("dialog")
    end

    it "offers no other option on a negative, where or would match nearly every visit" do
      get "/telemetry", params: { filters: [ { dimension: "country", operator: "is_not", value: "US" } ] }

      expect(bar.at_css("[aria-label^='Add another option']")).to be_nil
    end

    it "counts a visit from either country and none from anywhere else" do
      countries!

      get "/telemetry/reports/locations", params: { filters: either }

      expect(response.body).to include("United States", "Canada")
      expect(response.body).not_to include("Germany")
    end

    it "warns that two negatives joined by or match nearly everything" do
      get "/telemetry", params: { filters: [
        { dimension: "country", operator: "is_not", value: "US", group: 0 },
        { dimension: "country", operator: "is_not", value: "CA", group: 0 }
      ] }

      cluster = bar.at_css("[role=group][aria-describedby]")
      expect(bar.at_css("##{cluster['aria-describedby']}").text).to include("matches nearly every visit")
    end

    it "does not warn about a group that asks for one value or another" do
      get "/telemetry", params: { filters: either }

      expect(response.body).not_to include("matches nearly every visit")
    end
  end
end
