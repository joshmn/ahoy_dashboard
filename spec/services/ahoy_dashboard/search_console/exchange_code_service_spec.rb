require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsole::ExchangeCodeService do
  let(:token_url) { AhoyDashboard::SearchConsole::TOKEN_URL }

  it "makes no call while the integration is off in test" do
    expect(AhoyDashboard::SearchConsole).not_to be_enabled
    expect { described_class.call(code: "abc") }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  describe "with the integration on" do
    before { search_console_enabled! }

    it "posts the code, the client credentials and the same redirect uri" do
      stub_token(body: token_body("refresh_token" => "rt-1"))

      tokens = described_class.call(code: "abc")

      expect(a_request(:post, token_url).with { |sent|
        URI.decode_www_form(sent.body).to_h == {
          "code" => "abc",
          "client_id" => SearchConsoleFixtures::CLIENT_ID,
          "client_secret" => SearchConsoleFixtures::CLIENT_SECRET,
          "redirect_uri" => SearchConsoleFixtures::REDIRECT_URI,
          "grant_type" => "authorization_code"
        }
      }).to have_been_made

      expect(tokens.access_token).to eq("fresh-access")
      expect(tokens.refresh_token).to eq("rt-1")
      expect(tokens.scope).to eq(AhoyDashboard::SearchConsole::SCOPE)
      expect(tokens.expires_at).to be_within(5.seconds).of(3599.seconds.from_now)
    end

    it "refuses a blank code without asking google" do
      expect { described_class.call(code: " ") }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it "reads google's error code off a refusal" do
      stub_token(status: 400, body: { "error" => "invalid_grant", "error_description" => "Bad Request" })

      expect { described_class.call(code: "abc") }.to raise_error(AhoyDashboard::SearchConsole::AuthError) { |error|
        expect(error.code).to eq("invalid_grant")
        expect(error).to be_reconnect_required
      }
    end

    it "treats an answer with no access token as a refusal" do
      stub_token(body: { "token_type" => "Bearer" })

      expect { described_class.call(code: "abc") }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
    end

    it "raises rather than swallowing a connection failure" do
      stub_request(:post, token_url).to_timeout

      expect { described_class.call(code: "abc") }.to raise_error(AhoyDashboard::SearchConsole::Error)
    end
  end
end
