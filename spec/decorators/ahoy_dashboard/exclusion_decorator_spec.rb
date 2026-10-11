require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::ExclusionDecorator, type: :decorator do
  let(:entry) { { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } }

  def decorate(exclusion)
    described_class.new(exclusion)
  end

  describe "#summary" do
    it "reads one filter out in words" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ])

      expect(decorate(exclusion).summary).to eq("Network (ASN) contains AMAZON")
    end

    it "reads a group as or" do
      exclusion = AhoyDashboard::Exclusion.create!(
        name: "Two", filters: [ entry.merge("group" => 0), entry.merge("value" => "GOOGLE", "group" => 0) ]
      )

      expect(decorate(exclusion).summary).to eq("Network (ASN) contains AMAZON or GOOGLE")
    end

    it "reads filters with no block as one set, the way they were saved before sets" do
      exclusion = AhoyDashboard::Exclusion.create!(
        name: "Old",
        filters: [ entry, entry.merge("dimension" => "country", "operator" => "is", "value" => "US") ]
      )

      expect(decorate(exclusion).summary).to eq("Network (ASN) contains AMAZON and Country is US")
    end

    it "reads sets as alternatives" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Sets", filters: [
        entry.merge("block" => 0),
        entry.merge("dimension" => "country", "operator" => "is", "value" => "US", "block" => 0),
        entry.merge("dimension" => "ip", "operator" => "is", "value" => "1.2.3.4", "block" => 1)
      ])

      expect(decorate(exclusion).summary)
        .to eq("(Network (ASN) contains AMAZON and Country is US) or IP address is 1.2.3.4")
    end
  end

  describe "#rule" do
    it "opens with what the exclusion does and lowercases the filter behind it" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ])

      expect(decorate(exclusion).rule).to eq("Hides visits where network (ASN) contains AMAZON")
    end

    it "says why instead of reading out filters it cannot read" do
      exclusion = AhoyDashboard::Exclusion.create!(name: "Broken", filters: [ entry ])
      exclusion.update_column(:filters, [ entry.merge("dimension" => "nope") ])

      expect(decorate(exclusion.reload).rule).to include("Not being applied")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    exclusion = AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ])

    expect(decorate(exclusion).to_param).to eq(exclusion.id.to_s)
  end
end
