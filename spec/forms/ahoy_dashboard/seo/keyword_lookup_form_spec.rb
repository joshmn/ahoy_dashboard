require "rails_helper"

RSpec.describe AhoyDashboard::Seo::KeywordLookupForm do
  it "hands back the phrase, place and language a lookup is keyed by" do
    form = described_class.new(seed: "  visiting ", country: "GB", city: "", language: "EN")

    expect(form.lookup_params).to eq(seed: "visiting", location: "gb", language: "en")
  end

  it "falls back to the configured place and language" do
    allow(AhoyDashboard::Keywords).to receive_messages(location: "us", language: "fr")

    expect(described_class.new(seed: "visiting").lookup_params).to eq(seed: "visiting", location: "us", language: "fr")
  end
end
