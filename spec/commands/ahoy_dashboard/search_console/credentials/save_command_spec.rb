require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Credentials::SaveCommand do
  def stored
    AhoyDashboard::SearchConsole.credential.credentials
  end

  it "stores what was typed, trimmed" do
    events = described_class.call(values: { "client_id" => " id ", "client_secret" => "secret\n" })

    expect(events).to have_key(:ok)
    expect(stored).to eq(client_id: "id", client_secret: "secret")
  end

  it "keeps a stored value when its box is left blank" do
    described_class.call(values: { client_id: "id", client_secret: "secret" })

    described_class.call(values: { "client_id" => "new-id", "client_secret" => "  " })

    expect(stored).to eq(client_id: "new-id", client_secret: "secret")
    expect(AhoyDashboard::Credential.count).to eq(1)
  end
end
