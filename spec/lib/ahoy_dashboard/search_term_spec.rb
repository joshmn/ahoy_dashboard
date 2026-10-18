require "rails_helper"

RSpec.describe AhoyDashboard::SearchTerm do
  it "trims the term and caps it at the length every search box shares" do
    expect(described_class.clean("  bet  ")).to eq("bet")
    expect(described_class.clean(" #{"a" * 150}")).to eq("a" * described_class::MAX_LENGTH)
  end

  it "reads anything out of a query string without raising" do
    expect(described_class.clean(nil)).to eq("")
    expect(described_class.clean([ "alpha" ])).to eq("[\"alpha\"]")
    expect(described_class.clean("   ")).to eq("")
  end
end
