module SearchConsoleFixtures
  CLIENT_ID = "client-id".freeze
  CLIENT_SECRET = "client-secret".freeze
  REDIRECT_URI = "https://example.com/telemetry/settings/google_callback".freeze

  def search_console_enabled!
    allow(AhoyDashboard::SearchConsole).to receive_messages(
      enabled?: true, client_id: CLIENT_ID, client_secret: CLIENT_SECRET, redirect_uri: REDIRECT_URI
    )
  end

  def store_google_client(client_id: CLIENT_ID, client_secret: CLIENT_SECRET)
    credential = AhoyDashboard::Credential.fetch(AhoyDashboard::SearchConsole::CREDENTIAL_NAME)
    credential.credentials = { client_id: client_id, client_secret: client_secret }
    credential.save!
  end

  def search_console_disabled!
    allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false)
  end

  def search_console_switched_off!(**values)
    allow(AhoyDashboard::SearchConsole).to receive_messages(
      { enabled?: false, client_id: "cid", client_secret: "secret" }.merge(values)
    )
  end

  def token_url
    AhoyDashboard::SearchConsole::TOKEN_URL
  end

  def stub_token(body: nil, status: 200)
    stub_request(:post, token_url)
      .to_return(status: status, body: (body || token_body).to_json, headers: json_headers)
  end

  def token_body(overrides = {})
    { "access_token" => "fresh-access", "expires_in" => 3599, "scope" => AhoyDashboard::SearchConsole::SCOPE,
      "token_type" => "Bearer" }.merge(overrides.transform_keys(&:to_s))
  end

  def stub_sites(entries = [], status: 200, body: nil)
    stub_request(:get, AhoyDashboard::SearchConsole::SITES_URL)
      .to_return(status: status, body: (body || { "siteEntry" => entries }).to_json, headers: json_headers)
  end

  def analytics_url(property_uri = "sc-domain:example.com")
    AhoyDashboard::SearchConsole.analytics_url(property_uri)
  end

  def stub_analytics(*row_sets)
    responses = (row_sets.empty? ? [ [] ] : row_sets).map do |rows|
      { status: 200, body: analytics_body(rows).to_json, headers: json_headers }
    end
    stub_request(:post, analytics_url).to_return(*responses)
  end

  def stub_analytics_refusal(status, body: "{}")
    stub_request(:post, analytics_url).to_return(status: status, body: body, headers: json_headers)
  end

  def analytics_body(rows)
    {
      "rows" => rows.map do |keys, clicks, impressions, ctr, position|
        { "keys" => Array(keys), "clicks" => clicks.to_f, "impressions" => impressions.to_f,
          "ctr" => ctr.to_f, "position" => position.to_f }
      end,
      "responseAggregationType" => "byProperty"
    }
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end
end

RSpec.configure { |config| config.include SearchConsoleFixtures }

RSpec.shared_examples "a search console account job" do |name|
  it "does nothing with nothing connected" do
    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console #{name} skipped: search console is not configured")
    expect(AhoyDashboard::JobRun.for("search_console_#{name}").status).to eq("ok")
  end

  it "does nothing while the integration is off" do
    search_console_disabled!
    create(:dash_google_account, :with_property)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("search console #{name} skipped: search console is not configured")
  end

  describe "with a ready account" do
    before do
      create(:dash_google_account, :with_property)
      search_console_enabled!
    end

    it "fails the run when Google does not answer, so the jobs screen shows it" do
      stub_analytics_refusal(500)

      expect { described_class.perform_now }.to raise_error(AhoyDashboard::Job::Failed, /search console returned 500/)

      expect(AhoyDashboard::JobRun.for("search_console_#{name}"))
        .to have_attributes(status: "failed", last_error: a_string_starting_with("AhoyDashboard::Job::Failed"))
    end
  end
end
