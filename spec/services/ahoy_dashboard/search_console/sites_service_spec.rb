require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::SitesService do
  let(:account) { create(:dash_google_account, access_token: "good", expires_at: 30.minutes.from_now) }

  before { search_console_enabled! }

  it "sends the access token as a bearer credential" do
    stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" } ])

    described_class.call(account: account)

    expect(a_request(:get, AhoyDashboard::SearchConsole::SITES_URL)
      .with(headers: { "Authorization" => "Bearer good" })).to have_been_made
  end

  it "drops properties this account has not verified" do
    stub_sites([
      { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" },
      { "siteUrl" => "https://other.example/", "permissionLevel" => "siteUnverifiedUser" }
    ])

    expect(described_class.call(account: account).map(&:url)).to eq([ "sc-domain:example.com" ])
  end

  it "keeps restricted and full users, which can still read search data" do
    stub_sites([
      { "siteUrl" => "https://a.example/", "permissionLevel" => "siteFullUser" },
      { "siteUrl" => "https://b.example/", "permissionLevel" => "siteRestrictedUser" }
    ])

    expect(described_class.call(account: account).size).to eq(2)
  end

  it "keeps a domain property's identifier exactly as google sent it, and labels it without the prefix" do
    stub_sites([ { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" } ])

    site = described_class.call(account: account).first

    expect(site.url).to eq("sc-domain:example.com")
    expect(site.label).to eq("example.com")
    expect(site).to be_domain
  end

  it "puts domain properties first" do
    stub_sites([
      { "siteUrl" => "https://example.com/", "permissionLevel" => "siteOwner" },
      { "siteUrl" => "sc-domain:example.com", "permissionLevel" => "siteOwner" }
    ])

    expect(described_class.call(account: account).map(&:url))
      .to eq([ "sc-domain:example.com", "https://example.com/" ])
  end

  it "is empty when google lists nothing" do
    stub_sites(body: {})

    expect(described_class.call(account: account)).to eq([])
  end

  it "raises an auth error when the token is refused" do
    stub_sites(status: 401, body: { "error" => { "code" => 401, "message" => "Invalid Credentials" } })

    expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
  end

  it "raises a quota error rather than a plain failure" do
    stub_sites(status: 403, body: {
      "error" => { "code" => 403, "message" => "Quota exceeded", "errors" => [ { "reason" => "quotaExceeded" } ] }
    })

    expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::QuotaError)
  end
end
