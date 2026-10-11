require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Credentials::RemoveCommand do
  def store!(**values)
    AhoyDashboard::Credential.fetch(AhoyDashboard::SearchConsole::CREDENTIAL_NAME).update!(values: values)
  end

  it "deletes one value and keeps the other" do
    store!(client_id: "id", client_secret: "secret")

    events = described_class.call(key: "client_secret")

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::SearchConsole.credential.values).to eq(client_id: "id")
  end

  it "keeps the row once both are gone" do
    store!(client_id: "id")

    described_class.call(key: :client_id)

    expect(AhoyDashboard::Credential.count).to eq(1)
    expect(AhoyDashboard::SearchConsole.credential.read_attribute(:secrets)).to be_nil
  end

  it "broadcasts missing when nothing is stored under that key" do
    store!(client_id: "id")

    expect(described_class.call(key: :client_secret)).to have_key(:missing)
  end

  it "broadcasts missing when there is no row" do
    expect(described_class.call(key: :client_id)).to have_key(:missing)
  end
end
