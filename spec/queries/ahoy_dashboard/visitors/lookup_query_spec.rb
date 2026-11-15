require "rails_helper"

RSpec.describe AhoyDashboard::Visitors::LookupQuery do
  let!(:visit) { dash_landing("/", at: dash_time(2026, 8, 10, 9), visitor: "token-a", visit_token: "visit-a", user_id: 42) }
  let!(:anonymous) { dash_landing("/", at: dash_time(2026, 8, 10, 10), visitor: "token-b") }

  it "finds a visit by its visit token" do
    found = described_class.call("visit-a")

    expect(found).to be_visit
    expect(found.visit).to eq(visit)
  end

  it "finds a visitor by its visitor token" do
    found = described_class.call(" token-b ")

    expect(found.kind).to eq(:visitor)
    expect(found.key).to eq("token-b")
  end

  it "finds a user by id" do
    found = described_class.call("42")

    expect(found).to be_user
    expect(found.key).to eq("42")
  end

  it "finds nothing for a value that matches nothing" do
    expect(described_class.call("nobody")).to be_nil
    expect(described_class.call("")).to be_nil
    expect(described_class.call("x" * 300)).to be_nil
  end

  it "never treats something that isn't an id as a missing user id" do
    expect(described_class.call("not-a-number")).to be_nil
  end
end
