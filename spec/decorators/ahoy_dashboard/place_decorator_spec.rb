require "rails_helper"

RSpec.describe AhoyDashboard::PlaceDecorator, type: :decorator do
  def place(name, **rest)
    create(:dash_place, name: name, label: name.split(",").first,
                        depth: name.split(",").size - 1, **rest)
  end

  def decorate(record)
    described_class.new(record)
  end

  describe "#readable" do
    it "reads back as a sentence rather than a machine string" do
      expect(decorate(place("Chicago,Illinois,United States")).readable)
        .to eq("Chicago, Illinois, United States")
    end
  end

  describe "#parent_readable" do
    it "says what it is inside" do
      expect(decorate(place("Chicago,Illinois,United States")).parent_readable)
        .to eq("Illinois, United States")
    end

    it "has nothing above it at the top" do
      expect(decorate(place("United States")).parent_readable).to eq("")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    record = place("United States", code: 2840)

    expect(decorate(record).to_param).to eq("2840")
  end
end
