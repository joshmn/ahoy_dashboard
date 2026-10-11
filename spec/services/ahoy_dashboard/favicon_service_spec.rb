require "rails_helper"
require "support/ahoy_dashboard/fixtures"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::FaviconService do
  let(:png) { "\x89PNG\r\n\x1a\n".b + "the rest of it".b }
  let(:icon_url) { "https://icons.duckduckgo.com/ip3/google.com.ico" }

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = previous
  end

  def referred_from!(domain)
    dash_visit(started_at: Time.current, referring_domain: domain)
  end

  def switch_off!
    switch_off_ahoy_dashboard(:favicons)
  end

  describe "a domain the data knows" do
    before { referred_from!("google.com") }

    it "fetches the icon and reports what the bytes actually are" do
      stub_request(:get, icon_url).to_return(status: 200, body: png,
        headers: { "Content-Type" => "application/octet-stream" })

      icon = described_class.call("google.com")

      expect(icon.content_type).to eq("image/png")
      expect(icon.bytes).to eq(png)
    end

    it "asks for it once and serves the rest from the cache" do
      stub_request(:get, icon_url).to_return(status: 200, body: png)

      3.times { expect(described_class.call("google.com")).to be_present }

      expect(a_request(:get, icon_url)).to have_been_made.once
    end

    # A miss that is not cached means every dashboard load re-fetches a domain
    # that has no icon, which is most of them.
    it "remembers a 404 rather than asking again" do
      stub_request(:get, icon_url).to_return(status: 404)

      3.times { expect(described_class.call("google.com")).to be_nil }

      expect(a_request(:get, icon_url)).to have_been_made.once
    end

    it "swallows a timeout" do
      stub_request(:get, icon_url).to_timeout

      expect(described_class.call("google.com")).to be_nil
    end

    it "swallows a connection failure" do
      stub_request(:get, icon_url).to_raise(SocketError)

      expect(described_class.call("google.com")).to be_nil
    end

    it "refuses a response that is not an image, whatever it calls itself" do
      stub_request(:get, icon_url).to_return(status: 200, body: "<html>nope</html>",
        headers: { "Content-Type" => "image/png" })

      expect(described_class.call("google.com")).to be_nil
    end

    it "refuses a body over the cap" do
      stub_request(:get, icon_url)
        .to_return(status: 200, body: png + ("x" * described_class::MAX_BYTES))

      expect(described_class.call("google.com")).to be_nil
    end

    it "refuses one that announces itself over the cap" do
      stub_request(:get, icon_url).to_return(status: 200, body: png,
        headers: { "Content-Length" => (described_class::MAX_BYTES + 1).to_s })

      expect(described_class.call("google.com")).to be_nil
    end

    it "sends nothing while switched off" do
      switch_off!

      expect(described_class.call("google.com")).to be_nil
      expect(a_request(:get, icon_url)).not_to have_been_made
    end
  end

  describe "which domains it will fetch at all" do
    it "refuses a domain nothing in the data referred us from" do
      referred_from!("google.com")

      expect(described_class.call("evil.example")).to be_nil
      expect(WebMock).not_to have_requested(:get, %r{icons\.duckduckgo\.com})
    end

    it "refuses anything that is not a bare hostname" do
      referred_from!("google.com")

      [
        "", "   ", "google", "google.com/../secret", "http://google.com",
        "google.com:8080", "user@google.com", "google.com.", "goo gle.com",
        "google.com?x=1", "-google.com", "münchen.de", "203.0.113.10",
        "#{'a' * 250}.com", "google.com/ip3/other.ico"
      ].each do |value|
        expect(described_class.call(value)).to be_nil, "expected #{value.inspect} to be refused"
      end

      expect(WebMock).not_to have_requested(:get, %r{icons\.duckduckgo\.com})
    end

    it "takes a punycode host, because that is the form the data holds" do
      referred_from!("xn--mnchen-3ya.de")
      stub = stub_request(:get, "https://icons.duckduckgo.com/ip3/xn--mnchen-3ya.de.ico")
        .to_return(status: 200, body: png)

      expect(described_class.call("xn--mnchen-3ya.de")).to be_present
      expect(stub).to have_been_made
    end

    it "case folds, because case is not information in a hostname" do
      referred_from!("google.com")
      stub_request(:get, icon_url).to_return(status: 200, body: png)

      expect(described_class.call("GOOGLE.COM")).to be_present
    end
  end

  describe ".domain_for" do
    before { referred_from!("google.com") }

    it "takes the host out of whatever a row printed" do
      [ "google.com", "www.google.com", "https://www.google.com/search?q=prison",
        "HTTPS://Google.com/" ].each do |label|
        expect(described_class.domain_for(label)).to eq("google.com"), "from #{label.inspect}"
      end
    end

    it "has nothing to show for a row that is not a website" do
      [ "Direct / None", "Organic Search", "newsletter", nil, "" ].each do |label|
        expect(described_class.domain_for(label)).to be_nil, "from #{label.inspect}"
      end
    end
  end
end
