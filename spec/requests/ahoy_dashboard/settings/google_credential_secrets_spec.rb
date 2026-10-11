require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe "Dashboard Google OAuth client removal", type: :request do
  include SearchConsoleFixtures

  def store!(**values)
    AhoyDashboard::Credential.fetch(AhoyDashboard::SearchConsole::CREDENTIAL_NAME).tap do |credential|
      credential.update!(values: values)
    end
  end

  def stored
    AhoyDashboard::SearchConsole.credential
  end

  describe "gating" do
    it "is a 404 for a signed in visitor who is not an admin, and keeps the secret" do
      store!(client_id: "id", client_secret: "secret")
      sign_in create(:user)

      delete "/telemetry/settings/google_credential/secrets/client_secret"

      expect(response).to have_http_status(:not_found)
      expect(stored.value(:client_secret)).to eq("secret")
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "offers Remove beside each stored value" do
      store!(client_id: "id")

      get "/telemetry/settings/google_connection"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("a[aria-label='Remove the stored client ID']")["href"])
        .to eq("/telemetry/settings/google_connection?remove=client_id#remove-secret")
      expect(document.at_css("a[aria-label='Remove the stored client secret']")).to be_nil
    end

    it "asks first, and says syncing stops while Google stays connected" do
      store!(client_id: "id", client_secret: "secret")
      create(:dash_google_account)

      get "/telemetry/settings/google_connection", params: { remove: "client_secret" }

      expect(Nokogiri::HTML5(response.body).at_css("#remove-secret").text)
        .to include("Remove the stored client secret? Syncing stops until one is saved again. The Google connection stays.")
    end

    it "says Google cannot be connected when nothing is connected yet" do
      store!(client_id: "id")

      get "/telemetry/settings/google_connection", params: { remove: "client_id" }

      expect(response.body).to include("Google cannot be connected until one is saved again.")
    end

    it "never offers a value from anywhere else to take over" do
      store!(client_id: "id")

      get "/telemetry/settings/google_connection", params: { remove: "client_id" }

      expect(response.body).not_to include("initializer", "used instead")
    end

    it "deletes one value, keeps the other and the row, and leaves the connection alone" do
      store!(client_id: "id", client_secret: "secret")
      create(:dash_google_account)

      delete "/telemetry/settings/google_credential/secrets/client_secret"

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:notice]).to eq("Client secret removed.")
      expect(stored.values).to eq(client_id: "id")
      expect(AhoyDashboard::GoogleAccount.count).to eq(1)
      expect(AhoyDashboard::SearchConsole.client_secret).to be_nil
    end

    it "keeps the row with nothing in it once both are gone" do
      store!(client_id: "id")

      delete "/telemetry/settings/google_credential/secrets/client_id"

      expect(AhoyDashboard::Credential.count).to eq(1)
      expect(stored.read_attribute(:secrets)).to be_nil
    end

    it "reads Nothing stored once the stored value is gone, whatever the environment holds" do
      store!(client_id: "stored-id")
      stub_const("ENV", ENV.to_h.merge("SEARCH_CONSOLE_CLIENT_ID" => "from-env"))

      delete "/telemetry/settings/google_credential/secrets/client_id"
      get "/telemetry/settings/google_connection"

      expect(AhoyDashboard::SearchConsole.client_id).to be_nil
      expect(response.body).to include("Nothing stored.")
    end

    it "says there was nothing to remove" do
      delete "/telemetry/settings/google_credential/secrets/client_id"

      expect(flash[:alert]).to eq("There was no client ID stored.")
    end

    it "is a 404 for anything that is not the client ID or secret" do
      delete "/telemetry/settings/google_credential/secrets/refresh_token"

      expect(response).to have_http_status(:not_found)
    end
  end
end
