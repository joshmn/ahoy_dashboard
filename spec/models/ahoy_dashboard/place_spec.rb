require "rails_helper"

RSpec.describe AhoyDashboard::Place do
  def place(name, **rest)
    create(:dash_place, name: name, label: name.split(",").first,
                        depth: name.split(",").size - 1, **rest)
  end

  describe "reading the path" do
    it "knows what it is inside" do
      expect(place("Chicago,Illinois,United States").parent_path).to eq("Illinois,United States")
    end

    it "has nothing above it at the top" do
      expect(place("United States").parent_path).to eq("")
    end
  end

  # The catalogue is an input aid. What a keyword stores is the string the
  # adapters want, which is the same string whether it was picked or typed.
  describe "#to_location" do
    it "turns a country into the code the adapters take" do
      expect(place("United States", country_code: "us", depth: 0).to_location.value).to eq("us")
    end

    it "turns anything smaller into the city form" do
      location = place("Chicago,Illinois,United States", country_code: "us").to_location

      expect(location.value).to eq("city:us:Chicago,Illinois,United States")
      expect(location).to be_city
    end

    it "makes a place the search provider will accept" do
      expect(place("Illinois,United States", country_code: "us").to_location.problem).to be_nil
    end
  end

  describe ".for_location" do
    it "finds the row behind a stored place, so the picker can open where it already is" do
      chicago = place("Chicago,Illinois,United States", country_code: "us")

      expect(described_class.for_location(chicago.to_location)).to eq(chicago)
    end

    it "finds the country row for a country" do
      us = place("United States", country_code: "us", depth: 0)

      expect(described_class.for_location(AhoyDashboard::Serp::Location.country("us"))).to eq(us)
    end

    # A place typed in by hand, or one the provider has since dropped. It still
    # searches; it just has nowhere for the picker to start from.
    it "is nothing for a place that is not on the list" do
      expect(described_class.for_location(AhoyDashboard::Serp::Location.city(canonical_name: "Nowhere", country_code: "us")))
        .to be_nil
    end
  end
end
