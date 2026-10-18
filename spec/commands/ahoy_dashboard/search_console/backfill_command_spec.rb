require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::BackfillCommand do
  let(:account) { create(:dash_google_account, :with_property) }
  let(:url) { analytics_url }

  let(:now) { Time.utc(2026, 8, 12, 18, 0) }
  let(:window_start) { Date.new(2026, 8, 3) }

  def backfill(**options)
    described_class.call(account: account, now: now, **options)
  end

  it "does nothing while the integration is off" do
    search_console_disabled!

    expect(backfill).to have_key(:skipped)
    expect(a_request(:post, url)).not_to have_been_made
  end

  describe "with the integration on" do
    before { search_console_enabled! }

    it "skips an account that is not ready" do
      account.update!(property_uri: nil)

      expect(backfill[:skipped]).to be_present
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "starts below the nightly window, because that half is already covered" do
      stub_analytics

      result = backfill(days: 5)[:ok]

      expect(result.dates.last).to eq(window_start - 1)
      expect(result.dates.first).to eq(window_start - 5)
    end

    it "leaves Last synced and a failed nightly run's error alone, because it did not pull the recent week" do
      account.record_error!(AhoyDashboard::SearchConsole::IngestCommand::UNREACHABLE_MESSAGE)
      stub_analytics

      expect(backfill(days: 5)).to have_key(:ok)
      expect(account.reload.synced_at).to be_nil
      expect(account.last_error).to eq(AhoyDashboard::SearchConsole::IngestCommand::UNREACHABLE_MESSAGE)
    end

    it "records how far it got so the next run carries on from there" do
      stub_analytics

      backfill(days: 5)

      expect(account.reload.backfilled_to).to eq(window_start - 5)
    end

    it "takes the next slice down on the run after" do
      stub_analytics

      backfill(days: 5)
      result = backfill(days: 5)[:ok]

      expect(result.dates.last).to eq(window_start - 6)
      expect(result.dates.first).to eq(window_start - 10)
    end

    it "writes the days it pulled" do
      stub_analytics([ [ [ "thomson" ], 3.0, 40.0, 0.075, 8.4 ] ])

      result = backfill(days: 2)[:ok]

      expect(result.keywords).to eq(2)
      expect(AhoyDashboard::SearchConsoleKeyword.pluck(:date).sort)
        .to eq([ window_start - 2, window_start - 1 ])
    end

    it "moves past a stretch of days google has nothing for" do
      stub_analytics

      backfill(days: 5)

      expect(AhoyDashboard::SearchConsoleKeyword.count).to eq(0)
      expect(account.reload.backfilled_to).to eq(window_start - 5)
    end

    it "stops at the oldest day google still serves" do
      floor = AhoyDashboard::SearchConsole.earliest_available_date(now: now)
      account.update!(backfilled_to: floor + 2)
      stub_analytics

      result = backfill(days: 30)[:ok]

      expect(result.dates.first).to eq(floor)
      expect(result.dates.last).to eq(floor + 1)
    end

    it "reports itself done once it has reached the floor, and asks google nothing" do
      account.update!(backfilled_to: AhoyDashboard::SearchConsole.earliest_available_date(now: now))

      expect(backfill).to have_key(:done)
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "counts what is left so a caller can see it moving" do
      stub_analytics

      result = backfill(days: 10)[:ok]

      expect(result.dates.first).to eq(Date.new(2026, 7, 24))
      expect(result.remaining).to eq(470)
      expect(result).to be_more
    end

    it "resumes from the oldest day it already has when the watermark is gone" do
      create(:dash_search_console_day, date: Date.new(2026, 6, 1))
      create(:dash_search_console_keyword, date: Date.new(2026, 6, 1))
      stub_analytics

      result = backfill(days: 3)[:ok]

      expect(result.dates.last).to eq(Date.new(2026, 5, 31))
    end

    it "counts a day it reached that came back empty as reached" do
      create(:dash_search_console_day, date: Date.new(2026, 6, 1))
      create(:dash_search_console_keyword, date: Date.new(2026, 6, 20))
      stub_analytics

      result = backfill(days: 3)[:ok]

      expect(result.dates.last).to eq(Date.new(2026, 5, 31))
    end

    it "leaves the watermark alone when the pull fails, so the days are asked for again" do
      account.update!(backfilled_to: window_start)
      stub_request(:post, url).to_timeout

      expect(backfill(days: 5)).to have_key(:failed)
      expect(account.reload.backfilled_to).to eq(window_start)
    end

    it "passes a quota refusal through rather than inventing its own words for it" do
      stub_analytics_refusal(429)

      expect(backfill(days: 5)).to have_key(:rate_limited)
      expect(account.reload.backfilled_to).to be_nil
    end

    describe "a first backfill interrupted after a complete day" do
      before do
        stub_analytics
        stub_request(:post, url)
          .with do |request|
            body = JSON.parse(request.body)
            body["startDate"] == (window_start - 1).to_s &&
              body["dimensions"] == AhoyDashboard::SearchConsole::SLICE_DIMENSIONS
          end
          .to_return(status: 429, body: "{}", headers: json_headers)
      end

      it "keeps the original inferred boundary for the next attempt" do
        backfill(days: 2)

        expect(account.reload.backfilled_to).to eq(window_start)
      end

      it "replays the incomplete window rather than skipping its remaining days" do
        backfill(days: 2)
        stub_analytics

        expect(backfill(days: 2).fetch(:ok).dates).to eq([ window_start - 2, window_start - 1 ])
      end

      it "advances the boundary only after the replay finishes" do
        backfill(days: 2)
        stub_analytics
        backfill(days: 2)

        expect(account.reload.backfilled_to).to eq(window_start - 2)
      end
    end

    describe "an interrupted worker after a complete day" do
      before do
        stub_analytics
        stub_request(:post, url)
          .with { |request| JSON.parse(request.body)["startDate"] == (window_start - 1).to_s }
          .to_raise(IOError.new("worker interrupted"))

        begin
          backfill(days: 2)
        rescue IOError
        end
      end

      it "has already saved the original inferred boundary" do
        expect(account.reload.backfilled_to).to eq(window_start)
      end

      it "replays the interrupted window after restarting" do
        stub_analytics

        expect(backfill(days: 2).fetch(:ok).dates).to eq([ window_start - 2, window_start - 1 ])
      end
    end
  end
end
