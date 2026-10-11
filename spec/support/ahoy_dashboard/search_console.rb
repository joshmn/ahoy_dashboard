require_relative "switches"

module SearchConsoleFixtures
  CLIENT_ID = "client-id".freeze
  CLIENT_SECRET = "client-secret".freeze
  REDIRECT_URI = "https://example.com/telemetry/settings/google_callback".freeze

  # The integration is off in test, so every spec that wants it has to say so.
  def search_console_enabled!
    allow(AhoyDashboard::SearchConsole).to receive_messages(
      enabled?: true, client_id: CLIENT_ID, client_secret: CLIENT_SECRET, redirect_uri: REDIRECT_URI
    )
  end

  def store_google_client(client_id: CLIENT_ID, client_secret: CLIENT_SECRET)
    credential = AhoyDashboard::Credential.fetch(AhoyDashboard::SearchConsole::CREDENTIAL_NAME)
    credential.values = { client_id: client_id, client_secret: client_secret }
    credential.save!
  end

  def search_console_disabled!
    allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false)
  end

  def search_console_settings(**values, &block)
    with_ahoy_dashboard_settings(:search_console, **values, &block)
  end

  def stub_token(body: nil, status: 200)
    stub_request(:post, AhoyDashboard::SearchConsole::TOKEN_URL)
      .to_return(status: status, body: (body || token_body).to_json, headers: json_headers)
  end

  def token_body(overrides = {})
    { "access_token" => "fresh-access", "expires_in" => 3599, "scope" => AhoyDashboard::SearchConsole::SCOPE,
      "token_type" => "Bearer" }.merge(overrides.transform_keys(&:to_s))
  end

  def stub_sites(entries, status: 200)
    stub_request(:get, AhoyDashboard::SearchConsole::SITES_URL)
      .to_return(status: status, body: { "siteEntry" => entries }.to_json, headers: json_headers)
  end

  def analytics_url(property_uri = "sc-domain:example.com")
    AhoyDashboard::SearchConsole.analytics_url(property_uri)
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

RSpec.configure do |config|
  config.include SearchConsoleFixtures
  config.include ActiveSupport::Testing::TimeHelpers
end
