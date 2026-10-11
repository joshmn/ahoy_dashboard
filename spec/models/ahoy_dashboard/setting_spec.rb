require "rails_helper"

RSpec.describe AhoyDashboard::Setting do
  describe ".read and .write" do
    it "hands back the default when nothing is stored" do
      expect(described_class.read("nothing", "fallback")).to eq("fallback")
      expect(described_class.read("nothing")).to be_nil
    end

    it "stores any json shaped value under a key" do
      described_class.write("seo.brand_terms", [ "acme", "acme co" ])

      expect(described_class.read("seo.brand_terms")).to eq([ "acme", "acme co" ])
    end

    it "overwrites rather than duplicating" do
      described_class.write("time_zone", "Tokyo")
      described_class.write("time_zone", "Berlin")

      expect(described_class.where(key: "time_zone").count).to eq(1)
      expect(described_class.read("time_zone")).to eq("Berlin")
    end

    it "clears back to the default" do
      described_class.write("time_zone", "Tokyo")
      described_class.clear("time_zone")

      expect(described_class.read("time_zone", "UTC")).to eq("UTC")
    end

    it "answers the default when the table is not there yet" do
      allow(described_class).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "no table")

      expect(described_class.read("time_zone", "UTC")).to eq("UTC")
    end
  end

  describe "AhoyDashboard.time_zone" do
    it "is UTC when nothing is stored" do
      expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["UTC"])
    end

    it "prefers the stored zone" do
      described_class.write(described_class::TIME_ZONE, "Tokyo")

      expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["Tokyo"])
    end

    it "falls back to UTC when the stored zone is not one" do
      described_class.write(described_class::TIME_ZONE, "Mars/Olympus Mons")

      expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["UTC"])
    end

    it "falls back to UTC when the stored value is not even a string" do
      described_class.write(described_class::TIME_ZONE, { "zone" => "Tokyo" })

      expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["UTC"])
    end
  end
end
