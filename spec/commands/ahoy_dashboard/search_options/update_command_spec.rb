require "rails_helper"

RSpec.describe AhoyDashboard::SearchOptions::UpdateCommand do
  def form(**values)
    AhoyDashboard::SearchOptionsForm.new(
      { keywords_provider: "dataforseo", keywords_location: "gb", keywords_language: "en-gb",
        backlinks_provider: "", places_postal_codes: "1", places_source: "" }.merge(values)
    )
  end

  it "stores every value and broadcasts ok" do
    events = described_class.call(form: form)

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::Keywords.provider).to eq(:dataforseo)
    expect(AhoyDashboard::Keywords.location).to eq("gb")
    expect(AhoyDashboard::Keywords.language).to eq("en-gb")
    expect(AhoyDashboard::Preferences.stored?(:backlinks, :provider)).to be(false)
    expect(AhoyDashboard::Places.postal_codes?).to be(true)
    expect(AhoyDashboard::Places.source_template).to eq(AhoyDashboard::Preferences::PLACES_SOURCE)
  end

  it "broadcasts invalid with the form and writes nothing" do
    invalid = form(backlinks_provider: "ahrefs", places_source: "not a url")

    events = nil
    expect { events = described_class.call(form: invalid) }.not_to(change { AhoyDashboard::Setting.order(:key).pluck(:key, :value) })
    expect(events[:invalid]).to eq(invalid)
    expect(invalid.errors.messages.keys).to contain_exactly(:backlinks_provider, :places_source)
  end
end
