require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsole::IngestCommand do
  let(:account) do
    create(:dash_google_account, :with_property, access_token: "good", expires_at: 30.minutes.from_now)
  end
  let(:url) { analytics_url }
  let(:date) { Date.new(2026, 8, 9) }

  # All three calls go to the same URL and are told apart only by the dimensions
  # they carry: query and page, query alone, or none at all.
  def stub_day(queries:, total:, keywords: nil)
    slices = AhoyDashboard::SearchConsole::SLICE_DIMENSIONS

    stub_dimensions(AhoyDashboard::SearchConsole::QUERY_DIMENSIONS + slices, sliced(queries, 2))
    stub_dimensions(AhoyDashboard::SearchConsole::KEYWORD_DIMENSIONS + slices, sliced(keywords || rolled_up(queries), 1))
    stub_dimensions(slices, sliced(total, 0))
  end

  def sliced(rows, width)
    rows.map do |keys, *metrics|
      keys = Array(keys)

      [ keys.size == width ? keys + %w[DESKTOP usa] : keys, *metrics ]
    end
  end

  def stub_dimensions(dimensions, rows)
    stub_request(:post, url)
      .with { |sent| JSON.parse(sent.body)["dimensions"].to_a == dimensions }
      .to_return(status: 200, body: analytics_body(rows).to_json, headers: json_headers)
  end

  # What Google would answer at query grain if it withheld nothing, which it
  # does, which is why the two are asked for separately in the first place.
  def rolled_up(rows)
    rows.map do |keys, *metrics|
      keys = Array(keys)

      [ [ keys.first, *keys.drop(2) ], *metrics ]
    end
  end

  it "does nothing while the integration is off" do
    search_console_disabled!

    events = described_class.call(account: account, dates: [ date ])

    expect(events).to have_key(:skipped)
    expect(a_request(:post, url)).not_to have_been_made
  end

  describe "with the integration on" do
    before { search_console_enabled! }

    it "skips an account with no refresh token" do
      events = described_class.call(account: create(:dash_google_account, :unconnected), dates: [ date ])

      expect(events[:skipped]).to include("not connected")
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "skips an account with no property picked" do
      account.update!(property_uri: nil)

      events = described_class.call(account: account, dates: [ date ])

      expect(events[:skipped]).to include("property")
    end

    it "writes the query breakdown and the day totals" do
      stub_day(
        queries: [ [ [ "thomson", "https://example.com/a" ], 3.0, 40.0, 0.075, 8.4 ] ],
        total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ]
      )

      events = described_class.call(account: account, dates: [ date ])

      row = sole_item(AhoyDashboard::SearchConsoleRow)
      expect(row.date).to eq(date)
      expect(row.query).to eq("thomson")
      expect(row.page).to eq("https://example.com/a")
      expect(row.clicks).to eq(3)
      expect(row.impressions).to eq(40)
      expect(row.ctr).to be_within(0.0001).of(0.075)
      expect(row.position).to be_within(0.0001).of(8.4)

      total = sole_item(AhoyDashboard::SearchConsoleTotal)
      expect(total.date).to eq(date)
      expect(total.clicks).to eq(12)
      expect(total.impressions).to eq(300)

      expect(events[:ok].rows).to eq(1)
      expect(events[:ok].totals).to eq(1)
    end

    # The third grain, and the one a keyword trend is read from. Asked for on its
    # own rather than summed out of the breakdown, because Google withholds far
    # more when the page is part of the question.
    it "writes the keyword grain from its own call" do
      stub_day(
        queries: [ [ [ "thomson", "https://example.com/a" ], 3.0, 40.0, 0.075, 8.4 ] ],
        keywords: [ [ [ "thomson" ], 9.0, 220.0, 0.041, 7.1 ] ],
        total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ]
      )

      events = described_class.call(account: account, dates: [ date ])

      keyword = sole_item(AhoyDashboard::SearchConsoleKeyword)
      expect(keyword.date).to eq(date)
      expect(keyword.query).to eq("thomson")
      expect(keyword.clicks).to eq(9)
      expect(keyword.impressions).to eq(220)
      expect(keyword.position).to be_within(0.0001).of(7.1)

      expect(events[:ok].keywords).to eq(1)
      expect(a_request(:post, url)
        .with { |sent| JSON.parse(sent.body)["dimensions"] == %w[query device country] }).to have_been_made.once
    end

    # The keyword grain is not a rollup of the breakdown and must not be stored
    # as one, or every day the page split was withheld reads as a day the keyword
    # went quiet.
    it "keeps a keyword google withheld at query x page grain" do
      stub_day(
        queries: [],
        keywords: [ [ [ "halfway house rules" ], 4.0, 80.0, 0.05, 12.0 ] ],
        total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ]
      )

      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleRow.count).to eq(0)
      expect(sole_item(AhoyDashboard::SearchConsoleKeyword).query).to eq("halfway house rules")
    end

    it "rewrites a keyword day it has already stored" do
      stub_day(queries: [], keywords: [ [ [ "thomson" ], 3.0, 40.0, 0.075, 8.4 ] ], total: [])
      described_class.call(account: account, dates: [ date ])

      WebMock.reset!
      stub_day(queries: [], keywords: [ [ [ "thomson" ], 9.0, 91.0, 0.098, 6.1 ] ], total: [])
      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleKeyword.count).to eq(1)
      expect(sole_item(AhoyDashboard::SearchConsoleKeyword).clicks).to eq(9)
    end

    # Google keeps revising recent days, so a second run over the same day has to
    # rewrite what is there rather than duplicate it or skip it.
    it "rewrites a day it has already stored" do
      stub_day(queries: [ [ %w[thomson /a], 3.0, 40.0, 0.075, 8.4 ] ], total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ])
      described_class.call(account: account, dates: [ date ])

      WebMock.reset!
      stub_day(queries: [ [ %w[thomson /a], 9.0, 91.0, 0.098, 6.1 ] ], total: [ [ [], 20.0, 400.0, 0.05, 8.0 ] ])
      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleRow.count).to eq(1)
      expect(sole_item(AhoyDashboard::SearchConsoleRow).clicks).to eq(9)
      expect(AhoyDashboard::SearchConsoleTotal.count).to eq(1)
      expect(sole_item(AhoyDashboard::SearchConsoleTotal).clicks).to eq(20)
    end

    it "stores the device and country google split each grain by" do
      stub_day(
        queries: [
          [ [ "thomson", "https://example.com/a", "MOBILE", "usa" ], 3.0, 40.0, 0.075, 8.4 ],
          [ [ "thomson", "https://example.com/a", "DESKTOP", "can" ], 1.0, 10.0, 0.1, 5.0 ]
        ],
        total: [ [ %w[MOBILE usa], 9.0, 200.0, 0.045, 7.0 ], [ %w[TABLET gbr], 1.0, 20.0, 0.05, 3.0 ] ]
      )

      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleRow.order(:device).pluck(:device, :country)).to eq([ %w[desktop can], %w[mobile usa] ])
      expect(AhoyDashboard::SearchConsoleKeyword.order(:device).pluck(:query, :device, :country))
        .to eq([ %w[thomson desktop can], %w[thomson mobile usa] ])
      expect(AhoyDashboard::SearchConsoleTotal.order(:device).pluck(:device, :country, :clicks))
        .to eq([ [ "mobile", "usa", 9 ], [ "tablet", "gbr", 1 ] ])
    end

    it "replaces the rows it stored before device and country for a day it pulls again" do
      create(:dash_search_console_row, date: date, query: "thomson", page: "https://example.com/a", clicks: 50)
      create(:dash_search_console_keyword, date: date, query: "thomson", clicks: 50)
      create(:dash_search_console_total, date: date, clicks: 50)
      stub_day(
        queries: [ [ [ "thomson", "https://example.com/a" ], 3.0, 40.0, 0.075, 8.4 ] ],
        total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ]
      )

      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleRow.pluck(:device, :clicks)).to eq([ [ "desktop", 3 ] ])
      expect(AhoyDashboard::SearchConsoleKeyword.pluck(:device, :clicks)).to eq([ [ "desktop", 3 ] ])
      expect(AhoyDashboard::SearchConsoleTotal.pluck(:device, :clicks)).to eq([ [ "desktop", 12 ] ])
    end

    it "keeps the older rows on days it did not pull" do
      create(:dash_search_console_keyword, date: date - 30, query: "thomson", clicks: 50)
      create(:dash_search_console_total, date: date - 30, clicks: 50)
      stub_day(queries: [], total: [])

      described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleKeyword.pluck(:device, :clicks)).to eq([ [ "", 50 ] ])
      expect(AhoyDashboard::SearchConsoleTotal.pluck(:device, :clicks)).to eq([ [ "", 50 ] ])
    end

    it "removes sliced breakdown keys missing from a revised day" do
      create(:dash_search_console_row, date: date, query: "gone", device: "mobile", country: "usa")
      stub_day(queries: [[%w[replacement /new], 1, 10, 0.1, 2]], total: [])

      described_class.call(account: account, dates: [date])

      expect(AhoyDashboard::SearchConsoleRow.pluck(:query)).to eq(["replacement"])
    end

    it "removes sliced keyword keys missing from a revised day" do
      create(:dash_search_console_keyword, date: date, query: "gone", device: "mobile", country: "usa")
      stub_day(queries: [], keywords: [], total: [])

      described_class.call(account: account, dates: [date])

      expect(AhoyDashboard::SearchConsoleKeyword.where(date: date)).to be_empty
    end

    it "removes sliced totals when a revised day becomes empty" do
      create(:dash_search_console_total, date: date, device: "mobile", country: "usa")
      stub_day(queries: [], total: [])

      described_class.call(account: account, dates: [date])

      expect(AhoyDashboard::SearchConsoleTotal.where(date: date)).to be_empty
    end

    it "retains every previous grain when the database refuses the final grain" do
      create(:dash_search_console_row, date: date, clicks: 7)
      create(:dash_search_console_keyword, date: date, clicks: 8)
      create(:dash_search_console_total, date: date, clicks: 9)
      stub_day(queries: [[%w[new /new], 1, 10, 0.1, 2]], total: [[[], 10**30, 30, 0.1, 2]])

      described_class.call(account: account, dates: [date])

      expect([AhoyDashboard::SearchConsoleRow, AhoyDashboard::SearchConsoleKeyword,
              AhoyDashboard::SearchConsoleTotal].map { |model| model.where(date: date).pluck(:clicks) })
        .to eq([[7], [8], [9]])
    end

    it "does not mark a rejected snapshot scanned" do
      stub_day(queries: [], total: [[[], 10**30, 30, 0.1, 2]])

      described_class.call(account: account, dates: [date])

      expect(AhoyDashboard::SearchConsoleDay.where(date: date)).to be_empty
    end

    it "retains the previous snapshot if the final API request fails" do
      create(:dash_search_console_row, date: date, clicks: 7)
      stub_day(queries: [[%w[new /new], 1, 10, 0.1, 2]], total: [])
      stub_request(:post, url)
        .with { |sent| JSON.parse(sent.body)["dimensions"] == AhoyDashboard::SearchConsole::SLICE_DIMENSIONS }
        .to_return(status: 429, body: "{}", headers: json_headers)

      described_class.call(account: account, dates: [date])

      expect(AhoyDashboard::SearchConsoleRow.where(date: date).pluck(:clicks)).to eq([7])
    end

    it "defaults to the last seven finished days" do
      travel_to(Time.utc(2026, 8, 12, 18, 0)) do
        stub_day(queries: [], total: [])

        events = described_class.call(account: account)

        expect(events[:ok].dates).to eq((Date.new(2026, 8, 3)..Date.new(2026, 8, 9)).to_a)
      end
    end

    it "asks for final numbers unless it is told otherwise" do
      stub_day(queries: [], total: [])

      described_class.call(account: account, dates: [ date ])

      expect(a_request(:post, url).with { |sent| JSON.parse(sent.body)["dataState"] == "final" })
        .to have_been_made.at_least_once
    end

    it "stamps the account and clears an old error" do
      account.record_error!("yesterday's failure")
      stub_day(queries: [], total: [])

      described_class.call(account: account, dates: [ date ])

      expect(account.reload.synced_at).to be_present
      expect(account.last_error).to be_nil
    end

    it "writes nothing for a day google has no rows for" do
      stub_day(queries: [], total: [])

      events = described_class.call(account: account, dates: [ date ])

      expect(AhoyDashboard::SearchConsoleRow.count).to eq(0)
      expect(AhoyDashboard::SearchConsoleTotal.count).to eq(0)
      expect(events[:ok].rows).to eq(0)
    end

    # One day's batch is one statement, so the database can refuse the whole day
    # over a single row. That used to end the run: the sum aborted, every later
    # date was thrown away, and because an ActiveRecord::StatementInvalid is not
    # a SearchConsole::Error the exception escaped every rescue, so nothing
    # reached the account and the settings screen said all was well.
    describe "a day the database refuses" do
      let(:bad) { Date.new(2026, 8, 8) }
      let(:good) { Date.new(2026, 8, 9) }

      before do
        stub_day(queries: [ [ %w[thomson /a], 3.0, 40.0, 0.075, 8.4 ] ], total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ])

        # A statement Postgres really refuses, rather than a bare raise, so the
        # run has to cope with the aborted transaction it actually leaves behind.
        allow(AhoyDashboard::SearchConsoleRow).to receive(:absorb).and_wrap_original do |original, rows|
          AhoyDashboard::SearchConsoleRow.connection.execute("select 1 / 0") if rows.any? { |row| row[:date] == bad }

          original.call(rows)
        end
      end

      def ingest
        described_class.call(account: account, dates: [ bad, good ])
      end

      it "stores every other day in the window" do
        ingest

        expect(AhoyDashboard::SearchConsoleRow.pluck(:date)).to eq([ good ])
      end

      it "counts only what it managed to write" do
        expect(ingest[:failed]).to be_present
        expect(AhoyDashboard::SearchConsoleRow.count).to eq(1)
      end

      it "records the reason on the account so the settings screen can say so" do
        ingest

        expect(account.reload.last_error).to eq(described_class::REFUSED_MESSAGE)
      end

      it "still stamps the sync, because the rest of the week did land" do
        ingest

        expect(account.reload.synced_at).to be_present
      end

      it "names the day it lost instead of raising" do
        events = nil

        expect { events = ingest }.not_to raise_error
        expect(events[:failed]).to include(bad.to_s)
      end
    end

    it "reports a quota refusal as its own outcome and says the next run picks it up" do
      stub_request(:post, url).to_return(status: 429, body: "{}", headers: json_headers)

      events = described_class.call(account: account, dates: [ date ])

      expect(events).to have_key(:rate_limited)
      expect(account.reload.last_error).to eq(described_class::QUOTA_MESSAGE)
    end

    it "reports an unreachable google without raising" do
      stub_request(:post, url).to_timeout

      events = described_class.call(account: account, dates: [ date ])

      expect(events).to have_key(:failed)
      expect(account.reload.last_error).to eq(described_class::UNREACHABLE_MESSAGE)
    end

    it "says the account lost access to the property rather than that google did not answer" do
      stub_request(:post, url).to_return(status: 403, headers: json_headers, body: {
        "error" => { "code" => 403, "message" => "User does not have sufficient permission for site",
                     "errors" => [ { "reason" => "forbidden" } ] }
      }.to_json)

      events = described_class.call(account: account, dates: [ date ])

      expect(events).to have_key(:failed)
      expect(account.reload.last_error).to include("can no longer read example.com")
      expect(account.last_error).not_to eq(described_class::UNREACHABLE_MESSAGE)
    end

    it "leaves the stamp and the error alone when told not to stamp, the way the history pull runs it" do
      account.record_error!(described_class::UNREACHABLE_MESSAGE)
      stub_day(queries: [], total: [])

      events = described_class.call(account: account, dates: [ date ], stamp: false)

      expect(events).to have_key(:ok)
      expect(account.reload.synced_at).to be_nil
      expect(account.last_error).to eq(described_class::UNREACHABLE_MESSAGE)
    end

    describe "the property the stored rows belong to" do
      it "claims the rows for the property it pulls" do
        stub_day(queries: [], total: [])

        described_class.call(account: account, dates: [ date ])

        expect(AhoyDashboard::SearchConsole.stored_property).to eq("sc-domain:example.com")
      end

      it "clears rows another property left behind before writing this one's" do
        AhoyDashboard::SearchConsole.store_property!("sc-domain:other.com")
        create(:dash_search_console_total, date: date - 30)
        create(:dash_search_console_keyword, date: date - 30)
        create(:dash_search_console_row, date: date - 30)
        account.update_columns(backfilled_to: date - 200)
        stub_day(queries: [ [ %w[thomson /a], 3.0, 40.0, 0.075, 8.4 ] ], total: [ [ [], 12.0, 300.0, 0.04, 9.2 ] ])

        described_class.call(account: account, dates: [ date ])

        expect(AhoyDashboard::SearchConsoleTotal.pluck(:date)).to eq([ date ])
        expect(AhoyDashboard::SearchConsoleKeyword.pluck(:date).uniq).to eq([ date ])
        expect(AhoyDashboard::SearchConsoleRow.pluck(:date).uniq).to eq([ date ])
        expect(account.reload.backfilled_to).to be_nil
        expect(AhoyDashboard::SearchConsole.stored_property).to eq("sc-domain:example.com")
      end
    end

    it "leaves the refresh's own reason in place when the token is dead" do
      account.update!(expires_at: 5.minutes.ago)
      stub_token(status: 400, body: { "error" => "invalid_grant" })

      events = described_class.call(account: account, dates: [ date ])

      expect(events).to have_key(:failed)
      expect(account.reload.last_error).to eq(AhoyDashboard::SearchConsole::RefreshTokenService::RECONNECT_MESSAGE)
    end
  end
end
