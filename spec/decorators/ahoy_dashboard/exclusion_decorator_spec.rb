require "rails_helper"

RSpec.describe AhoyDashboard::ExclusionDecorator, type: :decorator do
  let(:entry) { { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } }

  describe "#summary" do
    it "reads one filter out in words" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ])

      expect(decorate(exclusion).summary).to eq("Network (ASN) contains AMAZON")
    end

    it "reads filters with no block as one set, the way they were saved before sets" do
      exclusion = AhoyDashboard::Exclusion.create!(
        name: "Old",
        filters: [ entry, entry.merge("dimension" => "country", "operator" => "is", "value" => "US") ]
      )

      expect(decorate(exclusion).summary).to eq("Network (ASN) contains AMAZON and Country is US")
    end
  end

  describe "#rule" do
    it "opens with what the exclusion does and lowercases the filter behind it" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ])

      expect(decorate(exclusion).rule).to eq("Hides visits where network (ASN) contains AMAZON")
    end

    it "says why instead of reading out filters it cannot read" do
      exclusion = create(:dash_exclusion, :unreadable, name: "Broken")

      expect(decorate(exclusion).rule).to include("Not being applied")
    end
  end
end
