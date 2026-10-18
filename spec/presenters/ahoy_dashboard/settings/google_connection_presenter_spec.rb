require "rails_helper"

RSpec.describe AhoyDashboard::Settings::GoogleConnectionPresenter do
  let(:floor) { Date.new(2025, 5, 13) }
  let(:callback) do
    AhoyDashboard::SearchConsoleCallbackQuery::Callback.new(
      effective: SearchConsoleFixtures::REDIRECT_URI, source: :host, browsing: nil, configured_host: "example.com"
    )
  end

  before { allow(AhoyDashboard::SearchConsole).to receive(:earliest_available_date).and_return(floor) }

  def presenter(remove: nil)
    described_class.new(callback: callback, remove: remove)
  end

  def stored(days:, first: Date.new(2026, 9, 1), last: Date.new(2026, 9, 6), expected: Date.new(2026, 9, 10))
    status = AhoyDashboard::SearchConsoleStatusQuery::Status.new(
      rows: 10, days: days, first_date: (first if days.positive?), last_date: (last if days.positive?),
      expected_last_date: expected, clicks: 1, impressions: 2
    )
    allow(AhoyDashboard::SearchConsoleStatusQuery).to receive(:call).and_return(status)
  end

  describe "#state" do
    it "asks for the client before anything else" do
      search_console_switched_off!(client_secret: nil)

      expect(presenter.state).to eq(:credentials)
      expect(presenter.missing_credentials_label).to eq("Client secret missing")
    end

    it "names whichever half of the client is missing" do
      allow(AhoyDashboard::SearchConsole).to receive_messages(client_id: nil, client_secret: "secret")
      expect(presenter.missing_credentials_label).to eq("Client ID missing")

      allow(AhoyDashboard::SearchConsole).to receive_messages(client_id: nil, client_secret: nil)
      expect(presenter.missing_credentials_label).to eq("No client ID or secret set")
    end

    it "is off when the client is there and the feature is not on" do
      search_console_switched_off!
      create(:dash_google_account, :with_property)

      expect(presenter.state).to eq(:off)
      expect(presenter).to be_connected
      expect(presenter).not_to be_setup_open
    end

    it "is connected or not once it is on" do
      search_console_enabled!
      expect(presenter.state).to eq(:disconnected)
      expect(presenter).to be_setup_open

      create(:dash_google_account)
      expect(presenter.state).to eq(:connected)
      expect(presenter).not_to be_setup_open
    end
  end

  describe "the reasons a button is switched off" do
    it "gives the feature's own reason first, the same one for sync, backfill and fill" do
      search_console_switched_off!(unavailable_reason: "Search Console is off.")
      create(:dash_google_account)
      stored(days: 3)

      expect(presenter.sync_reason).to eq("Search Console is off.")
      expect(presenter.backfill_reason).to eq("Search Console is off.")
      expect(presenter.fill_reason).to eq("Search Console is off.")
    end

    it "asks for a property when none is picked" do
      search_console_enabled!
      create(:dash_google_account)
      stored(days: 3)

      expect(presenter.sync_reason).to eq("Pick a property first.")
      expect(presenter.backfill_reason).to eq("Pick a property first.")
      expect(presenter.fill_reason).to eq("Pick a property first.")
    end

    it "lets sync run once a property is picked, and stops the backfill once history is complete" do
      search_console_enabled!
      account = create(:dash_google_account, :with_property, backfilled_to: floor + 30)

      expect(presenter.sync_reason).to be_nil
      expect(presenter.backfill_reason).to be_nil

      account.update!(backfilled_to: floor)
      expect(presenter.backfill_reason).to eq("Everything Google still keeps is already here.")
    end

    it "says a fill is going, or that the missing days are gone" do
      search_console_enabled!
      create(:dash_google_account, :with_property)
      stored(days: 3)
      queue = instance_double(AhoyDashboard::SearchConsole::FillQueue, running?: true)
      allow(AhoyDashboard::SearchConsole::FillQueue).to receive(:load).and_return(queue)
      expect(presenter.fill_reason).to eq("A fill is already going.")

      allow(queue).to receive(:running?).and_return(false)
      missing = instance_double(AhoyDashboard::SearchConsoleMissingDaysQuery::Record, fillable_days: 0)
      allow(AhoyDashboard::SearchConsoleMissingDaysQuery).to receive(:call).and_return(missing)
      expect(presenter.fill_reason).to eq("Those days are gone. Google stopped serving them.")

      allow(missing).to receive(:fillable_days).and_return(4)
      expect(presenter.fill_reason).to be_nil
    end
  end

  describe "#missing" do
    it "only looks for holes once something is stored" do
      stored(days: 0)
      allow(AhoyDashboard::SearchConsoleMissingDaysQuery).to receive(:call)

      expect(presenter.missing).to be_nil
      expect(AhoyDashboard::SearchConsoleMissingDaysQuery).not_to have_received(:call)
    end
  end

  describe "#summary" do
    it "says nothing when nothing is stored and nothing is connected" do
      stored(days: 0)

      expect(presenter.summary).to be_nil
    end

    it "gives the stored range, and whether it is up to date" do
      stored(days: 3)
      expect(presenter.summary).to eq("Sep 1 to Sep 6.")

      stored(days: 3, expected: Date.new(2026, 9, 6))
      expect(presenter.summary).to eq("Sep 1 to Sep 6, up to date.")
    end

    it "says how far back history reaches once connected" do
      stored(days: 0)
      account = create(:dash_google_account, :with_property)
      expect(presenter.summary).to eq("Older history has not been pulled yet.")

      account.update!(backfilled_to: floor + 1)
      expect(presenter.summary).to eq("History reaches back to May 14, 2025, 1 day short of May 13, 2025.")

      account.update!(backfilled_to: floor + 3)
      expect(presenter.summary).to eq("History reaches back to May 16, 2025, 3 days short of May 13, 2025.")

      account.update!(backfilled_to: floor - 2)
      expect(presenter.summary).to eq("History is complete back to May 13, 2025.")
    end
  end

  describe "the rest of the screen" do
    it "says why nothing has synced" do
      search_console_enabled!
      expect(presenter.empty_hint).to eq("Connect an account and pick a property. The first sync brings back a week.")

      allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(false)
      expect(presenter.empty_hint).to eq("Nothing syncs while Search Console is off.")
    end

    it "is broken when the last sync failed and the feature is on" do
      search_console_enabled!
      create(:dash_google_account, last_error: "invalid_grant")

      expect(presenter).to be_broken
    end

    it "finds the stored secret being removed, and only a stored one" do
      store_google_client(client_secret: "")

      expect(presenter(remove: "client_id").removing.key).to eq(:client_id)
      expect(presenter(remove: "client_secret").removing).to be_nil
      expect(presenter.secrets.keys).to eq(%i[client_id client_secret])
    end

    it "builds the redirect from the callback" do
      expect(presenter.redirect_uri).to eq(SearchConsoleFixtures::REDIRECT_URI)
    end
  end
end
