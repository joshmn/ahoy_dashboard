require "rails_helper"

RSpec.describe AhoyDashboard::Counted do
  it "prints the count delimited, with the noun agreeing with it" do
    expect(described_class.call(1, noun: "visitor")).to eq("1 visitor")
    expect(described_class.call(0, noun: "visitor")).to eq("0 visitors")
    expect(described_class.call(12_345, noun: "pageview")).to eq("12,345 pageviews")
  end
end
