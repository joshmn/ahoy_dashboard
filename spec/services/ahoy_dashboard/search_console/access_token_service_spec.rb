require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::AccessTokenService do
  before { search_console_enabled! }

  it "hands back a token that is still good without calling google" do
    account = create(:dash_google_account, access_token: "good", expires_at: 30.minutes.from_now)

    expect(described_class.call(account: account)).to eq("good")
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it "refreshes one that has expired" do
    account = create(:dash_google_account, :expired, access_token: "stale")
    stub_token

    expect(described_class.call(account: account)).to eq("fresh-access")
  end

  it "refreshes one that is about to expire" do
    account = create(:dash_google_account, access_token: "stale", expires_at: 30.seconds.from_now)
    stub_token

    expect(described_class.call(account: account)).to eq("fresh-access")
  end

  it "refreshes when the stored token will not decrypt" do
    account = create(:dash_google_account, expires_at: 30.minutes.from_now)
    account.update_columns(access_token: "not an envelope")
    stub_token

    expect(described_class.call(account: account.reload)).to eq("fresh-access")
  end

  it "refuses when nothing is connected" do
    expect { described_class.call(account: nil) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it "falls back to the one stored account" do
    create(:dash_google_account, access_token: "good", expires_at: 30.minutes.from_now)

    expect(described_class.call).to eq("good")
  end
end
