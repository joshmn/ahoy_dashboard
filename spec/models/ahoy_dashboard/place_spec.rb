require "rails_helper"

RSpec.describe AhoyDashboard::Place do
  def place(name, **rest)
    create(:dash_place, name: name, **rest)
  end

  describe ".for_location" do
    it "finds the row behind a stored place, so the picker can open where it already is" do
      chicago = place("Chicago,Illinois,United States", country_code: "us")
      location = AhoyDashboard::Serp::Location.city(canonical_name: chicago.name, country_code: chicago.country_code)

      expect(described_class.for_location(location)).to eq(chicago)
    end

    it "finds the country row for a country" do
      us = place("United States", country_code: "us", depth: 0)

      expect(described_class.for_location(AhoyDashboard::Serp::Location.country("us"))).to eq(us)
    end

    it "is nothing for a place that is not on the list" do
      expect(described_class.for_location(AhoyDashboard::Serp::Location.city(canonical_name: "Nowhere", country_code: "us")))
        .to be_nil
    end
  end
end
