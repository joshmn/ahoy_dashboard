require "rails_helper"

RSpec.describe AhoyDashboard::HttpClient do
  subject(:http) { described_class.new(open_timeout: 5, read_timeout: 30) }

  let(:url) { "https://api.example.com/v1/thing" }

  describe "#get" do
    it "sends the params and the dashboard's user agent and hands back the parsed payload" do
      allow(AhoyDashboard).to receive(:host).and_return("example.com")
      stub = stub_request(:get, "#{url}?q=a")
        .with(headers: { "User-Agent" => "ahoy_dashboard/#{AhoyDashboard::VERSION} (example.com)", "X-Key" => "k" })
        .to_return(status: 200, body: { "answer" => 1 }.to_json)

      reply = http.get(url, params: { q: "a", skipped: nil }, headers: { "X-Key" => "k" })

      expect(stub).to have_been_made
      expect(reply).to be_success
      expect(reply.payload).to eq("answer" => 1)
    end

    it "retries a read timeout once and then gives up" do
      stub_request(:get, url).to_raise(Net::ReadTimeout)

      expect { http.get(url) }.to raise_error(described_class::Unreachable, /Net::ReadTimeout/)
      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "turns off the retry Net::HTTP does on its own, so a request goes out no more than twice" do
      allow(Net::HTTP).to receive(:start).and_call_original
      stub_request(:get, url).to_return(status: 200, body: "{}")

      http.get(url)

      expect(Net::HTTP).to have_received(:start).with("api.example.com", 443, hash_including(max_retries: 0))
    end
  end

  describe "#post_json" do
    it "sends a json body with basic auth" do
      stub = stub_request(:post, url).with(basic_auth: [ "login", "secret" ], body: '[{"a":1}]',
                                           headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: "{}")

      http.post_json(url, body: [ { a: 1 } ], basic_auth: [ "login", "secret" ])

      expect(stub).to have_been_made
    end

    it "asks again when the connection never opened" do
      stub_request(:post, url).to_raise(Errno::ECONNREFUSED).then.to_return(status: 200, body: "{}")

      expect(http.post_json(url, body: {})).to be_success
      expect(a_request(:post, url)).to have_been_made.twice
    end

    [ Net::ReadTimeout, Errno::ECONNRESET, EOFError, OpenSSL::SSL::SSLError ].each do |failure|
      it "does not send a billed post again after #{failure}" do
        stub_request(:post, url).to_raise(failure)

        expect { http.post_json(url, body: {}) }.to raise_error(described_class::Unreachable, /#{failure}/)
        expect(a_request(:post, url)).to have_been_made.once
      end
    end

    it "sends an idempotent post again after a read timeout" do
      stub_request(:post, url).to_raise(Net::ReadTimeout).then.to_return(status: 200, body: "{}")

      expect(http.post_json(url, body: {}, idempotent: true)).to be_success
      expect(a_request(:post, url)).to have_been_made.twice
    end
  end

  describe "#post_form" do
    it "sends the form" do
      stub = stub_request(:post, url).with(body: { "code" => "abc" }).to_return(status: 400, body: { "error" => "invalid_grant" }.to_json)

      reply = http.post_form(url, params: { code: "abc" })

      expect(stub).to have_been_made
      expect(reply).not_to be_success
      expect(reply.payload).to eq("error" => "invalid_grant")
    end
  end

  it "reads a body that is not a json object as an empty payload" do
    stub_request(:get, url).to_return({ status: 200, body: "[1, 2]" }, { status: 502, body: "<html>bad gateway</html>" })

    expect(http.get(url).payload).to eq({})
    expect(http.get(url).payload).to eq({})
  end
end
