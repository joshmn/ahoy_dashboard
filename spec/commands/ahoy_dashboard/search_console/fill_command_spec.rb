require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::FillCommand do
  let(:account) { create(:dash_google_account, :with_property) }
  let(:url) { analytics_url }
  let(:queue) { AhoyDashboard::SearchConsole::FillQueue }
  let(:days) { [ Date.new(2026, 7, 3), Date.new(2026, 7, 4), Date.new(2026, 7, 5) ] }

  def fill
    described_class.call(account: account)
  end

  it "does nothing while the integration is off" do
    search_console_disabled!
    queue.start!(days)

    expect(fill).to have_key(:skipped)
    expect(a_request(:post, url)).not_to have_been_made
  end

  describe "with the integration on" do
    before { search_console_enabled! }

    it "says there is nothing to do when nothing is queued" do
      expect(fill).to have_key(:done)
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "asks for the oldest day first and takes it off the queue" do
      queue.start!(days)
      stub_analytics

      result = fill[:ok]

      expect(result.date).to eq(Date.new(2026, 7, 3))
      expect(result.remaining).to eq(2)
      expect(result.more?).to be(true)
      expect(queue.load.next_date).to eq(Date.new(2026, 7, 4))
    end

    it "asks for one day, not the window around it" do
      queue.start!(days)
      stub_analytics

      fill

      expect(a_request(:post, url).with { |request|
        body = JSON.parse(request.body)
        body["startDate"] == "2026-07-03" && body["endDate"] == "2026-07-03"
      }).to have_been_made.at_least_once
    end

    it "writes all three grains of the day, the same as the nightly run" do
      queue.start!([ Date.new(2026, 7, 3) ])
      stub_analytics([ [ %w[halfway house desktop usa], 2, 30, 0.06, 4.0 ] ],
                     [ [ %w[halfway house desktop usa], 2, 30, 0.06, 4.0 ] ],
                     [ [ %w[desktop usa], 2, 30, 0.06, 4.0 ] ])

      fill

      expect(AhoyDashboard::SearchConsoleRow.where(date: Date.new(2026, 7, 3)).count).to eq(1)
      expect(AhoyDashboard::SearchConsoleKeyword.where(date: Date.new(2026, 7, 3)).count).to eq(1)
      expect(AhoyDashboard::SearchConsoleTotal.where(date: Date.new(2026, 7, 3)).count).to eq(1)
    end

    it "clears the queue once the last day lands" do
      queue.start!([ Date.new(2026, 7, 3) ])
      stub_analytics

      result = fill[:ok]

      expect(result.more?).to be(false)
      expect(queue.load.running?).to be(false)
    end

    it "takes a day Google had nothing for off the queue rather than asking again forever" do
      queue.start!(days)
      stub_analytics

      fill

      expect(queue.load.next_date).to eq(Date.new(2026, 7, 4))
    end

    it "writes down that a day with nothing on it was scanned, so it is never offered again" do
      queue.start!(days)
      stub_analytics

      fill

      expect(AhoyDashboard::SearchConsoleDay.where(date: Date.new(2026, 7, 3))).to exist
      expect(AhoyDashboard::SearchConsoleTotal.where(date: Date.new(2026, 7, 3))).not_to exist
      expect(AhoyDashboard::SearchConsoleMissingDaysQuery.call.dates).not_to include(Date.new(2026, 7, 3))
    end

    it "does not mark a day scanned when Google never answered for it" do
      queue.start!(days)
      stub_analytics_refusal(429, body: "quota")

      fill

      expect(AhoyDashboard::SearchConsoleDay.count).to be_zero
    end

    it "does not touch Last synced, because it did not pull the recent week" do
      queue.start!(days)
      stub_analytics

      fill

      expect(account.reload.synced_at).to be_nil
    end

    it "leaves the day on the queue when Google refuses, so pressing the button again picks it up" do
      queue.start!(days)
      stub_analytics_refusal(429, body: "quota")

      expect(fill).to have_key(:rate_limited)
      expect(queue.load.next_date).to eq(Date.new(2026, 7, 3))
      expect(queue.load.remaining).to eq(3)
    end

    it "passes the reason on rather than writing a second, worse version of it" do
      queue.start!(days)
      stub_analytics_refusal(429, body: "quota")

      fill

      expect(account.reload.last_error).to eq(AhoyDashboard::SearchConsole::IngestCommand::QUOTA_MESSAGE)
    end
  end
end
