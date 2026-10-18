require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::RefreshTokenService do
  let(:account) { create(:dash_google_account, :expired, access_token: "stale", refresh_token: "rt-1") }

  it "makes no call while the integration is off in test" do
    expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  describe "with the integration on" do
    before { search_console_enabled! }

    it "posts the refresh grant and stores the new access token" do
      stub_token

      expect(described_class.call(account: account)).to eq("fresh-access")

      expect(a_request(:post, token_url).with { |sent|
        URI.decode_www_form(sent.body).to_h == {
          "client_id" => SearchConsoleFixtures::CLIENT_ID,
          "client_secret" => SearchConsoleFixtures::CLIENT_SECRET,
          "refresh_token" => "rt-1",
          "grant_type" => "refresh_token"
        }
      }).to have_been_made

      account.reload
      expect(account.access_token).to eq("fresh-access")
      expect(account.expires_at).to be_within(5.seconds).of(3599.seconds.from_now)
    end

    it "keeps the working refresh token when the answer has none" do
      stub_token

      described_class.call(account: account)

      expect(account.reload.refresh_token).to eq("rt-1")
    end

    it "clears an error a refused refresh recorded, because a working refresh is what fixes it" do
      account.record_error!(described_class::RECONNECT_MESSAGE)
      stub_token

      described_class.call(account: account)

      expect(account.reload.last_error).to be_nil
      expect(account.reload.last_error_at).to be_nil
    end

    it "leaves an error a failed sync recorded, because a fresh token does not mean the sync worked" do
      account.record_error!(AhoyDashboard::SearchConsole::IngestCommand::UNREACHABLE_MESSAGE)
      stub_token

      described_class.call(account: account)

      expect(account.reload.last_error).to eq(AhoyDashboard::SearchConsole::IngestCommand::UNREACHABLE_MESSAGE)
    end

    it "records invalid_grant as a reconnect and says why it might keep happening" do
      stub_token(status: 400, body: { "error" => "invalid_grant" })

      expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)

      expect(account.reload.last_error).to eq(described_class::RECONNECT_MESSAGE)
      expect(account.last_error).to include("still in testing")
      expect(account.last_error_at).to be_present
    end

    it "keeps the refresh token even when google refuses it, because nothing here can tell why" do
      stub_token(status: 400, body: { "error" => "invalid_grant" })

      expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)

      expect(account.reload.refresh_token).to eq("rt-1")
    end

    it "records a plainer message for a refusal that is not invalid_grant" do
      stub_token(status: 401, body: { "error" => "unauthorized_client" })

      expect { described_class.call(account: account) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)

      expect(account.reload.last_error).to eq(described_class::REFUSED_MESSAGE)
    end

    it "refuses an account with no refresh token without recording anything" do
      unconnected = create(:dash_google_account, :unconnected)

      expect { described_class.call(account: unconnected) }.to raise_error(AhoyDashboard::SearchConsole::AuthError)

      expect(unconnected.reload.last_error).to be_nil
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end
end
