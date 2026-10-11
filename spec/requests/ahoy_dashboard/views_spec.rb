require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard remembered view", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }
  let(:cookie) { AhoyDashboard::BaseController::VIEW_COOKIE }

  around { |example| travel_to(now) { example.run } }

  # A cleared cookie comes back as an empty string rather than as nothing at all.
  def remembered
    cookies[cookie].presence
  end

  def set_cookie
    Array(response.headers["Set-Cookie"]).find { |line| line.start_with?("#{cookie}=") }.to_s.downcase
  end

  def remember(value)
    cookies[cookie] = value
  end

  def period_label
    Nokogiri::HTML5(response.body).at_css("#tm-period-button").text.strip
  end

  def reset_controls
    Nokogiri::HTML5(response.body).css("form[action='/telemetry/view']")
  end

  describe "writing it" do
    before { sign_in create(:user, :admin) }

    it "remembers the range, the interval, the metric, the comparison and the crawler toggle" do
      get "/telemetry", params: {
        period: "7d", interval: "hour", metric: "pageviews",
        comparison: "previous_period", crawlers: "1"
      }

      expect(Rack::Utils.parse_nested_query(remembered)).to eq(
        "period" => "7d", "interval" => "hour", "metric" => "pageviews",
        "comparison" => "previous_period", "crawlers" => "1"
      )
    end

    it "remembers the two ends of a custom range" do
      get "/telemetry", params: { period: "custom", from: "2026-07-01", to: "2026-07-31" }

      expect(Rack::Utils.parse_nested_query(remembered)).to include(
        "period" => "custom", "from" => "2026-07-01", "to" => "2026-07-31"
      )
    end

    # A filter is a question somebody asked once. Reapplying it silently scopes
    # every number on the page on every later visit.
    it "never remembers a filter" do
      get "/telemetry", params: {
        period: "7d",
        filters: [ { dimension: "page", operator: "is", value: "/going-in/faq" } ]
      }

      expect(remembered).to eq("period=7d")
    end

    it "forgets it again when the dashboard is back at its defaults" do
      get "/telemetry", params: { period: "7d" }
      expect(remembered).to be_present

      get "/telemetry", params: { period: AhoyDashboard::Period::DEFAULT_KEY }

      expect(remembered).to be_nil
    end

    it "stores nothing at all for a plain visit to the default view" do
      get "/telemetry"

      expect(remembered).to be_nil
    end

    # Realtime is a glance at the last half hour, not a view worth opening into
    # next week, and skipping the write leaves the last real one intact.
    it "does not let a realtime glance overwrite the remembered view" do
      get "/telemetry", params: { period: "7d" }

      get "/telemetry", params: { period: "realtime" }

      expect(remembered).to eq("period=7d")
    end

    it "is not written by a report frame, a json poll or a csv export" do
      [
        "/telemetry/reports/pages?period=7d",
        "/telemetry.json?period=7d",
        "/telemetry/dashboard.json?period=7d",
        "/telemetry/exports/pages?period=7d",
        "/telemetry/realtime?period=7d"
      ].each do |path|
        get path

        expect(remembered).to be_nil, "expected #{path} to leave the remembered view alone"
      end
    end

    it "is not written for somebody who is not an admin" do
      sign_out :user
      sign_in create(:user)

      get "/telemetry", params: { period: "7d" }

      expect(response).to have_http_status(:not_found)
      expect(remembered).to be_nil
    end

    it "carries httponly and lax, and an expiry a long way out" do
      get "/telemetry", params: { period: "7d" }

      expect(set_cookie).to include("httponly")
      expect(set_cookie).to include("samesite=lax")
      expect(set_cookie).to include(AhoyDashboard::BaseController::VIEW_EXPIRY.from_now.httpdate.downcase)
    end
  end

  describe "restoring it" do
    before { sign_in create(:user, :admin) }

    it "opens a bare dashboard on the last view" do
      remember("period=7d&metric=pageviews")

      get "/telemetry"

      expect(response).to have_http_status(:ok)
      expect(period_label).to eq("Last 7 days")
      summary = Nokogiri::HTML5(response.body).at_css("tm-frame#dash_summary")
      expect(Rack::Utils.parse_nested_query(URI.parse(summary["src"]).query)).to include("period" => "7d", "metric" => "pageviews")
    end

    it "offers a way to forget it, and only while it is being applied" do
      remember("period=7d")

      get "/telemetry"
      expect(reset_controls.size).to eq(1)

      get "/telemetry", params: { period: "7d" }
      expect(reset_controls).to be_empty
    end

    # Somebody following a shared link has to see what the link says. to_query
    # leaves defaults out, so a link naming only the period is a whole view.
    it "loses to an explicit param that disagrees" do
      remember("period=7d&metric=pageviews")

      get "/telemetry", params: { period: "day" }

      expect(period_label).to eq("Today so far")
    end

    it "keeps out of a link that names only a filter" do
      remember("period=7d")

      get "/telemetry", params: {
        filters: [ { dimension: "page", operator: "is", value: "/going-in/faq" } ]
      }

      expect(period_label).to eq("Last 30 days")
    end

    it "falls back to the defaults on a cookie somebody has been editing" do
      [
        "period=banana",
        "period[]=7d",
        "%%%",
        "filters[][dimension]=page&filters[][operator]=is&filters[][value]=/going-in/faq",
        "period=custom&from=yesterday&to=tomorrow",
        "a" * 3_000
      ].each do |value|
        remember(value)

        get "/telemetry"

        expect(response).to have_http_status(:ok), "expected #{value.truncate(40)} to still render"
      end
    end

    it "will not smuggle a filter in through the cookie" do
      remember("filters[][dimension]=page&filters[][operator]=is&filters[][value]=/going-in/faq")

      get "/telemetry"

      expect(Nokogiri::HTML5(response.body).css(".chip")).to be_empty
      expect(reset_controls).to be_empty
    end
  end

  describe "forgetting it" do
    it "sends a signed out visitor to sign in" do
      delete "/telemetry/view"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      delete "/telemetry/view"

      expect(response).to have_http_status(:not_found)
    end

    it "clears the cookie and lands on a clean dashboard" do
      sign_in create(:user, :admin)
      remember("period=7d&metric=pageviews")

      delete "/telemetry/view"

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/telemetry/")
      expect(remembered).to be_nil

      follow_redirect!

      expect(period_label).to eq("Last 30 days")
    end
  end
end
