require "rails_helper"

RSpec.describe "Dashboard assets", type: :request do
  let(:build) { AhoyDashboard::Assets.build }
  let(:script) { AhoyDashboard::Assets::SCRIPT }

  it "sends a signed out visitor to sign in" do
    get "/telemetry/assets/#{build}/#{script}"

    expect(response).to redirect_to("/users/sign_in")
  end

  it "is a 404 for a signed in visitor who is not an admin" do
    sign_in create(:user)

    get "/telemetry/assets/#{build}/#{script}"

    expect(response).to have_http_status(:not_found)
  end

  context "as an admin" do
    before { sign_in create(:user, :admin) }

    it "serves the bundled script" do
      get "/telemetry/assets/#{build}/#{script}"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      # Every controller the entry point registers is in the one file now.
      expect(response.body).to include("dash--chart", "dash--realtime", "dash--palette")
    end

    it "serves the sourcemap beside it" do
      get "/telemetry/assets/#{build}/#{AhoyDashboard::Assets::SOURCEMAP}"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "serves the built stylesheet" do
      get "/telemetry/assets/#{build}/#{AhoyDashboard::Assets::STYLESHEET}"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/css")
    end

    # The stylesheet asks for these by relative url, so they have to answer on
    # the same build path the stylesheet was served from.
    it "serves the fonts the stylesheet asks for" do
      get "/telemetry/assets/#{build}/fonts/inter-latin-wght-normal.woff2"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("font/woff2")
    end

    it "caches the current build and nothing else" do
      get "/telemetry/assets/#{build}/#{script}"

      expect(response.headers["Cache-Control"]).to include("immutable")

      get "/telemetry/assets/deadbeefdeadbeef/#{script}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-cache")
    end

    # The module tree is build input now, not something anybody can fetch.
    it "no longer serves the unbundled modules" do
      get "/telemetry/assets/#{build}/runtime/frames.js"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a path that climbs out of the asset tree" do
      get "/telemetry/assets/#{build}/fonts/../../../config/database.yml"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a file that is not there" do
      get "/telemetry/assets/#{build}/nope.js"

      expect(response).to have_http_status(:not_found)
    end
  end
end
