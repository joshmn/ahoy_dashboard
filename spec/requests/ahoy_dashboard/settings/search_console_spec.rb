require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe "Dashboard Search Console settings", type: :request do
  let(:token_url) { AhoyDashboard::SearchConsole::TOKEN_URL }
  let(:sites_url) { AhoyDashboard::SearchConsole::SITES_URL }

  def connect!(**attributes)
    create(:dash_google_account, **attributes)
  end

  # The state is made in the session the redirect started in, so the spec walks
  # the same path a browser does rather than poking at the session.
  def start_authorization!
    get "/telemetry/settings/google_authorization/new"

    URI.decode_www_form(URI(response.location).query).to_h["state"]
  end

  describe "gating" do
    it "sends a signed out visitor to sign in from every entry point" do
      [ "/telemetry/settings/google_connection",
        "/telemetry/settings/google_authorization/new",
        "/telemetry/settings/google_callback",
        "/telemetry/settings/search_console_property/edit" ].each do |path|
        get path

        expect(response).to redirect_to("/users/sign_in"), "expected #{path} to bounce a signed out visitor"
      end
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/google_connection"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a disconnect from somebody who is not an admin" do
      sign_in create(:user)
      connect!

      delete "/telemetry/settings/google_connection"

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::GoogleAccount.count).to eq(1)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "the connection page" do
      it "says nothing is configured when there is no client id" do
        allow(AhoyDashboard::SearchConsole).to receive_messages(client_id: nil, client_secret: nil)

        get "/telemetry/settings/google_connection"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No client ID or secret set")
      end

      it "warns that a testing project hands out tokens that die in a week" do
        get "/telemetry/settings/google_connection"

        expect(response.body).to include("seven days")
        expect(response.body).to include("In production")
      end

      it "says how often it syncs and that google lags" do
        get "/telemetry/settings/google_connection"

        expect(response.body).to include("Syncs nightly", "Google lags")
      end

      describe "with no host set anywhere" do
        before do
          allow(AhoyDashboard::SearchConsole).to receive_messages(
            enabled?: true, client_id: SearchConsoleFixtures::CLIENT_ID, client_secret: SearchConsoleFixtures::CLIENT_SECRET
          )
          AhoyDashboard::Preferences.clear(:site, :host, :canonical_host)
        end

        it "renders, and says the host is what is missing instead of raising" do
          get "/telemetry/settings/google_connection"

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("There is no URL to add yet.", "The dashboard has no host set")

          document = Nokogiri::HTML5(response.body)
          connect = document.css("button[disabled]").find { |node| node.text.strip == "Connect Google account" }
          expect(connect).to be_present
        end

        it "refuses to start a sign-in google could not send back" do
          get "/telemetry/settings/google_authorization/new"

          expect(response).to redirect_to("/telemetry/settings/google_connection")
          expect(flash[:alert]).to eq(AhoyDashboard::SearchConsole::NO_HOST_MESSAGE)
        end
      end

      describe "with the integration switched off" do
        before do
          allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false, client_id: "cid", client_secret: "secret")
        end

        it "does not offer Sync now or Reach back a month, and says why" do
          connect!(property_uri: "sc-domain:example.com")

          get "/telemetry/settings/google_connection"

          document = Nokogiri::HTML5(response.body)
          sync = document.css("button[disabled][aria-describedby]").find { |node| node.text.strip == "Sync now" }
          backfill = document.css("button[disabled]").find { |node| node.text.include?("Reach back a month") }

          expect(sync).to be_present
          expect(document.at_css("##{sync['aria-describedby']}").text).to include("Search Console is off.")
          expect(backfill.text).to include("Search Console is off.")
          expect(document.at_css("form[action='/telemetry/settings/search_console_sync']")).to be_nil
          expect(document.at_css("form[action='/telemetry/settings/search_console_backfill']")).to be_nil
        end
      end

      describe "with the integration on" do
        before { search_console_enabled! }

        it "offers a connect button when nothing is connected" do
          get "/telemetry/settings/google_connection"

          expect(response.body).to include("Connect Google")
          expect(response.body).to include("Not connected")
        end

        it "shows the property and offers a reconnect once connected" do
          connect!(property_uri: "sc-domain:example.com")

          get "/telemetry/settings/google_connection"

          document = Nokogiri::HTML5(response.body)
          badges = document.css(".gsc-name .badge").map { |badge| badge.text.strip }

          expect(badges).to include("Active", "Domain property")
          expect(response.body).to include("example.com")
          expect(response.body).to include("Reconnect")
        end

        it "shows the last error when there is one" do
          connect!.record_error!("Google refused the saved refresh token.")

          get "/telemetry/settings/google_connection"

          expect(response.body).to include("Google refused the saved refresh token.")
        end

        it "reports what has been pulled" do
          create(:dash_search_console_total, date: Date.new(2026, 8, 5), clicks: 40, impressions: 900)
          create(:dash_search_console_row, date: Date.new(2026, 8, 5))

          get "/telemetry/settings/google_connection"

          document = Nokogiri::HTML5(response.body)
          stats = document.css("[aria-label='What has been pulled'] > *").map { |stat| stat.text.split.join(" ") }

          expect(stats).to include("Day 1")
          expect(stats).to include("Impressions 900")
        end

        it "offers the backfill and says how far back it has got" do
          connect!(property_uri: "sc-domain:example.com", backfilled_to: Date.new(2026, 3, 1))

          get "/telemetry/settings/google_connection"

          expect(response.body).to include("Reach back a month")
          expect(response.body).to include("Mar 1")
        end

        it "says the backfill is finished once it has reached what google still serves" do
          connect!(property_uri: "sc-domain:example.com",
                   backfilled_to: AhoyDashboard::SearchConsole.earliest_available_date - 1)

          get "/telemetry/settings/google_connection"

          document = Nokogiri::HTML5(response.body)
          backfill = document.css("button[disabled]").find { |node| node.text.include?("Reach back a month") }

          expect(backfill).to be_present
          expect(backfill.text).to include("Everything Google still keeps is already here.")
          expect(document.at_css("form[action='/telemetry/settings/search_console_backfill']")).to be_nil
          expect(response.body).to include("History is complete")
        end

        # The link passes confirm=1 and the page reads it. It used to render the
        # link and never the step it asks for, so disconnecting did nothing.
        it "asks before disconnecting" do
          connect!(property_uri: "sc-domain:example.com")

          get "/telemetry/settings/google_connection", params: { confirm: 1 }

          expect(response.body).to include("Disconnect Google? The rows already pulled stay put.")
        end
      end
    end

    describe "starting the authorization" do
      it "refuses to send anybody to google with no client credentials" do
        get "/telemetry/settings/google_authorization/new"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to eq("Add the OAuth client ID and secret first.")
      end

      it "says it is switched off, rather than missing a client, when the client is saved" do
        store_google_client

        get "/telemetry/settings/google_authorization/new"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to eq("Search Console is off. Turn it on under Settings, Features.")
      end

      it "redirects to google asking for offline access, and remembers the state" do
        search_console_enabled!

        state = start_authorization!

        expect(response.location).to start_with(AhoyDashboard::SearchConsole::AUTH_URL)
        params = URI.decode_www_form(URI(response.location).query).to_h
        expect(params["access_type"]).to eq("offline")
        expect(params["prompt"]).to eq("consent")
        expect(params["scope"]).to eq(AhoyDashboard::SearchConsole::SCOPE)
        expect(state).to be_present
      end

      it "makes a different state every time" do
        search_console_enabled!

        expect(start_authorization!).not_to eq(start_authorization!)
      end
    end

    describe "the callback" do
      before { search_console_enabled! }

      it "refuses a state that does not match, and asks google for nothing" do
        get "/telemetry/settings/google_callback", params: { code: "abc", state: "made-up" }

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to include("did not come back from a sign-in this browser started")
        expect(a_request(:post, token_url)).not_to have_been_made
        expect(AhoyDashboard::GoogleAccount.count).to eq(0)
      end

      it "refuses a callback carrying no state at all" do
        get "/telemetry/settings/google_callback", params: { code: "abc" }

        expect(flash[:alert]).to be_present
        expect(a_request(:post, token_url)).not_to have_been_made
      end

      it "refuses the same state twice, because it is spent on first use" do
        state = start_authorization!
        stub_token(body: token_body("refresh_token" => "rt-1"))

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }
        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(flash[:alert]).to include("did not come back")
      end

      it "stores the tokens and sends the admin on to pick a property" do
        state = start_authorization!
        stub_token(body: token_body("refresh_token" => "rt-1"))

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(response).to redirect_to("/telemetry/settings/search_console_property/edit")
        expect(flash[:notice]).to eq("Google is connected.")

        account = AhoyDashboard::GoogleAccount.current
        expect(account.refresh_token).to eq("rt-1")
        expect(account.access_token).to eq("fresh-access")
        expect(account.connected_at).to be_present
      end

      it "goes back to the status page when a property is already picked" do
        connect!(property_uri: "sc-domain:example.com")
        state = start_authorization!
        stub_token(body: token_body("refresh_token" => "rt-2"))

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(AhoyDashboard::GoogleAccount.count).to eq(1)
        expect(AhoyDashboard::GoogleAccount.current.property_uri).to eq("sc-domain:example.com")
      end

      it "keeps the working refresh token when a reconnect comes back without one" do
        connect!(refresh_token: "rt-1", property_uri: "sc-domain:example.com")
        state = start_authorization!
        stub_token(body: token_body)

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(AhoyDashboard::GoogleAccount.current.refresh_token).to eq("rt-1")
      end

      it "says so plainly when the operator turned the request down" do
        state = start_authorization!

        get "/telemetry/settings/google_callback", params: { error: "access_denied", state: state }

        expect(flash[:alert]).to include("turned the request down")
        expect(a_request(:post, token_url)).not_to have_been_made
      end

      it "reports a refusal from google rather than a blank page" do
        state = start_authorization!
        stub_token(status: 400, body: { "error" => "invalid_grant" })

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to be_present
        expect(AhoyDashboard::GoogleAccount.count).to eq(0)
      end

      it "refuses a first connection that came back with no refresh token" do
        state = start_authorization!
        stub_token(body: token_body)

        get "/telemetry/settings/google_callback", params: { code: "abc", state: state }

        expect(flash[:alert]).to include("no refresh token")
      end
    end

    describe "the property picker" do
      before { search_console_enabled! }

      it "sends anybody without a connection back to the status page" do
        get "/telemetry/settings/search_console_property/edit"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to include("Connect a Google account")
      end

      it "lists what google says the account can read" do
        connect!(access_token: "good", expires_at: 30.minutes.from_now)
        stub_sites([
          { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" },
          { "siteUrl" => "https://nope.example/", "permissionLevel" => "siteUnverifiedUser" }
        ])

        get "/telemetry/settings/search_console_property/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("sc-domain:example.com")
        expect(response.body).not_to include("nope.example")
      end

      it "explains itself when google will not answer" do
        connect!(access_token: "good", expires_at: 30.minutes.from_now)
        stub_request(:get, sites_url).to_timeout

        get "/telemetry/settings/search_console_property/edit"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to include("not available right now")
      end

      it "saves a property google offered" do
        account = connect!(access_token: "good", expires_at: 30.minutes.from_now)
        stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" } ])

        patch "/telemetry/settings/search_console_property",
              params: { property: { property_uri: "sc-domain:example.com" } }

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(account.reload.property_uri).to eq("sc-domain:example.com")
      end

      it "refuses a property google did not offer" do
        account = connect!(access_token: "good", expires_at: 30.minutes.from_now)
        stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" } ])

        patch "/telemetry/settings/search_console_property",
              params: { property: { property_uri: "sc-domain:someone-else.com" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("not one Google says this account can read")
        expect(account.reload.property_uri).to be_nil
      end

      it "refuses a blank choice" do
        connect!(access_token: "good", expires_at: 30.minutes.from_now)
        stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" } ])

        patch "/telemetry/settings/search_console_property", params: { property: { property_uri: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Pick the property")
      end
    end

    describe "switching the property" do
      before { search_console_enabled! }

      let!(:account) do
        connect!(access_token: "good", expires_at: 30.minutes.from_now, property_uri: "sc-domain:example.com",
                 backfilled_to: Date.current - 300, synced_at: 1.hour.ago)
      end

      before do
        stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" },
                     { "siteUrl" => "sc-domain:other.com", "permissionLevel" => "siteOwner" } ])
        create(:dash_search_console_total, date: Date.current - 5)
        create(:dash_search_console_total, date: Date.current - 4)
        create(:dash_search_console_keyword, date: Date.current - 5)
        create(:dash_search_console_row, date: Date.current - 5)
      end

      it "warns on the picker that switching deletes what is stored" do
        get "/telemetry/settings/search_console_property/edit"

        expect(response.body).to include("Switching deletes what is stored.", "2 days", "belong to example.com")
      end

      it "removes the old property's rows and starts the history over" do
        patch "/telemetry/settings/search_console_property",
              params: { property: { property_uri: "sc-domain:other.com" } }

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:notice]).to include("Removed 2 days pulled for the old property")
        expect(AhoyDashboard::SearchConsoleTotal.count).to eq(0)
        expect(AhoyDashboard::SearchConsoleKeyword.count).to eq(0)
        expect(AhoyDashboard::SearchConsoleRow.count).to eq(0)

        account.reload
        expect(account.property_uri).to eq("sc-domain:other.com")
        expect(account.backfilled_to).to be_nil
        expect(account.synced_at).to be_nil
        expect(AhoyDashboard::SearchConsole.stored_property).to eq("sc-domain:other.com")
      end

      it "keeps everything when the same property is saved again" do
        patch "/telemetry/settings/search_console_property",
              params: { property: { property_uri: "sc-domain:example.com" } }

        expect(flash[:notice]).to eq("Search Console property saved.")
        expect(AhoyDashboard::SearchConsoleTotal.count).to eq(2)
        expect(account.reload.backfilled_to).to eq(Date.current - 300)
      end

      it "still knows whose rows they are after a disconnect and a reconnect" do
        AhoyDashboard::SearchConsole.store_property!("sc-domain:example.com")
        account.update_columns(property_uri: nil)

        patch "/telemetry/settings/search_console_property",
              params: { property: { property_uri: "sc-domain:other.com" } }

        expect(AhoyDashboard::SearchConsoleTotal.count).to eq(0)
      end
    end

    describe "the manual pull" do
      it "refuses while search console is switched off, and queues nothing" do
        allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false, client_id: "cid", client_secret: "secret")
        connect!(property_uri: "sc-domain:example.com")

        expect {
          post "/telemetry/settings/search_console_sync"
        }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::IngestJob)

        expect(flash[:alert]).to eq(AhoyDashboard::SearchConsole::OFF_MESSAGE)
        expect(flash[:notice]).to be_nil
      end

      it "says the credentials are missing when that is why it is off" do
        allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false, client_id: nil, client_secret: nil)
        connect!(property_uri: "sc-domain:example.com")

        post "/telemetry/settings/search_console_sync"

        expect(flash[:alert]).to eq(AhoyDashboard::SearchConsole::MISSING_CREDENTIALS_MESSAGE)
      end

      it "refuses without a connection" do
        search_console_enabled!
        post "/telemetry/settings/search_console_sync"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(flash[:alert]).to eq("Connect Google first.")
      end

      it "refuses without a property" do
        search_console_enabled!
        connect!

        post "/telemetry/settings/search_console_sync"

        expect(flash[:alert]).to eq("Pick a property first.")
      end

      it "enqueues the same job the nightly run uses" do
        search_console_enabled!
        connect!(property_uri: "sc-domain:example.com")

        expect {
          post "/telemetry/settings/search_console_sync"
        }.to have_enqueued_job(AhoyDashboard::SearchConsole::IngestJob).on_queue("low")

        expect(flash[:notice]).to include("last week")
      end
    end

    describe "disconnecting" do
      before { search_console_enabled! }

      it "tells google to forget the grant and drops the row" do
        connect!(refresh_token: "rt-1")
        revoke = stub_request(:post, AhoyDashboard::SearchConsole::REVOKE_URL).to_return(status: 200)

        delete "/telemetry/settings/google_connection"

        expect(response).to redirect_to("/telemetry/settings/google_connection")
        expect(AhoyDashboard::GoogleAccount.count).to eq(0)
        expect(revoke.with(body: { token: "rt-1" })).to have_been_made
      end

      # Disconnecting has to work when the token is already dead, which is one of
      # the reasons somebody would be doing it.
      it "drops the row even when google refuses the revoke" do
        connect!
        stub_request(:post, AhoyDashboard::SearchConsole::REVOKE_URL).to_return(status: 400, body: "{}")

        delete "/telemetry/settings/google_connection"

        expect(AhoyDashboard::GoogleAccount.count).to eq(0)
        expect(flash[:notice]).to eq("Google is disconnected.")
      end

      it "keeps the rows already pulled" do
        connect!
        create(:dash_search_console_row)
        stub_request(:post, AhoyDashboard::SearchConsole::REVOKE_URL).to_return(status: 200)

        delete "/telemetry/settings/google_connection"

        expect(AhoyDashboard::SearchConsoleRow.count).to eq(1)
      end

      it "says there was nothing to disconnect" do
        delete "/telemetry/settings/google_connection"

        expect(flash[:alert]).to eq("There was nothing connected.")
      end
    end
  end
end
