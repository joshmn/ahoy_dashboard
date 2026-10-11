require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Countries do
  it "names a country from the three letter code google sends" do
    expect(described_class.name("usa")).to eq("United States")
    expect(described_class.name("GBR")).to eq("United Kingdom")
    expect(described_class.name("xkk")).to eq("Kosovo")
  end

  it "names the rows that carry no country" do
    expect(described_class.name("")).to eq("Unknown")
    expect(described_class.name("zzz")).to eq("Unknown region")
  end

  it "prints a code it does not know rather than dropping it" do
    expect(described_class.name("qqq")).to eq("QQQ")
  end

  it "maps to the two letter code ahoy stores" do
    expect(described_class.alpha2("usa")).to eq("US")
    expect(described_class.alpha2("zzz")).to be_nil
  end
end
