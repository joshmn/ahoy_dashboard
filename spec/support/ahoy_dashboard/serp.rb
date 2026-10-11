require_relative "switches"

module SerpFixtures
  FIXTURE_ROOT = Pathname(__dir__).join("serp/fixtures")
  API_KEY = "serpapi-test-key".freeze

  def serp_settings(**values, &block)
    with_ahoy_dashboard_settings(:serp, **values, &block)
  end

  # Off in test, the same posture as search console, so a spec that wants the
  # tracking to actually run has to say so.
  def serp_enabled!(provider: :fake)
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Serp).to receive(:provider) { AhoyDashboard::Serp.record&.name&.to_sym || provider.to_sym }
  end

  def serpapi_configured!(api_key: API_KEY)
    allow(AhoyDashboard::Serp).to receive(:credential).and_call_original
    allow(AhoyDashboard::Serp).to receive(:credential).with(:serpapi, :api_key).and_return(api_key)
  end

  def serp_fixture(name)
    JSON.parse(FIXTURE_ROOT.join("#{name}.json").read)
  end

  def serpapi_body(organic: [], ai_overview: nil, search_id: "test-search-id", status: "Success")
    {
      "search_metadata" => { "id" => search_id, "status" => status },
      "organic_results" => organic,
      "ai_overview" => ai_overview
    }.compact
  end

  def serpapi_organic(*links, from: 1)
    links.each_with_index.map do |link, index|
      { "position" => from + index, "link" => link, "title" => "Result #{from + index}",
        "snippet" => "A snippet." }
    end
  end

  def dataforseo_configured!(login: "login", password: "password")
    allow(AhoyDashboard::Serp).to receive(:credential).and_call_original
    allow(AhoyDashboard::Serp).to receive(:credential).with(:dataforseo, :login).and_return(login)
    allow(AhoyDashboard::Serp).to receive(:credential).with(:dataforseo, :password).and_return(password)
  end

  def searchapi_configured!(api_key: API_KEY)
    allow(AhoyDashboard::Serp).to receive(:credential).and_call_original
    allow(AhoyDashboard::Serp).to receive(:credential).with(:searchapi, :api_key).and_return(api_key)
  end

  def dataforseo_body(items: [], task_status: 20_000, status: 20_000, id: "task-1")
    {
      "status_code" => status, "status_message" => "Ok.", "cost" => 0.0012,
      "tasks" => [ { "id" => id, "status_code" => task_status, "status_message" => "Ok.",
                     "result" => [ { "items" => items } ] } ]
    }
  end

  def stub_dataforseo(body:, status: 200)
    stub_request(:post, AhoyDashboard::Serp::Adapters::DataForSeoAdapter::ENDPOINT)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_searchapi(body:, status: 200)
    stub_request(:get, %r{searchapi\.io/api/v1/search})
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_serpapi(body:, status: 200)
    stub_request(:get, %r{serpapi\.com/search\.json})
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure { |config| config.include SerpFixtures }
