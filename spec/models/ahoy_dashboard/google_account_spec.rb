require "rails_helper"

RSpec.describe AhoyDashboard::GoogleAccount do
  describe "tokens" do
    it "round trips through the secret box" do
      account = described_class.create!(access_token: "at-1", refresh_token: "rt-1")

      expect(account.reload.access_token).to eq("at-1")
      expect(account.reload.refresh_token).to eq("rt-1")
    end

    it "does not store either token in the clear" do
      account = described_class.create!(access_token: "at-1", refresh_token: "rt-1")

      expect(account.reload[:access_token]).not_to include("at-1")
      expect(account.reload[:refresh_token]).not_to include("rt-1")
    end

    it "keeps the stored refresh token when handed a blank one" do
      account = described_class.create!(refresh_token: "rt-1")

      account.refresh_token = nil
      account.refresh_token = ""

      expect(account.refresh_token).to eq("rt-1")
    end

    it "reads as disconnected rather than raising when the envelope will not open" do
      account = described_class.create!(refresh_token: "rt-1")
      account.update_columns(refresh_token: "not an envelope")

      expect(account.reload.refresh_token).to be_nil
      expect(account.reload).not_to be_connected
    end
  end

  describe ".current" do
    it "is nil with nothing connected" do
      expect(described_class.current).to be_nil
    end

    it "is the one row, lowest id first" do
      first = described_class.create!(email: "a@example.com")
      described_class.create!(email: "b@example.com")

      expect(described_class.current).to eq(first)
    end
  end

  describe "readiness" do
    it "needs a refresh token to count as connected" do
      expect(described_class.new(access_token: "at-1")).not_to be_connected
      expect(described_class.new(refresh_token: "rt-1")).to be_connected
    end

    it "needs a property as well to count as ready" do
      account = described_class.new(refresh_token: "rt-1")

      expect(account).not_to be_ready
      account.property_uri = "sc-domain:example.com"
      expect(account).to be_ready
    end
  end

  describe "#expired?" do
    it "treats a missing expiry as expired" do
      expect(described_class.new).to be_expired
    end

    it "expires a minute before it actually does" do
      now = Time.current
      account = described_class.new(expires_at: now + 30.seconds)

      expect(account.expired?(now: now)).to be(true)
      expect(described_class.new(expires_at: now + 10.minutes).expired?(now: now)).to be(false)
    end
  end

  describe "#property_label" do
    it "is nil with no property chosen" do
      expect(described_class.new.property_label).to be_nil
    end

    it "strips the domain prefix a domain property carries" do
      account = described_class.new(property_uri: "sc-domain:federalprisondude.com")

      expect(account.property_label).to eq("federalprisondude.com")
      expect(account).to be_domain_property
    end

    it "prints a url prefix property as it stands" do
      account = described_class.new(property_uri: "https://federalprisondude.com/")

      expect(account.property_label).to eq("https://federalprisondude.com/")
      expect(account).not_to be_domain_property
    end
  end

  describe "error state" do
    it "records and clears an error" do
      account = described_class.create!(email: "a@example.com")

      account.record_error!("invalid_grant")
      expect(account.reload.last_error).to eq("invalid_grant")
      expect(account.last_error_at).to be_present

      account.clear_error!
      expect(account.reload.last_error).to be_nil
      expect(account.last_error_at).to be_nil
    end

    it "truncates a long message rather than failing to record it" do
      account = described_class.create!
      account.record_error!("x" * 400)

      expect(account.reload.last_error.length).to eq(255)
    end
  end
end
