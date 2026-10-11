require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::PropertyDecorator, type: :decorator do
  def decorate(property)
    described_class.new(property)
  end

  describe "#name" do
    it "prefers the label" do
      expect(decorate(AhoyDashboard::Property.new(key: "facility_id", label: "Facility")).name).to eq("Facility")
    end

    it "humanizes the key when there is no label" do
      expect(decorate(AhoyDashboard::Property.new(key: "facility_id")).name).to eq("Facility")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    property = AhoyDashboard::Property.create!(key: "facility_id")

    expect(decorate(property).to_param).to eq("facility_id")
  end
end
