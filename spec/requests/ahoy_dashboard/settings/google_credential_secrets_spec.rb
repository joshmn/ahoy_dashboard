require "rails_helper"

RSpec.describe "Dashboard Google OAuth client removal", type: :request do
  def store_secret
    store!(client_id: "id")
  end

  def store!(**values)
    AhoyDashboard::Credential.fetch(AhoyDashboard::SearchConsole::CREDENTIAL_NAME).tap do |credential|
      credential.update!(credentials: values)
    end
  end

  def stored
    AhoyDashboard::SearchConsole.credential
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a stored secret removal",
                     secret_path: "/telemetry/settings/google_credential/secrets/client_id",
                     confirm_path: "/telemetry/settings/google_connection?remove=client_id",
                     edit_path: "/telemetry/settings/google_connection",
                     word: "value", nothing: "There was no client ID stored.", model: AhoyDashboard::Credential,
                     unknown: {
                       "anything that is not the client ID or secret" => "/telemetry/settings/google_credential/secrets/refresh_token"
                     }


    it "offers Remove beside each stored value" do
      store!(client_id: "id")

      get "/telemetry/settings/google_connection"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("a[aria-label='Remove the stored client ID']")["href"])
        .to eq("/telemetry/settings/google_connection?remove=client_id#remove-secret")
      expect(document.at_css("a[aria-label='Remove the stored client secret']")).to be_nil
    end

    it "shows the stored client ID and never the secret, both posted at the top level" do
      store!(client_id: "id", client_secret: "secret")

      get "/telemetry/settings/google_connection"

      document = Nokogiri::HTML5(response.body)
      client_id = document.at_css("input[name='google_credential[client_id]']")
      client_secret = document.at_css("input[name='google_credential[client_secret]']")
      expect(client_id.attributes.slice("type", "value", "id").transform_values(&:value))
        .to eq("type" => "text", "value" => "id", "id" => "google_credential_client_id")
      expect(client_secret["type"]).to eq("password")
      expect(client_secret["value"]).to be_nil
      expect(document.at_css("#google_credential_client_id_hint").text).to eq("Stored.")
      expect(document.at_css("#google_credential_client_secret_hint").text)
        .to eq(AhoyDashboard::Settings::StoredSecretPresenter::STORED_HINT)
    end

    it "asks first, and says syncing stops while Google stays connected" do
      store!(client_id: "id", client_secret: "secret")
      create(:dash_google_account)

      get "/telemetry/settings/google_connection", params: { remove: "client_secret" }

      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored client secret? Syncing stops until one is saved again. The Google connection stays.")
    end

    it "says Google cannot be connected when nothing is connected yet" do
      store!(client_id: "id")

      get "/telemetry/settings/google_connection", params: { remove: "client_id" }

      expect(response.body).to include("Google cannot be connected until one is saved again.")
    end

    it "deletes one value, keeps the other and the row, and leaves the connection alone" do
      store!(client_id: "id", client_secret: "secret")
      create(:dash_google_account)

      delete "/telemetry/settings/google_credential/secrets/client_secret"

      expect(response).to redirect_to("/telemetry/settings/google_connection")
      expect(flash[:notice]).to eq("Client secret removed.")
      expect(stored.credentials).to eq(client_id: "id")
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
  end
end
