require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Redirects::UpdateCommand do
  def form(value)
    AhoyDashboard::SearchConsole::RedirectForm.new(redirect_uri: value)
  end

  it "stores the override and broadcasts ok" do
    events = described_class.call(form: form("http://lvh.me:5000/telemetry/settings/google_callback"))

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::SearchConsole.redirect_uri).to eq("http://lvh.me:5000/telemetry/settings/google_callback")
  end

  it "clears the override when it is blank" do
    AhoyDashboard::Preferences.write(:search_console, redirect_uri: "https://elsewhere.example/callback")

    described_class.call(form: form(""))

    expect(AhoyDashboard::Preferences.stored?(:search_console, :redirect_uri)).to be(false)
  end

  it "broadcasts invalid with the form and writes nothing" do
    invalid = form("mailto:someone@example.com")

    events = nil
    expect { events = described_class.call(form: invalid) }.not_to(change { AhoyDashboard::Setting.order(:key).pluck(:key, :value) })
    expect(events[:invalid]).to eq(invalid)
    expect(invalid.errors.messages.keys).to eq([ :redirect_uri ])
  end
end
