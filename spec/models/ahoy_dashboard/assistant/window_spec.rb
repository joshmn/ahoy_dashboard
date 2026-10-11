require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Assistant::Window do
  around { |example| travel_to(AhoyDashboard.time_zone.local(2026, 8, 21, 14, 30)) { example.run } }

  def dates(window)
    [ window.range.begin.to_date, window.range.end.to_date ]
  end

  it "counts days inclusive of today, so seven days is seven days" do
    window = described_class.call(days: 7)

    expect(window.days_covered).to eq(7)
    expect(dates(window)).to eq([ Date.new(2026, 8, 15), Date.new(2026, 8, 21) ])
  end

  it "cuts a counted window exactly where the dashboard's own period cuts it" do
    counted = described_class.call(days: 7)
    named = described_class.call(period: "7d")

    expect(dates(counted)).to eq(dates(named))
  end

  it "reads a stretch of dates with both ends included" do
    window = described_class.call(from: "2026-08-10", to: "2026-08-16")

    expect(window.days_covered).to eq(7)
    expect(window.label).to eq("Aug 10 to Aug 16")
    expect(dates(window)).to eq([ Date.new(2026, 8, 10), Date.new(2026, 8, 16) ])
  end

  it "turns a range that reads backwards the right way round" do
    window = described_class.call(from: "2026-08-16", to: "2026-08-10")

    expect(dates(window)).to eq([ Date.new(2026, 8, 10), Date.new(2026, 8, 16) ])
  end

  it "reads one date as that day rather than everything since it" do
    window = described_class.call(from: "2026-08-16")

    expect(window.days_covered).to eq(1)
    expect(dates(window)).to eq([ Date.new(2026, 8, 16), Date.new(2026, 8, 16) ])
  end

  it "lets dates beat a named period, because a stated week is not a menu item" do
    window = described_class.call(period: "30d", from: "2026-08-10", to: "2026-08-16")

    expect(window.days_covered).to eq(7)
  end

  it "carries a named month whole" do
    window = described_class.call(period: "last_month")

    expect(dates(window)).to eq([ Date.new(2026, 7, 1), Date.new(2026, 7, 31) ])
    expect(window.label).to eq("July 2026")
  end

  it "defaults to the same thirty days the dashboard opens on" do
    expect(dates(described_class.call)).to eq(dates(described_class.call(period: "30d")))
  end

  it "refuses a period nobody registered rather than quietly answering about another one" do
    expect { described_class.call(period: "lastweek").range }
      .to raise_error(described_class::UnknownPeriod)
  end

  it "holds a count to a year" do
    expect(described_class.call(days: 4_000).days_covered).to eq(described_class::MAX_DAYS)
  end

  it "ignores a date it cannot read rather than raising" do
    expect(dates(described_class.call(from: "last tuesday", days: 7)))
      .to eq(dates(described_class.call(days: 7)))
  end

  it "hands a link the params that reopen the same window" do
    expect(described_class.call(from: "2026-08-10", to: "2026-08-16").link_params)
      .to eq(period: "custom", from: "2026-08-10", to: "2026-08-16", interval: "day")
    expect(described_class.call(period: "7d").link_params).to eq(period: "7d")
  end

  it "groups a window of dates by day unless it is told otherwise" do
    expect(described_class.call(from: "2026-08-10", to: "2026-08-16").interval).to eq(:day)
    expect(described_class.call(days: 1).interval).to eq(:day)
    expect(described_class.call(from: "2026-08-10", to: "2026-08-16", interval: "hour").interval).to eq(:hour)
  end

  it "follows the period's own interval unless it is told otherwise" do
    expect(described_class.call(period: "12mo").interval).to eq(:month)
    expect(described_class.call(period: "12mo", interval: "week").interval).to eq(:week)
    expect(described_class.call(period: "12mo", interval: "nonsense").interval).to eq(:month)
  end

  describe "what it tells the model it read" do
    let(:slice) do
      AhoyDashboard::Assistant::Slice.new.with([
        { "dimension" => "country", "value" => "US", "group" => 0 },
        { "dimension" => "country", "value" => "CA", "group" => 0 },
        { "dimension" => "page", "value" => "/pricing" }
      ])
    end

    it "labels an or group once, and says it with or and and" do
      window = described_class.call(period: "7d", slice: slice)

      expect(window.to_h[:filters]).to eq([ "(Country is US or CA)", "Page is /pricing" ])
      expect(window.filter_sentence).to eq("(Country is US or CA) and Page is /pricing")
    end

    it "says hidden traffic is left out and names the exclusions doing it" do
      AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                       filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } ])
      read = described_class.call(period: "7d").to_h

      expect(read[:hidden_traffic]).to eq("excluded")
      expect(read[:hidden_by]).to include("Datacenters")
      expect(read).not_to have_key(:internal_addresses)
    end

    it "says hidden traffic is shown when the conversation was showing it" do
      shown = AhoyDashboard::Assistant::Slice.from_context("slice" => { "filters" => "none", "internal" => true })
      read = described_class.call(period: "7d", slice: shown).to_h

      expect(read[:hidden_traffic]).to eq("shown")
      expect(read).not_to have_key(:hidden_by)
    end
  end
end

RSpec.describe AhoyDashboard::Assistant::Tools::Trend do
  around { |example| travel_to(AhoyDashboard.time_zone.local(2026, 8, 21, 14, 30)) { example.run } }

  it "hands back the window's own total, which the daily points do not add up to" do
    token = SecureRandom.uuid
    [ 3.days.ago, 1.day.ago ].each do |at|
      dash_page_view(dash_visit(started_at: at, visitor: token))
    end

    answer = described_class.new.execute(metric: "visitors", days: 7)

    expect(answer[:points].sum { |point| point[:value] }).to eq(2)
    expect(answer[:total][:value]).to eq(1)
    expect(answer[:summing]).to include("do not add the points up")
  end

  it "says so when it can add them up" do
    expect(described_class.new.execute(metric: "pageviews", days: 7)[:summing])
      .to include("adding the points up gives the window total")
  end

  it "gets a count metric's points and independent total in one analytics statement" do
    %w[visitors visits pageviews].each do |metric|
      statements = []
      recorder = ->(*args) do
        payload = args.last
        statements << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(/\b(?:FROM|JOIN)\s+"?ahoy_(?:visits|events)\b/i)
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
        result = described_class.new.execute(metric: metric, days: 7)
        expect(result).not_to have_key(:error)
      end

      expect(statements.size).to eq(1), metric
      expect(statements.first).to include("grouping sets")
    end
  end

  it "reads the window it was asked for, not one a day longer" do
    answer = described_class.new.execute(from: "2026-08-10", to: "2026-08-16")

    expect(answer[:days]).to eq(7)
    expect(answer[:points].size).to eq(7)
  end

  it "offers the windows it knows when handed one it does not" do
    answer = described_class.new.execute(period: "lastweek")

    expect(answer[:error]).to include("lastweek")
    expect(answer[:periods].map { |period| period[:key] }).to include("last_month", "7d")
  end
end
