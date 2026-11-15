require "rails_helper"

RSpec.describe "Dashboard visitor journeys", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def clock(day, hour, minute = 0)
    dash_time(2026, 8, day, hour, minute)
  end

  let!(:anonymous) { dash_landing("/", at: clock(10, 9), visitor: "laptop", visit_token: "visit-anon") }
  let!(:signed_in) { dash_landing("/account", at: clock(10, 11), visitor: "laptop", visit_token: "visit-in", user_id: 7) }
  let!(:phone) { dash_landing("/deals", at: clock(11, 9), visitor: "phone", visit_token: "visit-phone", user_id: 7) }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists recent visitors" do
      get "/telemetry/visitors"

      expect(response).to have_http_status(:ok)
    end

    it "lists only signed in visitors, over a range and filters" do
      get "/telemetry/visitors", params: { who: "identified", period: "7d", page: 3,
                                           filters: [ { dimension: "country", operator: "is", value: "US" } ] }

      expect(response).to have_http_status(:ok)
    end

    it "opens a visitor by token" do
      get "/telemetry/visitors/laptop"

      expect(response).to have_http_status(:ok)
    end

    it "opens a user across their tokens" do
      get "/telemetry/visitors/users/7"

      expect(response).to have_http_status(:ok)
    end

    it "opens with hidden traffic shown" do
      dash_exclusion("Everything", [ "country", "is", "US" ])

      get "/telemetry/visitors/users/7", params: { crawlers: "1", internal: "1" }

      expect(response).to have_http_status(:ok)
    end

    it "opens a person whose every visit is hidden" do
      dash_exclusion("Everything", [ "country", "is", "US" ])

      get "/telemetry/visitors/laptop"

      expect(response).to have_http_status(:ok)
    end

    it "opens a long visit without listing every event" do
      300.times { |index| dash_page_view(phone, path: "/p/#{index}", at: clock(11, 9) + index.seconds) }

      get "/telemetry/visitors/phone"

      expect(response).to have_http_status(:ok)
    end

    it "is a 404 for a visitor, user or visit nobody has" do
      get "/telemetry/visitors/nobody"
      expect(response).to have_http_status(:not_found)

      get "/telemetry/visitors/users/999"
      expect(response).to have_http_status(:not_found)

      get "/telemetry/visitors/users/not-an-id"
      expect(response).to have_http_status(:not_found)

      get "/telemetry/visitors/visits/nothing"
      expect(response).to have_http_status(:not_found)
    end

    it "sends a visit token to its visitor, at that visit" do
      get "/telemetry/visitors/visits/visit-in"

      expect(response).to redirect_to("/telemetry/visitors/laptop#visit-#{signed_in.id}")
    end

    it "sends a visit token to the page the visit is on" do
      Array.new(25) { |index| dash_landing("/", at: clock(9, 0, index), visitor: "laptop") }

      get "/telemetry/visitors/visits/visit-in"

      expect(response).to redirect_to("/telemetry/visitors/laptop?page=2#visit-#{signed_in.id}")
    end

    it "shows hidden traffic when the visit asked for is hidden" do
      dash_exclusion("Everything", [ "country", "is", "US" ])

      get "/telemetry/visitors/visits/visit-in"

      expect(response).to redirect_to("/telemetry/visitors/laptop?crawlers=1&internal=1#visit-#{signed_in.id}")
    end

    it "looks up a visit token, a visitor token and a user id" do
      get "/telemetry/visitors/lookup", params: { q: "visit-phone" }
      expect(response).to redirect_to("/telemetry/visitors/phone#visit-#{phone.id}")

      get "/telemetry/visitors/lookup", params: { q: "laptop" }
      expect(response).to redirect_to("/telemetry/visitors/laptop")

      get "/telemetry/visitors/lookup", params: { q: "7" }
      expect(response).to redirect_to("/telemetry/visitors/users/7")
    end

    it "sends a lookup that matches nothing back to the list" do
      get "/telemetry/visitors/lookup", params: { q: "nobody", period: "7d" }

      expect(response).to redirect_to("/telemetry/visitors?period=7d")
      expect(flash[:alert]).to be_present
    end

    it "builds the same urls a host app links to" do
      routes = AhoyDashboard.routes

      expect(routes.visitors_user_path(7)).to eq("/telemetry/visitors/users/7")
      expect(routes.visitor_path("laptop")).to eq("/telemetry/visitors/laptop")
      expect(routes.visitors_visit_path("visit-in")).to eq("/telemetry/visitors/visits/visit-in")
    end
  end

  describe "without access" do
    around do |example|
      permissions = AhoyDashboard.config.authorize_action
      example.run
    ensure
      AhoyDashboard.config.authorize_action = permissions
    end

    paths = %w[
      /telemetry/visitors
      /telemetry/visitors/laptop
      /telemetry/visitors/users/7
      /telemetry/visitors/visits/visit-in
      /telemetry/visitors/lookup?q=7
    ].freeze

    it "is a 404 for a signed in user who isn't an admin" do
      user = create(:user)

      paths.each do |path|
        sign_in user
        get path
        expect(response).to have_http_status(:not_found), "#{path} answered #{response.status}"
      end
    end

    it "is a 404 when the host refuses read access" do
      AhoyDashboard.config.authorize_action = ->(_controller, permission) { permission != :read }
      admin = create(:user, :admin)

      paths.each do |path|
        sign_in admin
        get path
        expect(response).to have_http_status(:not_found), "#{path} answered #{response.status}"
      end
    end

    it "sends a signed out visitor to sign in" do
      paths.each do |path|
        get path
        expect(response).to redirect_to("/users/sign_in"), "#{path} answered #{response.status}"
      end
    end
  end
end
