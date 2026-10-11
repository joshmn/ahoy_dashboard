require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Domain do
  describe ".host" do
    it "reads the host out of a url" do
      expect(described_class.host("https://www.bop.gov/inmates/visiting.jsp")).to eq("bop.gov")
    end

    it "reads a bare domain" do
      expect(described_class.host("www.Example.COM")).to eq("example.com")
    end

    it "drops a port, a path and a trailing dot" do
      expect(described_class.host("lvh.me:5000/x")).to eq("lvh.me")
      expect(described_class.host("example.com.")).to eq("example.com")
    end

    it "answers nil for nothing and for something unparseable" do
      expect(described_class.host(nil)).to be_nil
      expect(described_class.host("")).to be_nil
      expect(described_class.host("http://exa mple.com")).to be_nil
    end
  end

  describe ".matches?" do
    it "matches the same host either side of a scheme and a www" do
      expect(described_class.matches?("https://www.example.com/a", "example.com")).to be(true)
    end

    it "does not treat a subdomain as the site unless asked" do
      expect(described_class.matches?("https://portal.example.com/a", "example.com")).to be(false)
    end

    it "treats a subdomain as the site when asked" do
      expect(described_class.matches?("https://portal.example.com/a", "example.com",
                                      match_subdomains: true)).to be(true)
    end

    it "does not match a domain that merely ends with the same letters" do
      expect(described_class.matches?("https://notexample.com", "example.com",
                                      match_subdomains: true)).to be(false)
    end

    it "is false when either side is missing" do
      expect(described_class.matches?(nil, "example.com")).to be(false)
      expect(described_class.matches?("https://example.com", nil)).to be(false)
    end
  end
end
