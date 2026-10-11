require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard journey explorer", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def clock(hour, minute = 0)
    AhoyDashboard.time_zone.local(2026, 8, 10, hour, minute)
  end

  def journeys!
    first = dash_visit(started_at: clock(9), visitor: "a")
    dash_page_view(first, path: "/", at: clock(9))
    dash_page_view(first, path: "/going-in", at: clock(9, 5))
    dash_page_view(first, path: "/going-in/faq", at: clock(9, 9))

    second = dash_visit(started_at: clock(10), visitor: "b")
    dash_page_view(second, path: "/", at: clock(10))
    dash_page_view(second, path: "/consult", at: clock(10, 5))
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/journey"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/journey"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "opens as one column, with nothing standing in for the steps nobody has picked yet" do
      journeys!

      get "/telemetry/journey"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Every page viewed")
      expect(response.body).to include("/going-in/faq")
      expect(response.body).not_to include("Step 2")
      expect(response.body).to include("Pick a page to see where visitors went next")
    end

    it "does not call the first column landing pages, because it is every page viewed" do
      journeys!

      get "/telemetry/journey"
      text = Nokogiri::HTML5(response.body).text.squish

      expect(text).to include("Where visitors went after any page they viewed.")
      expect(text).not_to include("Entry pages", "landed on", "entry page")
    end

    it "counts visitors, not sessions" do
      journeys!
      revisit = dash_visit(started_at: clock(11), visitor: "a")
      dash_page_view(revisit, path: "/", at: clock(11))
      dash_page_view(revisit, path: "/going-in", at: clock(11, 5))

      get "/telemetry/journey", params: { steps: [ "/", "/going-in" ] }
      text = Nokogiri::HTML5(response.body).text.squish

      expect(text).to include("1 visitor")
      expect(text).to include("50% of step 1")
      expect(text).not_to match(/sessions?\b/i)
      expect(text).not_to include("of entries")
    end

    it "says visitors left the site and names the page they viewed" do
      journeys!

      get "/telemetry/journey", params: { steps: [ "/", "/consult", "__exit__" ] }
      document = Nokogiri::HTML5(response.body)
      text = document.text.squish

      expect(text).to include("1 visitor left the site here")
      expect(text).to include("50% of visitors who viewed /")
      expect(text).not_to include("entered at", "sessions")
    end

    it "titles the exit row by visitors" do
      journeys!

      get "/telemetry/journey", params: { steps: [ "/", "/consult" ] }

      expect(Nokogiri::HTML5(response.body).css("a[title='Visitors who left the site here']")).to be_present
    end

    it "opens the next column only once a step is picked" do
      journeys!

      get "/telemetry/journey", params: { steps: [ "/" ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Step 2")
      expect(response.body).not_to include("Step 3")
    end

    # Columns scroll sideways rather than folding away. A journey is a sequence
    # and hiding the middle of it hides the thing being read.
    it "keeps every earlier column open once a third one opens" do
      journeys!

      get "/telemetry/journey",
        params: { steps: [ "/", "/going-in" ] }

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("j-col\"").size).to eq(3)
      expect(response.body).to include("Step 3")
    end

    it "makes every row a link that carries the whole chain" do
      journeys!

      get "/telemetry/journey"

      expect(response.body).to include("steps%5B%5D=%2Fconsult")
    end

    it "shows what came next once a step is picked" do
      journeys!

      get "/telemetry/journey", params: { steps: [ "/" ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Step 2")
      expect(response.body).to include("after")
      expect(response.body).to include(%(aria-current="true"))
    end

    it "reads two steps on" do
      journeys!

      get "/telemetry/journey",
        params: { steps: [ "/", "/going-in" ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Step 3")
      expect(response.body).to include("/going-in/faq")
    end

    it "offers the exit when the journey stops" do
      journeys!

      get "/telemetry/journey", params: { steps: [ "/consult" ] }

      expect(response.body).to include("Exited site")
    end

    it "narrows a column from the search box" do
      journeys!

      get "/telemetry/journey", params: { find: [ "going" ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/going-in/faq")
      expect(response.body).not_to include(">/consult<")
    end

    it "says nothing matches rather than blaming the range" do
      journeys!

      get "/telemetry/journey", params: { find: [ "nowhere" ] }

      expect(response.body).to include("Nothing matches that")
    end

    # The design's column is a head and a list, so a cut column shows the rows it
    # kept rather than a line explaining that it cut some.
    it "shows the busiest rows and no more when a column is cut" do
      journeys!
      visit = dash_visit(started_at: clock(11), visitor: "c")
      15.times { |index| dash_page_view(visit, path: "/page-#{index}", at: clock(11, index)) }

      get "/telemetry/journey"
      rows = Nokogiri::HTML5(response.body).css(".j-col .j-list .data-row")

      expect(rows.size).to be <= AhoyDashboard::JourneyQuery::ROWS
      expect(response.body).not_to include("Showing the busiest")
    end

    it "keeps the range and the filters when it is opened from the dashboard" do
      journeys!

      get "/telemetry/journey",
        params: { period: "day", filters: [ { dimension: "page", operator: "is", value: "/going-in" } ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing in this range")
    end

    it "does not remember the view, because only the dashboard writes that cookie" do
      get "/telemetry/journey", params: { period: "7d" }

      expect(response.cookies["dash_view"]).to be_nil
    end

    it "stays out of the index" do
      get "/telemetry/journey"

      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    end
  end

  describe "a hand edited url" do
    before { sign_in create(:user, :admin) }

    it "renders rather than falling over on a chain of nonsense" do
      journeys!

      get "/telemetry/journey", params: { steps: "banana", find: "x" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Every page viewed")
    end

    it "renders rather than falling over on a chain of sql" do
      journeys!

      get "/telemetry/journey",
        params: { steps: [ "/') or 1=1; drop table ahoy_events --" ] }

      expect(response).to have_http_status(:ok)
      expect(Ahoy::Event.count).to eq(5)
    end

    it "renders every period" do
      journeys!

      AhoyDashboard::Period::ALL.each do |period|
        get "/telemetry/journey", params: { period: period.key, from: "2026-08-01", to: "2026-08-11" }

        expect(response).to have_http_status(:ok), "expected the #{period.key} period to render"
      end
    end
  end

  describe "on the dashboard" do
    before { sign_in create(:user, :admin) }

    # Embedded at the bottom of the page rather than linked from the bar: three
    # columns need the full width, and the bar is for controls that change what is
    # on screen rather than for destinations.
    it "is embedded at the bottom, carrying the query the dashboard was opened on" do
      get "/telemetry", params: { period: "7d" }

      frame = Nokogiri::HTML5(response.body).at_css("tm-frame#dash_journey")

      expect(frame).to be_present
      expect(frame["src"]).to eq("/telemetry/journey?period=7d")
      expect(frame["loading"]).to eq("lazy")
    end

    it "sits after the cards, so it reads last" do
      get "/telemetry"

      body = response.body

      expect(body.index("id=\"dash_journey\"")).to be > body.index('id="panels"')
    end

    # The frame the dashboard points at must not repeat its own source url, or the
    # response sends the frame straight back where it came from.
    it "serves its own frame without a src" do
      get "/telemetry/journey"

      frame = Nokogiri::HTML5(response.body).at_css("tm-frame#dash_journey")

      expect(frame).to be_present
      expect(frame["src"]).to be_nil
    end

    it "no longer takes a slot in the bar" do
      get "/telemetry"

      expect(response.body).not_to include("Follow it backwards")
      expect(response.body).not_to include("Who's here now")
    end
  end
end
