require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard reports", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!(pages: 3)
    pages.times do |index|
      visit = dash_visit(
        started_at: now - 1.day - index.minutes,
        visitor: "visitor-#{index}",
        country: index.even? ? "US" : "CA",
        browser: index.even? ? "Chrome" : "Safari",
        referring_domain: index.even? ? "google.com" : nil,
        utm_medium: index.even? ? "cpc" : nil,
        utm_source: index.even? ? "adwords" : nil,
        utm_campaign: index.even? ? "spring" : nil,
        utm_term: index.even? ? "prison" : nil,
        utm_content: index.even? ? "banner" : nil,
        landing_page: "https://federalprisondude.com/page-#{index}"
      )
      dash_page_view(visit, path: "/page-#{index}", at: now - 1.day - index.minutes)
      dash_page_view(visit, path: "/resources", at: now - 1.day - index.minutes + 1.minute)
      dash_goal(visit, "site_searched", at: now - 1.day - index.minutes + 2.minutes, facility_id: index.to_s)
    end
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/reports/pages"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/reports/pages"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "renders every card and every tab inside it" do
      traffic!

      AhoyDashboard::Report.cards.each do |report|
        report.tabs.each do |tab|
          get "/telemetry/reports/#{report.key}", params: { tab: tab.key }

          expect(response).to have_http_status(:ok),
            "expected #{report.key}/#{tab.key} to render, got #{response.status}"
        end
      end
    end

    it "renders every card against an empty database" do
      AhoyDashboard::Report.cards.each do |report|
        get "/telemetry/reports/#{report.key}"

        expect(response).to have_http_status(:ok), "expected an empty #{report.key} card to render"
      end
    end

    it "wraps the card in the frame the dashboard is waiting on" do
      traffic!

      get "/telemetry/reports/pages"

      expect(response.body).to include("report_pages")
    end

    it "returns the same card without querying or rendering the surrounding layout for a frame" do
      traffic!
      get "/telemetry/reports/pages"
      card = Nokogiri::HTML5(response.body).at_css("tm-frame#report_pages").to_html

      expect(AhoyDashboard::RealtimeQuery).not_to receive(:call)
      get "/telemetry/reports/pages", headers: { "Tm-Frame" => "report_pages" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<html", "dash-ask")
      expect(Nokogiri::HTML5(response.body).at_css("tm-frame#report_pages").to_html).to eq(card)
    end

    it "opens the sources card on its sources tab once a channel is the filter" do
      get "/telemetry/reports/sources",
          params: { filters: [ { dimension: "channel", operator: "is", value: "Direct / None" } ] }

      current = Nokogiri::HTML5(response.body).at_css('[data-controller="dash--tabs"] nav a[aria-current="true"]')
      expect(current.text.strip).to eq("Sources")
    end

    it "keeps the tab the url names over the drill down" do
      get "/telemetry/reports/sources",
          params: { tab: "channels", filters: [ { dimension: "channel", operator: "is", value: "Direct / None" } ] }

      current = Nokogiri::HTML5(response.body).at_css('[data-controller="dash--tabs"] nav a[aria-current="true"]')
      expect(current.text.strip).to eq("Channels")
    end

    it "falls back to the default tab for a tab nobody registered" do
      traffic!

      get "/telemetry/reports/pages", params: { tab: "hairstyles" }

      expect(response).to have_http_status(:ok)
    end

    it "404s for a report key nobody registered" do
      get "/telemetry/reports/hairstyles"

      expect(response).to have_http_status(:not_found)
    end

    it "renders the details view in its own frame" do
      traffic!

      get "/telemetry/reports/pages", params: { view: "details" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("report_details_pages")
    end

    it "pages the details view" do
      traffic!(pages: 4)

      get "/telemetry/reports/pages", params: { view: "details", page: 2 }

      expect(response).to have_http_status(:ok)
    end

    it "carries the dashboard's period and filters through" do
      traffic!

      get "/telemetry/reports/pages", params: {
        period: "7d", filters: [ { dimension: "page", operator: "is", value: "/resources" } ]
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/resources")
    end

    it "still renders on nonsense in the query string" do
      traffic!

      [
        { tab: "banana" },
        { period: "banana" },
        { view: "banana" },
        { page: "banana" },
        { page: "-3" },
        { filters: "banana" }
      ].each do |params|
        get "/telemetry/reports/sources", params: params

        expect(response).to have_http_status(:ok), "expected #{params.inspect} to still render"
      end
    end

    # The picker's markup has its own view spec. These are the two things only a
    # real request can see: that the card head actually renders it, and that the
    # links built off the card carry the choice so the modal and the CSV agree
    # with what is on screen.
    describe "the breakdown picker in the card" do
      it "renders on a tab that offers a choice" do
        get "/telemetry/reports/pages", params: { tab: "pages" }

        expect(response.body).to include(%(data-tm-picker="breakdown"))
        expect(response.body).to include("Break down by")
      end

      it "does not render on a tab that offers none" do
        get "/telemetry/reports/pages", params: { tab: "exit_pages" }

        expect(response.body).not_to include(%(data-tm-picker="breakdown"))
      end

      it "carries the choice into the details and the csv links" do
        dash_page_view(dash_visit(started_at: now - 1.day), path: "/resources", at: now - 1.day)

        get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "controller" }

        page = Nokogiri::HTML5(response.body)
        details = page.at_css("footer a[aria-haspopup=dialog]")
        card = page.at_css("section.panel")
        export = card.css("a").map { |node| node["href"] }.compact.grep(%r{/ahoy_dashboard/exports/})

        expect(details["href"]).to include("breakdown=controller")
        expect(export).to all(include("breakdown=controller")) if export.any?
      end
    end

    describe "the breakdown" do
      def entries!
        [
          [ "https://federalprisondude.com/resources?q=halfway+house", "/resources" ],
          [ "https://portal.federalprisondude.com/vouch", "/vouch" ]
        ].each_with_index do |(landing, path), index|
          visit = dash_visit(started_at: now - 2.days - index.minutes, visitor: "entry-#{index}",
                                  landing_page: landing)
          dash_page_view(visit, path: path, at: visit.started_at)
        end
      end

      def rows(params)
        get "/telemetry/reports/#{params.delete(:key) || 'pages'}", params: params

        Nokogiri::HTML5(response.body).css(".p-list .nm").map { |row| row.text.strip }
      end

      it "groups top pages by path until somebody asks for the controller" do
        traffic!

        expect(rows(tab: "pages")).to include("/page-0", "/resources")
        expect(rows(tab: "pages", breakdown: "controller")).to eq([ "public/pages" ])
      end

      it "drops the columns the engagement event cannot answer per controller" do
        traffic!

        get "/telemetry/reports/pages", params: { tab: "pages", view: "details", breakdown: "controller" }
        document = Nokogiri::HTML5(response.body)

        expect(document.at_css(".m-search .form-control")["placeholder"]).to include("rails controllers")
        expect(document.at_css("a[href*='explore']")["href"]).not_to include("scroll_depth")
      end

      it "groups the details view by the breakdown too" do
        traffic!

        get "/telemetry/reports/pages", params: { tab: "pages", view: "details", breakdown: "controller" }

        expect(Nokogiri::HTML5(response.body).css(".m-list .data-row .nm").map { |cell| cell.text.strip })
          .to eq([ "public/pages" ])
      end

      it "shows a path on entry pages, with nothing of the url around it" do
        entries!

        expect(rows(tab: "entry_pages")).to include("/resources", "/vouch")
        expect(rows(tab: "entry_pages")).not_to include(
          "https://federalprisondude.com/resources?q=halfway+house"
        )
      end

      # The one thing a path breakdown cannot say. request.path drops the query
      # string, and the landing page is the only place either ahoy table keeps it.
      it "shows the whole url, query string and all, on the url breakdown" do
        entries!

        expect(rows(tab: "entry_pages", breakdown: "url"))
          .to include("https://federalprisondude.com/resources?q=halfway+house")
      end

      it "shows the four hosts apart from each other on the hostname breakdown" do
        entries!

        expect(rows(tab: "entry_pages", breakdown: "host"))
          .to include("federalprisondude.com", "portal.federalprisondude.com")
      end

      it "falls back to the path rather than 500ing on a value nobody registered" do
        entries!

        [ "", "  ", "banana", "path; drop table ahoy_visits", "a" * 200, [ "url" ], { "url" => "1" } ].each do |value|
          expect(rows(tab: "entry_pages", breakdown: value)).to include("/resources"),
            "expected breakdown=#{value.inspect} to fall back to the path"
          expect(response).to have_http_status(:ok)
        end
      end

      it "ignores a breakdown another card offers" do
        traffic!

        expect(rows(key: "sources", breakdown: "host")).to include("Paid Search")
        expect(response).to have_http_status(:ok)
      end

      # The choice belongs to one card, so it is merged in at the card's own links
      # and never near QueryForm#to_query, which every other card builds from.
      it "keeps the choice off the links that leave the card" do
        traffic!

        get "/telemetry/reports/pages", params: { tab: "pages", breakdown: "controller" }
        hrefs = Nokogiri::HTML5(response.body).css("a").map { |link| link["href"] }.compact

        expect(hrefs.grep(%r{\A/telemetry/\?})).not_to be_empty
        expect(hrefs.grep(%r{\A/telemetry/\?}).grep(/breakdown/)).to be_empty
      end

      it "leaves every other card's frame alone" do
        traffic!

        get "/telemetry", params: { breakdown: "controller" }
        sources = Nokogiri::HTML5(response.body).at_css("tm-frame#report_sources")

        expect(response).to have_http_status(:ok)
        expect(sources["src"]).not_to include("breakdown")
      end
    end

    describe "the custom property picker" do
      before do
        create(:dash_property, key: "facility_id", position: 1)
        create(:dash_property, key: "results", position: 2)
        create(:dash_property, key: "gone_quiet", position: 3)
      end

      def properties_card(params = {})
        get "/telemetry/reports/behaviours", params: { tab: "properties" }.merge(params)
        Nokogiri::HTML5(response.body)
      end

      it "offers every allowlisted property, including one with nothing in the range" do
        traffic!

        labels = properties_card.css("[data-tm-picker=property] [data-dash--menu-target=panel] a").map { |item| item.text.strip }

        expect(labels).to include("facility_id", "results", "gone_quiet")
      end

      it "marks the property the card is showing" do
        traffic!

        active = properties_card(property: "results").css("[data-tm-picker=property] a[aria-current=true]")

        expect(active.map { |item| item.text.strip }).to eq([ "results" ])
        expect(active.first["aria-current"]).to eq("true")
      end

      it "names the showing property on the button, with a label that says what it is" do
        traffic!

        button = properties_card(property: "results").at_css("[data-tm-picker=property] button")

        expect(button.text.strip).to eq("results")
        expect(button["aria-label"]).to eq("Custom property: results")
        expect(button["aria-expanded"]).to eq("false")
        expect(button["aria-controls"]).to eq(button.document.at_css("[data-tm-picker=property] [data-dash--menu-target=panel]")["id"])
      end

      it "opens on the first allowlisted property when the url names none" do
        traffic!

        expect(properties_card.at_css("[data-tm-picker=property] button").text.strip)
          .to eq("facility_id")
      end

      it "does not render on the goals tab" do
        traffic!

        get "/telemetry/reports/behaviours", params: { tab: "goals" }

        expect(response.body).not_to include(%(data-tm-picker="property"))
      end

      it "groups the card by the property somebody picked" do
        traffic!

        rows = properties_card(property: "facility_id").css(".p-list .nm").map(&:text)

        expect(rows).to include("0", "1", "2")
      end

      it "groups by the picked property rather than the default" do
        traffic!

        rows = properties_card(property: "action").css(".p-list .nm").map(&:text)

        expect(rows).to eq([ "show" ])
      end

      it "carries the property through to the details link" do
        traffic!

        details = properties_card(property: "facility_id").at_css("footer a[aria-haspopup=dialog]")

        expect(details["href"]).to include("property=facility_id")
        expect(details["href"]).to include("view=details")
      end

      it "groups the details view by the property too" do
        traffic!

        get "/telemetry/reports/behaviours",
            params: { tab: "properties", view: "details", property: "action" }

        expect(response).to have_http_status(:ok)
        headers = Nokogiri::HTML5(response.body).css(".m-list .data-row .nm").map { |cell| cell.text.strip }

        expect(headers).to eq([ "show" ])
      end

      it "shows the empty state for a property nothing in the range carries" do
        traffic!

        card = properties_card(property: "gone_quiet")

        expect(card.css(".p-list")).to be_empty
        expect(response.body).to include("Nothing here for this range")
      end

      it "still renders on a property value that is not a property name" do
        traffic!

        [ "", "  ", "not a key", "facility_id; drop table ahoy_events", "prop:facility_id",
          "a" * 41, "../../etc/passwd" ].each do |value|
          get "/telemetry/reports/behaviours", params: { tab: "properties", property: value }

          expect(response).to have_http_status(:ok), "expected property=#{value.inspect} to render"
        end
      end

      it "falls back to the default property when the url names a bad one" do
        traffic!

        expect(properties_card(property: "not\na key").at_css("[data-tm-picker=property] button").text.strip)
          .to eq("facility_id")
      end
    end

    describe "the custom properties tab with nothing on the list" do
      def planned!
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-plan")
        dash_page_view(visit, path: "/pricing", at: now - 1.day)
        dash_goal(visit, "signed_up", at: now - 1.day + 1.minute, plan: "pro")
      end

      it "opens on a key the range's events actually carry" do
        planned!

        get "/telemetry/reports/behaviours", params: { tab: "properties" }
        card = Nokogiri::HTML5(response.body)

        expect(card.at_css("[data-tm-picker=property] button").text.strip).to eq("plan")
        expect(card.css(".p-list .nm").map { |cell| cell.text.strip }).to eq([ "pro" ])
        expect(response.body).not_to include("facility_id")
      end

      it "opens on a found key when the url names a property in a shape it cannot use" do
        planned!

        get "/telemetry/reports/behaviours", params: { tab: "properties", property: [ "facility_id" ] }

        expect(Nokogiri::HTML5(response.body).at_css("[data-tm-picker=property] button").text.strip).to eq("plan")
      end

      it "says there are no custom properties when no event carries one" do
        dash_page_view(dash_visit(started_at: now - 1.day, visitor: "visitor-bare"), path: "/", at: now - 1.day)

        get "/telemetry/reports/behaviours", params: { tab: "properties" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No custom properties in this range")
        expect(response.body).to include(%(href="/telemetry/settings/properties"))
        expect(response.body).not_to include(%(data-tm-picker="property"))
        expect(response.body).not_to include("facility_id")
      end

      it "exports the key the card opened on" do
        planned!

        get "/telemetry/exports/behaviours", params: { tab: "properties" }

        expect(response).to have_http_status(:ok)
        expect(response.body.lines.drop(1).map { |line| line.split(",").first }).to eq([ "pro" ])
      end
    end

    describe "the ip addresses card, which is registered from an initializer" do
      def addressed!
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-ip", ip: "203.0.113.44")
        dash_page_view(visit, path: "/page-0", at: now - 1.day)
        visit
      end

      it "is registered by config/initializers/dash_panels.rb" do
        expect(AhoyDashboard::Report.find("ip_addresses").title).to eq("IP addresses")
        expect(AhoyDashboard::Report.cards.map(&:key)).to include("ip_addresses")
        expect(AhoyDashboard::Dimension.find("ip").label).to eq("IP address")
      end

      it "renders the card in the frame the dashboard is waiting on" do
        addressed!

        get "/telemetry/reports/ip_addresses"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("report_ip_addresses")
        expect(response.body).to include("203.0.113.44")
      end

      it "renders against an empty database" do
        get "/telemetry/reports/ip_addresses"

        expect(response).to have_http_status(:ok)
      end

      it "renders its details modal" do
        addressed!

        get "/telemetry/reports/ip_addresses", params: { view: "details" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("report_details_ip_addresses")
        expect(response.body).to include("203.0.113.44")
      end

      it "narrows its details modal to a search" do
        addressed!

        get "/telemetry/reports/ip_addresses", params: { view: "details", q: "198.51" }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("203.0.113.44")
      end

      it "exports itself to csv" do
        addressed!

        get "/telemetry/exports/ip_addresses.csv"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("IP address")
        expect(response.body).to include("203.0.113.44")
      end

      it "lands in the dashboard grid with its own frame and dialog" do
        addressed!

        get "/telemetry"

        expect(response.body).to include("report_ip_addresses")
        expect(response.body).to include("tm-modal-ip_addresses")
      end

      it "puts itself on the export menu" do
        get "/telemetry/palette"

        expect(response.body).to include("IP addresses as CSV")
      end

      it "offers its dimension to the filter dialog" do
        get "/telemetry/filters/new", params: { category: "custom" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("IP address")
      end

      # An address is one person, so the card is ranked by visits: ranked by
      # visitors every row reads 1 and the card says nothing at all.
      it "ranks by visits, so somebody who came back is above somebody who came once" do
        once = dash_visit(started_at: now - 1.day, visitor: "one", ip: "198.51.100.7")
        dash_page_view(once, path: "/page-0", at: now - 1.day)

        2.times do |index|
          repeat = dash_visit(started_at: now - 2.days + index.hours, visitor: "two",
                                   ip: "203.0.113.44")
          dash_page_view(repeat, path: "/page-0", at: now - 2.days + index.hours)
        end

        get "/telemetry/reports/ip_addresses"

        labels = Nokogiri::HTML5(response.body).css(".p-list .nm").map { |row| row.text.strip }

        expect(labels).to eq([ "203.0.113.44", "198.51.100.7" ])
      end

      it "narrows the whole dashboard when the filter is applied" do
        addressed!
        other = dash_visit(started_at: now - 1.day, visitor: "other", ip: "198.51.100.7")
        dash_page_view(other, path: "/elsewhere", at: now - 1.day)

        get "/telemetry/reports/pages",
            params: { filters: [ { dimension: "ip", operator: "is", value: "203.0.113.44" } ] }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/page-0")
        expect(response.body).not_to include("/elsewhere")
      end
    end

    it "answers the tab switcher in json" do
      traffic!

      get "/telemetry/reports/pages.json", params: { tab: "entry_pages" }

      expect(response).to have_http_status(:ok)
      expect { JSON.parse(response.body) }.not_to raise_error
    end
  end
end
