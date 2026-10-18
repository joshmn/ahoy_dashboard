require "rails_helper"

RSpec.describe AhoyDashboard::Delta do
  describe ".between" do
    it "reads a count change as a percent of the earlier count" do
      expect(described_class.between(:percent, now: 40, before: 10)).to eq(text: "300.0%", tone: :good, direction: :up)
    end

    it "rounds a count change to whole percents when asked" do
      expect(described_class.between(:percent, now: 40, before: 10, places: 0)[:text]).to eq("300%")
    end

    it "has nothing to say about a count with nothing before it" do
      expect(described_class.between(:percent, now: 5, before: 0)).to be_nil
    end

    it "reads a rate change in points" do
      expect(described_class.between(:points, now: 0.05, before: 0.02)).to eq(text: "3.0 pts", tone: :good, direction: :up)
    end

    it "reads a position change in places, where a lower number is the good one" do
      expect(described_class.between(:places, now: 3.0, before: 5.5)).to eq(text: "2.5", tone: :good, direction: :down)
    end

    it "only wants an earlier position when asked to" do
      expect(described_class.between(:places, now: 3, before: 0)).not_to be_nil
      expect(described_class.between(:places, now: 3, before: 0, require_before: true)).to be_nil
    end

    it "keeps a level move unless told to hide it" do
      expect(described_class.between(:points, now: 0.02, before: 0.02)).to eq(text: "0.0 pts", tone: :neutral, direction: nil)
      expect(described_class.between(:points, now: 0.02, before: 0.02, hide_zero: true)).to be_nil
    end
  end
end
