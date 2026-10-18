require "rails_helper"

RSpec.describe AhoyDashboard::Property do
  describe "validations" do
    it "wants a key" do
      expect(described_class.new).not_to be_valid
    end

    it "refuses a key that could not be a property name" do
      expect(described_class.new(key: "line\nbreak")).not_to be_valid
      expect(described_class.new(key: "a" * 256)).not_to be_valid
      expect(described_class.new(key: "facility_id")).to be_valid
    end

    it "takes any key an app can send" do
      %w[facilityId plan-tier page.section].push("plan name").each do |key|
        expect(described_class.new(key: key)).to be_valid, "expected #{key.inspect} to be valid"
      end
    end

    it "treats two spellings as two keys, the way the events do" do
      described_class.create!(key: "facilityId")

      expect(described_class.new(key: "facilityid")).to be_valid
    end

    it "refuses the same key twice" do
      described_class.create!(key: "facility_id")

      expect(described_class.new(key: "facility_id")).not_to be_valid
    end

    it "refuses a key that is already a built in dimension, naming it" do
      property = described_class.new(key: "format")

      expect(property).not_to be_valid
      expect(property.errors[:key]).to include(a_string_including("Page format"))
      expect(described_class.new(key: "Country")).not_to be_valid
      expect(described_class.new(key: "page_format")).not_to be_valid
    end

    it "trims the key and keeps its capitals" do
      expect(described_class.create!(key: "  facilityId  ").key).to eq("facilityId")
    end
  end

  describe ".surfaced" do
    it "leaves out the disabled ones and orders by position" do
      described_class.create!(key: "second", position: 2)
      described_class.create!(key: "first", position: 1)
      described_class.create!(key: "hidden", position: 0, enabled: false)

      expect(described_class.surfaced.map(&:key)).to eq(%w[first second])
    end
  end

  describe ".default_dimension_key" do
    it "does not fall back to a key from some other app" do
      expect(described_class.default_dimension_key).not_to eq("prop:facility_id")
    end

    it "opens on whichever property is first once the list is configured" do
      described_class.create!(key: "campaign", position: 0)

      expect(described_class.default_dimension_key).to eq("prop:campaign")
    end

    it "ignores a disabled property" do
      described_class.create!(key: "campaign", position: 0, enabled: false)

      expect(described_class.default_dimension_key).not_to eq("prop:campaign")
    end
  end

  describe ".showing" do
    it "takes the key that was asked for when it can be a property" do
      expect(described_class.showing("plan name", %w[plan])).to eq("plan name")
    end

    it "falls back to the first key found when the one asked for cannot be a property" do
      [ nil, "", "  ", "line\nbreak", [ "plan" ], { "key" => "plan" } ].each do |requested|
        expect(described_class.showing(requested, %w[tier plan])).to eq("tier")
      end
    end

    it "is nil when nothing was asked for and nothing was found" do
      expect(described_class.showing(nil, [])).to be_nil
    end
  end

  it "builds the dimension it stands for" do
    property = described_class.create!(key: "facility_id")

    expect(property.dimension.key).to eq("prop:facility_id")
    expect(property.to_param).to eq("facility_id")
  end
end
