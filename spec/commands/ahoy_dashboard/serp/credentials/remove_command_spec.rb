require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Credentials::RemoveCommand do
  it "deletes one credential and keeps the others" do
    create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com", password: "hunter2" })

    events = described_class.call(name: "dataforseo", key: "password")

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::SerpProvider.for("dataforseo").credentials).to eq(login: "me@example.com")
  end

  it "clears the column once the last credential is gone" do
    create(:dash_serp_provider, :serpapi)

    described_class.call(name: "serpapi", key: :api_key)

    expect(AhoyDashboard::SerpProvider.for("serpapi").read_attribute(:credentials)).to be_nil
  end

  it "broadcasts missing when nothing is stored under that key" do
    create(:dash_serp_provider, name: "dataforseo", credentials: { login: "me@example.com" })

    expect(described_class.call(name: "dataforseo", key: :password)).to have_key(:missing)
  end

  it "broadcasts missing when there is no row" do
    expect(described_class.call(name: "serpapi", key: :api_key)).to have_key(:missing)
  end
end
