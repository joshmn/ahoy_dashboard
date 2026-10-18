require "rails_helper"

RSpec.describe AhoyDashboard::Share do
  describe ".fraction" do
    it "is the part over the whole, held between nothing and all of it" do
      expect(described_class.fraction(25, of: 100)).to eq(0.25)
      expect(described_class.fraction(150, of: 100)).to eq(1.0)
      expect(described_class.fraction(-5, of: 100)).to eq(0.0)
    end

    it "is nothing when there is no whole to measure against" do
      expect(described_class.fraction(5, of: 0)).to eq(0.0)
      expect(described_class.fraction(5, of: nil)).to eq(0.0)
      expect(described_class.fraction(nil, of: 10)).to eq(0.0)
    end

    it "reads a fractional whole as a whole" do
      expect(described_class.fraction(0.25, of: 0.5)).to eq(0.5)
    end
  end

  describe ".label" do
    it "rounds to a whole percent from ten up and to one decimal under it" do
      expect(described_class.label(123, of: 1_000)).to eq("12%")
      expect(described_class.label(3, of: 1_000)).to eq("0.3%")
    end

    it "says all of it from 99.5 up rather than rounding to it" do
      expect(described_class.label(995, of: 1_000)).to eq("100%")
      expect(described_class.label(994, of: 1_000)).to eq("99%")
    end

    it "prints a sliver as under a tenth of a percent rather than zero" do
      expect(described_class.label(3, of: 10_000)).to eq("<0.1%")
      expect(described_class.label(0, of: 10_000)).to eq("0%")
    end

    it "is nil when there is no whole to measure against" do
      expect(described_class.label(3, of: 0)).to be_nil
      expect(described_class.label(3, of: nil)).to be_nil
    end
  end
end
