require "rails_helper"
require "support/ahoy_dashboard/fixtures"

# This replaced groupdate, so it is held to the two things that were the reason
# not to replace it: a day is not always 24 hours, and a dashboard week does not
# start where Postgres thinks it does.
RSpec.describe AhoyDashboard::Sql::Buckets do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:zone) { AhoyDashboard.time_zone }

  def series(range, interval)
    described_class.series(range, interval)
  end

  def counted(range, interval)
    described_class.fill(
      AhoyDashboard.visit.where(started_at: range)
        .group(described_class.sql('"ahoy_visits"."started_at"', interval)).count,
      range, interval
    )
  end

  it "is reading a zone that actually shifts, or none of the rest means anything" do
    expect(zone.tzinfo.name).to eq("America/Chicago")
  end

  describe "the series across a clock change" do
    # 2026-03-08 loses an hour at 2am, 2026-11-01 gains one back.
    it "gives a short day 23 hours and a long day 25" do
      forward = zone.local(2026, 3, 8)
      back = zone.local(2026, 11, 1)

      expect(series(forward..forward.end_of_day, :hour).size).to eq(23)
      expect(series(back..back.end_of_day, :hour).size).to eq(25)
    end

    it "still counts each of those as one day" do
      forward = zone.local(2026, 3, 8)
      back = zone.local(2026, 11, 1)

      expect(series(forward..forward.end_of_day, :day).size).to eq(1)
      expect(series(back..back.end_of_day, :day).size).to eq(1)
    end

    it "steps a month by the calendar rather than by a length" do
      january = zone.local(2026, 1, 1)

      expect(series(january..zone.local(2026, 12, 31, 23, 59, 59), :month).size).to eq(12)
      expect(series(zone.local(2026, 2, 1)..zone.local(2026, 2, 28, 23, 59, 59), :day).size).to eq(28)
      expect(series(zone.local(2028, 2, 1)..zone.local(2028, 2, 29, 23, 59, 59), :day).size).to eq(29)
    end
  end

  describe "where a week starts" do
    # Postgres truncates a week to Monday. This one starts Sunday, and getting
    # it wrong shifts every weekly chart by a day without erroring.
    it "starts the bucket on the Sunday on or before the range" do
      # 2026-08-12 is a Wednesday.
      first = series(zone.local(2026, 8, 12)..zone.local(2026, 8, 20), :week).first

      expect(first).to eq(zone.local(2026, 8, 9))
      expect(first.strftime("%A")).to eq("Sunday")
    end

    it "puts a Saturday and the Sunday after it in different weeks" do
      saturday = zone.local(2026, 8, 15, 12)
      sunday = zone.local(2026, 8, 16, 12)

      expect(described_class.truncate(saturday, :week)).to eq(zone.local(2026, 8, 9))
      expect(described_class.truncate(sunday, :week)).to eq(zone.local(2026, 8, 16))
    end
  end

  describe "grouping rows" do
    it "keeps a whole short day in that day's bucket" do
      range = zone.local(2026, 3, 8)..zone.local(2026, 3, 8).end_of_day
      [ 1, 3, 23 ].each_with_index do |hour, n|
        dash_visit(started_at: zone.local(2026, 3, 8, hour, 30), visitor: "v#{n}")
      end

      expect(counted(range, :day).values.sum).to eq(3)
      expect(counted(range, :day).keys).to eq([ zone.local(2026, 3, 8) ])
    end

    # The hour either side of a spring forward is a different bucket, and the
    # hour that does not exist locally is not one at all.
    it "separates the hours either side of a clock change" do
      range = zone.local(2026, 3, 8)..zone.local(2026, 3, 8).end_of_day
      dash_visit(started_at: zone.local(2026, 3, 8, 1, 30), visitor: "before")
      dash_visit(started_at: zone.local(2026, 3, 8, 3, 30), visitor: "after")

      filled = counted(range, :hour).reject { |_bucket, count| count.zero? }

      expect(filled.values).to eq([ 1, 1 ])
      expect(filled.keys.map { |time| time.strftime("%H") }).to eq([ "01", "03" ])
    end

    it "reads the boundary in the dashboard's zone, not in utc" do
      # 23:30 local on 10 August is 04:30 UTC on the 11th.
      range = zone.local(2026, 8, 10)..zone.local(2026, 8, 10).end_of_day
      dash_visit(started_at: zone.local(2026, 8, 10, 23, 30), visitor: "late")

      expect(counted(range, :day)).to eq({ zone.local(2026, 8, 10) => 1 })
    end
  end

  describe "five and fifteen minute buckets" do
    let(:range) { zone.local(2026, 8, 10, 9)..zone.local(2026, 8, 10, 9, 59, 59) }

    it "cuts an hour into twelve and four" do
      expect(series(range, :five_minutes).size).to eq(12)
      expect(series(range, :fifteen_minutes).map { |time| time.strftime("%H:%M") }).to eq(%w[09:00 09:15 09:30 09:45])
    end

    it "starts at the bucket the range begins inside" do
      late = zone.local(2026, 8, 10, 9, 7)..zone.local(2026, 8, 10, 9, 20)

      expect(series(late, :five_minutes).first).to eq(zone.local(2026, 8, 10, 9, 5))
      expect(series(late, :fifteen_minutes).first).to eq(zone.local(2026, 8, 10, 9))
    end

    it "puts each row in the bucket the series says holds it" do
      dash_visit(started_at: zone.local(2026, 8, 10, 9, 4, 59), visitor: "a")
      dash_visit(started_at: zone.local(2026, 8, 10, 9, 5), visitor: "b")
      dash_visit(started_at: zone.local(2026, 8, 10, 9, 44), visitor: "c")

      five = counted(range, :five_minutes)
      fifteen = counted(range, :fifteen_minutes)

      expect(five.reject { |_bucket, count| count.zero? }.transform_keys { |time| time.strftime("%H:%M") })
        .to eq("09:00" => 1, "09:05" => 1, "09:40" => 1)
      expect(fifteen.values).to eq([ 2, 0, 1, 0 ])
    end
  end

  describe "filling the gaps" do
    it "hands back every bucket in the range, empty ones included" do
      range = zone.local(2026, 8, 10)..zone.local(2026, 8, 12).end_of_day
      dash_visit(started_at: zone.local(2026, 8, 11, 9), visitor: "only")

      expect(counted(range, :day).values).to eq([ 0, 1, 0 ])
    end

    it "keeps the buckets in order" do
      range = zone.local(2026, 8, 1)..zone.local(2026, 8, 31).end_of_day
      keys = counted(range, :day).keys

      expect(keys).to eq(keys.sort)
      expect(keys.size).to eq(31)
    end

    it "takes a default other than zero" do
      range = zone.local(2026, 8, 10)..zone.local(2026, 8, 11).end_of_day

      expect(described_class.fill({}, range, :day, default: nil).values).to eq([ nil, nil ])
    end
  end

  describe "the sql it groups by" do
    it "reads day, week and month as dates and the rest as instants" do
      %i[day week month].each do |interval|
        expect(described_class.sql("x", interval).to_s).to end_with("::date")
      end

      %i[minute five_minutes fifteen_minutes hour].each do |interval|
        expect(described_class.sql("x", interval).to_s).to include("AT TIME ZONE 'America/Chicago'")
        expect(described_class.sql("x", interval).to_s).not_to end_with("::date")
      end
    end

    it "refuses an interval it does not have" do
      expect { described_class.truncate(Time.current, :fortnight) }.to raise_error(ArgumentError, /fortnight/)
    end
  end

  describe ".elapsed" do
    let(:now) { zone.local(2026, 8, 11, 14, 30) }

    it "keeps the bucket that is still filling in and drops the ones that have not started" do
      pairs = 24.times.map { |hour| [ now.change(hour: hour), hour ] }

      expect(described_class.elapsed(pairs, now: now).map(&:last)).to eq((0..14).to_a)
    end

    it "keeps a day bucket that is today" do
      pairs = [ [ now.beginning_of_day - 1.day, 1 ], [ now.beginning_of_day, 2 ], [ now.beginning_of_day + 1.day, 3 ] ]

      expect(described_class.elapsed(pairs, now: now).map(&:last)).to eq([ 1, 2 ])
    end

    it "leaves a finished series alone" do
      pairs = 3.times.map { |day| [ now.beginning_of_day - (5 - day).days, day ] }

      expect(described_class.elapsed(pairs, now: now)).to eq(pairs)
    end
  end
end
