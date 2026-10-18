require "rails_helper"

RSpec.describe AhoyDashboard::PropertyDecorator, type: :decorator do
  describe "#name" do
    it "prefers the label" do
      expect(decorate(AhoyDashboard::Property.new(key: "facility_id", label: "Facility")).name).to eq("Facility")
    end

    it "humanizes the key when there is no label" do
      expect(decorate(AhoyDashboard::Property.new(key: "facility_id")).name).to eq("Facility")
    end
  end
end
