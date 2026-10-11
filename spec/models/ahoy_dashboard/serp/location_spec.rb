require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Location do
  it "defaults to the country every other default is written against" do
    expect(described_class.new(nil).country_code).to eq(AhoyDashboard::Serp::DEFAULT_COUNTRY)
  end

  it "reads a country code" do
    location = described_class.country("US")

    expect(location).to be_country
    expect(location).not_to be_city
    expect(location.country_code).to eq("us")
    expect(location.canonical_name).to be_nil
    expect(location.label).to eq("US")
  end

  it "reads a city back out of the value it was built from" do
    location = described_class.city(canonical_name: "Chicago,Illinois,United States")

    expect(location.to_s).to eq("city:us:Chicago,Illinois,United States")
    expect(location).to be_city
    expect(location.country_code).to eq("us")
    expect(location.canonical_name).to eq("Chicago,Illinois,United States")
    expect(location.label).to eq("Chicago, Illinois, United States")
  end

  it "parses a value it has already parsed" do
    location = described_class.country("gb")

    expect(described_class.parse(location)).to equal(location)
  end

  it "takes a two letter country code and nothing else" do
    expect(described_class.new("us")).to be_readable
    expect(described_class.new("GB")).to be_readable
    expect(described_class.new("chicago")).not_to be_readable
    expect(described_class.new("usa")).not_to be_readable
    expect(described_class.new("chicago").problem).to include("two letter country code")
  end

  it "wants all three parts of a city, and says which one is missing" do
    expect(described_class.new("city:us:Chicago,Illinois,United States")).to be_readable
    expect(described_class.new("city:us")).not_to be_readable
    expect(described_class.new("city:us").problem).to include("missing the place")
    expect(described_class.new("city:united states:Chicago")).not_to be_readable
  end

  it "compares by value" do
    expect(described_class.new("us")).to eq(described_class.country("US"))
  end
end
