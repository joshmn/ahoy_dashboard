require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard goal conversions", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def converted!(name: "site_searched", visitors: 2)
    visitors.times do |index|
      visit = dash_visit(started_at: now - 1.day, visitor: "visitor-#{index}")
      dash_page_view(visit, path: "/going-in/faq", at: now - 1.day)
      dash_goal(visit, name, at: now - 1.day, query: "thomson")
    end
  end

  def document
    Nokogiri::HTML5(response.body)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/goal_conversions"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is closed to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/goal_conversions"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says there are no goals rather than no conversions when none are defined" do
      get "/telemetry/goal_conversions"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Add a goal to get started")
      expect(response.body).to include("New goal", AhoyDashboard::Engine.routes.url_helpers.new_settings_goal_path)
      expect(response.body).not_to include("Click a goal to filter")
      expect(Nokogiri::HTML5(response.body).at_css(".g-head")).to be_nil
    end

    it "renders a row per goal with its three numbers" do
      create(:dash_goal, event_name: "site_searched", display_name: "Searched")
      converted!

      get "/telemetry/goal_conversions"
      row = document.at_css(".g-list .g-row")

      expect(response).to have_http_status(:ok)
      expect(row.at_css(".nm").text.strip).to eq("Searched")
      expect(row.css(".g-num").size).to eq(3)
      expect(row.css(".g-num").first.text.strip).to eq("2")
    end

    # A goal that was defined and never fired is an answer, not an absence, so it
    # keeps its row and reads zero.
    it "keeps a row for a goal that has never fired" do
      create(:dash_goal, event_name: "never_happened", display_name: "Never")

      get "/telemetry/goal_conversions"

      expect(document.at_css(".g-list .g-row .nm").text.strip).to eq("Never")
      expect(document.at_css(".g-list .g-row .g-num").text.strip).to eq("0")
    end

    it "serves its own frame without a src, so the dashboard's frame cannot loop" do
      get "/telemetry/goal_conversions"
      frame = document.at_css("tm-frame##{AhoyDashboard::GoalConversionsPresenter::FRAME}")

      expect(frame).to be_present
      expect(frame["src"]).to be_nil
    end

    describe "clicking a goal" do
      before do
        create(:dash_goal, event_name: "site_searched", display_name: "Searched")
        converted!
      end

      it "filters the whole dashboard by it" do
        get "/telemetry/goal_conversions"
        row = document.at_css(".g-list .g-row")

        expect(row["href"]).to include("filters")
        expect(row["href"]).to include("Searched")
        expect(row["data-tm-frame"]).to eq("_top")
      end

      # The row is the control both ways: the one already applied takes itself
      # off rather than being applied a second time.
      it "takes the filter off again when it is the one applied" do
        get "/telemetry/goal_conversions",
            params: { filters: [ { dimension: "goal", operator: "is", value: "Searched" } ] }
        row = document.at_css(".g-list .g-row")

        expect(row["aria-current"]).to eq("true")
        expect(row["title"]).to eq("Remove filter")
        expect(row["href"]).not_to include("Searched")
      end

      it "takes off a goal filter with any operator when it stands alone" do
        get "/telemetry/goal_conversions",
            params: { filters: [ { dimension: "goal", operator: "contains", value: "Searched" } ] }
        row = document.at_css(".g-list .g-row")

        expect(row["aria-current"]).to eq("true")
        expect(row["href"]).not_to include("Searched")
      end

      it "leaves an or group holding the goal alone rather than treating it as the row's own filter" do
        get "/telemetry/goal_conversions",
            params: { filters: [ { dimension: "goal", operator: "is", value: "Searched", group: "0" },
                                 { dimension: "goal", operator: "is", value: "Booked", group: "0" } ] }
        row = document.at_css(".g-list .g-row")
        href = CGI.unescape(row["href"])

        expect(row["aria-current"]).not_to eq("true")
        expect(href).to include("filters[][value]=Booked")
        expect(href).to include("filters[][group]=0")
        expect(href.scan("filters[][value]=Searched").size).to eq(2)
      end
    end

    it "prints the money beside the name only for a goal that carries a currency" do
      create(:dash_goal, event_name: "site_searched", display_name: "Searched", currency: "USD")
      converted!

      get "/telemetry/goal_conversions"

      expect(document.at_css(".g-list .g-row")).to be_present
      expect(document.css(".g-rev").size).to be <= 1
    end

    it "prints revenue as money, the way Explore does" do
      create(:dash_goal, event_name: "consult_booked", display_name: "Booked", currency: "USD")
      2.times do |index|
        visit = dash_visit(started_at: now - 1.day, visitor: "buyer-#{index}")
        dash_goal(visit, "consult_booked", at: now - 1.day, revenue: "300")
      end

      get "/telemetry/goal_conversions"
      revenue = document.at_css("[title^='Revenue totalled']").text.strip

      expect(revenue).to eq("$600.00")
      expect(response.body).not_to include("600.0<")
    end

    it "prints no revenue on a revenue goal as zero dollars rather than a bare 0.0" do
      create(:dash_goal, event_name: "consult_booked", display_name: "Booked", currency: "USD")
      visit = dash_visit(started_at: now - 1.day, visitor: "free")
      dash_goal(visit, "consult_booked", at: now - 1.day)

      get "/telemetry/goal_conversions"

      expect(document.at_css("[title^='Revenue totalled']").text.strip).to eq("$0.00")
    end

    it "carries the range it was asked for" do
      create(:dash_goal, event_name: "site_searched", display_name: "Searched")
      converted!

      get "/telemetry/goal_conversions", params: { period: "7d" }

      expect(response).to have_http_status(:ok)
    end
  end
end
