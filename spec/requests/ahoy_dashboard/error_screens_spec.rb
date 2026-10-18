require "rails_helper"

RSpec.describe "Dashboard error screens", type: :request do
  def with_error_screens(setting)
    before = AhoyDashboard.config.error_screens
    exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
    AhoyDashboard.config.error_screens = setting
    unless setting
      Rails.application.env_config["action_dispatch.show_exceptions"] = Rails.gem_version >= Gem::Version.new("7.1") ? :none : false
    end
    yield
  ensure
    AhoyDashboard.config.error_screens = before
    Rails.application.env_config["action_dispatch.show_exceptions"] = exceptions
  end

  def break_realtime
    allow(AhoyDashboard::RealtimeQuery).to receive(:snapshot).and_raise(ArgumentError, "the query fell over")
  end

  describe "a screen that raises" do
    before { sign_in create(:user, :admin) }

    it "renders the failure inside the dashboard rather than handing it to the host" do
      break_realtime

      with_error_screens(true) { get "/telemetry/realtime" }

      expect(response).to have_http_status(:internal_server_error)
      expect(document.at_css("a.live")["href"]).to eq("/telemetry/realtime")
      expect(document.at_css("h1").text).to include("Realtime")
      expect(response.body).to include("ArgumentError")
      expect(response.body).to include(request.request_id)
      expect(response.body).not_to include("the query fell over")
    end

    it "offers the same address again and a way back" do
      break_realtime

      with_error_screens(true) { get "/telemetry/realtime" }

      links = document.css("main a").map { |link| [ link.text.strip, link["href"] ] }.to_h

      expect(links).to include("Try again" => "/telemetry/realtime", "Back to the dashboard" => "/telemetry/")
    end

    it "logs the error" do
      break_realtime
      allow(Rails.logger).to receive(:error).and_call_original

      with_error_screens(true) { get "/telemetry/realtime" }

      expect(Rails.logger).to have_received(:error).with(/ahoy_dashboard ArgumentError: the query fell over request/)
    end

    if Rails.respond_to?(:error)
      it "reports the error through the host's reporter" do
        break_realtime
        allow(Rails.error).to receive(:report)

        with_error_screens(true) { get "/telemetry/realtime" }

        options = if Rails.gem_version >= Gem::Version.new("7.1")
          hash_including(handled: true, source: "ahoy_dashboard", context: hash_including(action: "show"))
        else
          hash_including(handled: true, context: hash_including(action: "show", source: "ahoy_dashboard"))
        end
        expect(Rails.error).to have_received(:report).with(an_instance_of(ArgumentError), options)
      end
    end

    it "still raises where exceptions are meant to surface" do
      break_realtime

      with_error_screens(false) do
        expect { get "/telemetry/realtime" }.to raise_error(ArgumentError, "the query fell over")
      end
    end

    it "follows the host's own setting when nothing is configured" do
      break_realtime

      with_error_screens(nil) do
        expect { get "/telemetry/realtime" }.to raise_error(ArgumentError)
      end
    end

    it "answers a request for json with the status and no screen" do
      allow(AhoyDashboard::RealtimeQuery).to receive(:call).and_raise(ArgumentError, "the query fell over")

      with_error_screens(true) { get "/telemetry/realtime.json" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to be_blank
    end

    it "keeps an SEO screen inside the SEO shell" do
      allow(AhoyDashboard::Seo::SerpFeaturesQuery).to receive(:call).and_raise(TypeError, "no implicit conversion")

      with_error_screens(true) { get "/telemetry/seo/serp_feature" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("TypeError")
      expect(document.at_css("nav[aria-label='SEO pages']")).to be_present
    end
  end

  describe "a lazy frame that raises" do
    before { sign_in create(:user, :admin) }

    it "renders a compact error in the frame that asked, with a way to ask again" do
      allow(AhoyDashboard::BreakdownQuery).to receive(:call).and_raise(ArgumentError, "the query fell over")

      with_error_screens(true) do
        get "/telemetry/reports/sources", headers: { "Tm-Frame" => "dash_report_sources" }
      end

      frame = document.at_css("tm-frame#dash_report_sources")

      expect(response).to have_http_status(:internal_server_error)
      expect(frame).to be_present
      expect(frame.at_css("[role='alert']")).to be_present
      expect(frame.at_css("a")["href"]).to eq("/telemetry/reports/sources")
      expect(document.at_css("a.live")).to be_nil
    end

    it "will not echo a frame id that is not one" do
      allow(AhoyDashboard::BreakdownQuery).to receive(:call).and_raise(ArgumentError, "the query fell over")

      with_error_screens(true) do
        get "/telemetry/reports/sources", headers: { "Tm-Frame" => "\"><script>" }
      end

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).not_to include("\"><script>")
      expect(document.at_css("a.live")).to be_present
    end
  end

  describe "an address the dashboard does not have" do
    describe "as an admin" do
      before { sign_in create(:user, :admin) }

      it "renders the dashboard's own 404 for a path no route matches" do
        get "/telemetry/nothing/here"

        expect(response).to have_http_status(:not_found)
        expect(document.at_css("a.live")).to be_present
        expect(response.body).to include("No such screen")
        expect(response.body).to include("Back to the dashboard")
      end

      it "renders it for a report that does not exist" do
        get "/telemetry/reports/nope"

        expect(response).to have_http_status(:not_found)
        expect(document.at_css("a.live")).to be_present
        expect(response.body).to include("No such screen")
      end

      it "renders it for a record that does not exist" do
        get "/telemetry/chats/999999"

        expect(response).to have_http_status(:not_found)
        expect(document.at_css("a.live")).to be_present
      end

      it "renders it whatever the verb" do
        post "/telemetry/nothing/here"

        expect(response).to have_http_status(:not_found)
      end

      it "does not offer to try a missing address again" do
        get "/telemetry/nothing/here"

        expect(document.css("main a").map { |link| link.text.strip }).not_to include("Try again")
      end
    end
  end
end
