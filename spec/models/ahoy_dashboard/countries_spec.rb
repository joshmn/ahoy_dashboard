require "rails_helper"

RSpec.describe AhoyDashboard::Countries do
  it "reads a country back from its full name" do
    expect(described_class.code("United Kingdom")).to eq("GB")
    expect(described_class.code("united states of america")).to eq("US")
    expect(described_class.code("Côte d'Ivoire")).to eq("CI")
    expect(described_class.code("CA")).to eq("CA")
    expect(described_class.code("Atlantis")).to be_nil
    expect(described_class.code(" ")).to be_nil
  end

  it "names a two letter code and leaves anything else as it was stored" do
    expect(described_class.name("gb")).to eq("United Kingdom")
    expect(described_class.name("ZZ")).to eq("ZZ")
    expect(described_class.name("United Kingdom")).to eq("United Kingdom")
  end
end
