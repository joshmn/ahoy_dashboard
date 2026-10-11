require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard realtime", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  def someone(name, path:, ago: 1.minute, **attributes)
    visit = dash_visit(started_at: now - ago, visitor: name, **attributes)
    dash_page_view(visit, path: path, at: now - ago)

    visit
  end

  it "sends a signed out visitor to sign in" do
    get "/telemetry/realtime"

    expect(response).to redirect_to("/users/sign_in")
  end

  it "is a 404 for a signed in visitor who is not an admin" do
    sign_in create(:user)

    get "/telemetry/realtime.json"

    expect(response).to have_http_status(:not_found)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "renders the frame the poller replaces" do
      get "/telemetry/realtime"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("dash_realtime")
    end

    # The page used to render the header pill as its whole body, which put two of
    # them on screen with the layout's copy, both polling.
    it "renders the live pill exactly once" do
      get "/telemetry/realtime"

      expect(document.css(".live").size).to eq(1)
    end

    # The src points at the panel-only branch, not at this page, so the response
    # carries the panel rather than another copy of the whole screen.
    it "renders one refreshable panel frame that does not refetch itself on load" do
      get "/telemetry/realtime"

      frames = document.css("tm-frame#dash_realtime_panel")

      expect(frames.size).to eq(1)
      expect(frames.first["src"]).to eq("/telemetry/realtime?view=panel")
      expect(frames.first.attributes).to have_key("complete")
    end

    it "serves the panel on its own without a src, so the frame cannot load itself" do
      get "/telemetry/realtime", params: { view: "panel" }

      frames = document.css("tm-frame#dash_realtime_panel")

      expect(frames.size).to eq(1)
      expect(frames.first["src"]).to be_nil
      expect(response.body).to include("tm-live__panel")
    end

    it "links the header pill at the page" do
      get "/telemetry"

      pill = document.at_css("a.live")

      expect(pill["href"]).to eq("/telemetry/realtime")
      expect(pill["data-tm-frame"]).to eq("_top")
    end

    it "says nobody is here against an empty database" do
      get "/telemetry/realtime"

      expect(response).to have_http_status(:ok)
      expect(document.at_css(".tm-live__number").text.strip).to eq("0")
      expect(response.body).to include("No one is on the site right now")
    end

    it "drops the empty state as soon as anybody is counted" do
      someone("one", path: "/a")

      get "/telemetry/realtime"

      expect(document.at_css(".tm-live__number").text.strip).to eq("1")
      expect(response.body).not_to include("No one is on the site right now")
    end

    it "marks the live pill current rather than the dashboard tab" do
      get "/telemetry/realtime"

      expect(document.at_css("a.live")["aria-current"]).to eq("page")
      expect(document.css("nav[aria-label='Primary'] a[aria-current]")).to be_empty
    end

    it "counts nobody against an empty database" do
      get "/telemetry/realtime.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("visitors" => 0)
    end

    it "counts the people on the site right now" do
      one = dash_visit(started_at: now - 2.minutes, visitor: "one")
      dash_page_view(one, path: "/a", at: now - 2.minutes)
      two = dash_visit(started_at: now - 1.minute, visitor: "two")
      dash_page_view(two, path: "/b", at: now - 1.minute)

      get "/telemetry/realtime.json"

      expect(JSON.parse(response.body)).to eq("visitors" => 2)
    end

    it "lists the pages they are on and where they came from" do
      someone("one", path: "/going-in/faq", referring_domain: "google.com")
      someone("two", path: "/going-in/faq", ago: 2.minutes, referring_domain: "google.com")
      someone("three", path: "/resources", ago: 3.minutes, referring_domain: nil)

      get "/telemetry/realtime"

      expect(document.at_css(".tm-live__number").text.strip).to eq("3")

      pages, sources = document.css(".p-list").map { |list| labels_and_counts(list) }

      expect(pages).to eq([ [ "/going-in/faq", "2" ], [ "/resources", "1" ] ])
      expect(sources).to eq([ [ "google.com", "2" ], [ AhoyDashboard::Sql::DIRECT, "1" ] ])
    end

    # Somebody reading four pages in five minutes is one person on the fourth
    # one, so the rows count people rather than views and add up to the number
    # above them.
    it "counts a person once, against the last page they opened" do
      visit = dash_visit(started_at: now - 4.minutes, visitor: "one")
      dash_page_view(visit, path: "/first", at: now - 4.minutes)
      dash_page_view(visit, path: "/second", at: now - 3.minutes)
      dash_page_view(visit, path: "/third", at: now - 1.minute)

      get "/telemetry/realtime"

      expect(labels_and_counts(document.at_css(".p-list"))).to eq([ [ "/third", "1" ] ])
    end

    it "leaves crawlers out of it" do
      visit = dash_visit(started_at: now - 1.minute, visitor: "bot")
      dash_page_view(visit, path: "/going-in/faq", at: now - 1.minute, crawler: "Googlebot")

      get "/telemetry/realtime"

      expect(document.at_css(".tm-live__number").text.strip).to eq("0")
      expect(JSON.parse(get_json)).to eq("visitors" => 0)
    end

    # One window, or the number on load and the number after the first refresh
    # are answers to two different questions.
    it "reads the page and the poll over the same window" do
      someone("here", path: "/a", ago: 4.minutes)
      someone("gone", path: "/b", ago: 20.minutes)

      get "/telemetry/realtime"

      expect(document.at_css(".tm-live__number").text.strip).to eq("1")
      expect(labels_and_counts(document.at_css(".p-list"))).to eq([ [ "/a", "1" ] ])

      get "/telemetry/realtime.json"

      expect(JSON.parse(response.body)).to eq("visitors" => 1)
    end

    it "keeps itself out of the index" do
      get "/telemetry/realtime"

      expect(response.body).to match(/noindex/)
    end
  end

  def labels_and_counts(list)
    list.css(".data-row").map do |row|
      [ row.at_css(".nm").text.strip, row.at_css(".cnt").text.strip ]
    end
  end

  def get_json
    get "/telemetry/realtime.json"

    response.body
  end
end
