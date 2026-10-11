require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Properties::AdoptCommand do
  let(:account) { create(:dash_google_account, :with_property, backfilled_to: Date.current - 100, synced_at: 1.hour.ago) }

  def stored!
    create(:dash_search_console_total, date: Date.current - 3)
    create(:dash_search_console_keyword, date: Date.current - 3)
    create(:dash_search_console_row, date: Date.current - 3)
  end

  it "claims rows nobody has claimed for the property the account already reads" do
    stored!

    events = described_class.call(account: account, property_uri: "sc-domain:example.com")

    expect(events).to have_key(:kept)
    expect(AhoyDashboard::SearchConsole.stored_property).to eq("sc-domain:example.com")
    expect(AhoyDashboard::SearchConsoleTotal.count).to eq(1)
  end

  it "clears every grain and the history watermark for a different property" do
    stored!

    events = described_class.call(account: account, property_uri: "sc-domain:other.com")

    expect(events[:cleared]).to eq(1)
    expect(AhoyDashboard::SearchConsoleTotal.count).to eq(0)
    expect(AhoyDashboard::SearchConsoleKeyword.count).to eq(0)
    expect(AhoyDashboard::SearchConsoleRow.count).to eq(0)
    expect(account.reload.backfilled_to).to be_nil
    expect(account.synced_at).to be_nil
    expect(AhoyDashboard::SearchConsole.stored_property).to eq("sc-domain:other.com")
  end

  it "wipes the old property's error too, because it was about the old property" do
    account.record_error!("This Google account can no longer read example.com")

    described_class.call(account: account, property_uri: "sc-domain:other.com")

    expect(account.reload.last_error).to be_nil
  end

  it "goes by the recorded owner once the account has been dropped and connected again" do
    stored!
    AhoyDashboard::SearchConsole.store_property!("sc-domain:example.com")
    fresh = create(:dash_google_account)

    events = described_class.call(account: fresh, property_uri: "sc-domain:other.com")

    expect(events).to have_key(:cleared)
    expect(AhoyDashboard::SearchConsoleTotal.count).to eq(0)
  end

  it "keeps the rows when the recorded owner is picked again" do
    stored!
    AhoyDashboard::SearchConsole.store_property!("sc-domain:example.com")

    events = described_class.call(account: create(:dash_google_account), property_uri: "sc-domain:example.com")

    expect(events).to have_key(:kept)
    expect(AhoyDashboard::SearchConsoleTotal.count).to eq(1)
  end
end
