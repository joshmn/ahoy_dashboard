require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Period do
  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def range_for(key, **options)
    described_class.find(key).range(now: Time.current, **options)
  end

  describe "the registry" do
    it "lists the period menu in plausible's order" do
      expect(described_class::ALL.map(&:key)).to eq(
        %w[realtime day yesterday 7d 28d 30d month last_month 6mo 12mo year all custom]
      )
    end

    it "finds a period by key and hands its key back as the param" do
      period = described_class.find("30d")

      expect(period.label).to eq("Last 30 days")
      expect(period.to_param).to eq("30d")
    end

    it "raises for a key nobody registered" do
      expect { described_class.find("last_fortnight") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "defaults every period to an interval it actually allows" do
      described_class::ALL.each do |period|
        expect(period.intervals.map(&:to_sym)).to include(period.interval.to_sym),
          "#{period.key} defaults to #{period.interval}, which is not in its own interval list"
      end
    end

    it "knows which two periods are special" do
      expect(described_class.find("custom")).to be_custom
      expect(described_class.find("realtime")).to be_realtime
      expect(described_class.find("30d")).not_to be_custom
      expect(described_class.find("30d")).not_to be_realtime
    end
  end

  describe "#range" do
    {
      "day" => [ [ 2026, 8, 11 ], [ 2026, 8, 11 ] ],
      "yesterday" => [ [ 2026, 8, 10 ], [ 2026, 8, 10 ] ],
      "7d" => [ [ 2026, 8, 5 ], [ 2026, 8, 11 ] ],
      "28d" => [ [ 2026, 7, 15 ], [ 2026, 8, 11 ] ],
      "30d" => [ [ 2026, 7, 13 ], [ 2026, 8, 11 ] ],
      "month" => [ [ 2026, 8, 1 ], [ 2026, 8, 11 ] ],
      "last_month" => [ [ 2026, 7, 1 ], [ 2026, 7, 31 ] ],
      "6mo" => [ [ 2026, 3, 1 ], [ 2026, 8, 11 ] ],
      "12mo" => [ [ 2025, 9, 1 ], [ 2026, 8, 11 ] ],
      "year" => [ [ 2026, 1, 1 ], [ 2026, 8, 11 ] ]
    }.each do |key, (first, last)|
      it "runs #{key} from #{first.join('-')} to #{last.join('-')}" do
        range = range_for(key)

        expect(range.begin).to eq(zone.local(*first).beginning_of_day)
        expect(range.end).to be_within(1.second).of(zone.local(*last).end_of_day)
      end
    end

    it "runs realtime over the last half hour" do
      range = range_for("realtime")

      expect(range.begin).to be_within(1.second).of(now - 30.minutes)
      expect(range.end).to be_within(1.second).of(now)
    end

    it "starts all time at the first visit on record" do
      create(:ahoy_visit, started_at: zone.local(2026, 6, 5, 9, 15))

      expect(range_for("all").begin).to eq(zone.local(2026, 6, 5).beginning_of_day)
    end

    it "starts all time today when nothing is on record" do
      expect(range_for("all").begin).to eq(zone.local(2026, 8, 11).beginning_of_day)
    end

    it "parses a custom range off two dates" do
      range = range_for("custom", from: "2026-07-02", to: "2026-07-09")

      expect(range.begin).to eq(zone.local(2026, 7, 2).beginning_of_day)
      expect(range.end).to be_within(1.second).of(zone.local(2026, 7, 9).end_of_day)
    end

    it "parses a custom range off two times, stopping at the second" do
      range = range_for("custom", from: "2026-08-10T09:00", to: "2026-08-10T17:00")

      expect(range.begin).to eq(zone.local(2026, 8, 10, 9))
      expect(range.end).to be_within(1.second).of(zone.local(2026, 8, 10, 17))
      expect(range.end).to be < zone.local(2026, 8, 10, 17)
    end

    it "keeps the minutes of a time" do
      range = range_for("custom", from: "2026-08-10T09:40", to: "2026-08-10T09:55")

      expect(range.begin).to eq(zone.local(2026, 8, 10, 9, 40))
      expect(range.end).to be_within(1.second).of(zone.local(2026, 8, 10, 9, 55))
    end

    it "takes a date on one side and a time on the other" do
      range = range_for("custom", from: "2026-08-09", to: "2026-08-10T05:00")

      expect(range.begin).to eq(zone.local(2026, 8, 9))
      expect(range.end).to be_within(1.second).of(zone.local(2026, 8, 10, 5))
    end

    # This is a URL people edit by hand, so a broken custom range has to land
    # somewhere sane rather than raising in front of them.
    it "falls back to thirty days on a custom range it cannot parse" do
      [
        {},
        { from: nil, to: nil },
        { from: "not-a-date", to: "2026-07-09" },
        { from: "2026-07-02", to: "" },
        { from: "2026-13-45", to: "2026-07-09" },
        { from: "2026-08-10T25:00", to: "2026-08-10T17:00" },
        { from: "2026-08-10T17:00", to: "2026-08-10T09:00" },
        { from: "2026-08-10T09:00", to: "2026-08-10T09:00" },
        { from: "2026-08-10T9", to: "2026-08-10T17:00" }
      ].each do |options|
        range = range_for("custom", **options)

        expect(range.begin).to eq(zone.local(2026, 7, 13).beginning_of_day),
          "expected #{options.inspect} to fall back to the 30d range"
      end
    end

    # Everything downstream buckets and labels in this zone. A range built in
    # UTC moves every boundary five or six hours and nothing else notices.
    it "computes in the telemetry time zone" do
      expect(range_for("day").begin.time_zone).to eq(AhoyDashboard.time_zone)
      expect(range_for("day").end.time_zone).to eq(AhoyDashboard.time_zone)
    end
  end

  describe "#comparison_range" do
    it "walks back one whole period" do
      period = described_class.find("yesterday")
      comparison = period.comparison_range(period.range(now: now), :previous_period)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 8, 9).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 8, 10).beginning_of_day)
    end

    it "walks a seven day period back seven days and stops where today has got to" do
      period = described_class.find("7d")
      comparison = period.comparison_range(period.range(now: now), :previous_period, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 7, 29).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 8, 4, 14, 30))
    end

    it "compares today so far with yesterday by the same hour" do
      period = described_class.find("day")
      comparison = period.comparison_range(period.range(now: now), :previous_period, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 8, 10).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 8, 10, 14, 30))
    end

    it "compares the month so far with the same stretch of days before it" do
      period = described_class.find("month")
      comparison = period.comparison_range(period.range(now: now), :previous_period, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 7, 21).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 7, 31, 14, 30))
    end

    it "cuts year over year at the same hour when the range is still running" do
      period = described_class.find("day")
      comparison = period.comparison_range(period.range(now: now), :year_over_year, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2025, 8, 11).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2025, 8, 11, 14, 30))
    end

    it "leaves a finished range whole" do
      period = described_class.find("last_month")
      comparison = period.comparison_range(period.range(now: now), :previous_period, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 5, 31).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 6, 30).end_of_day)
    end

    it "leaves a custom range that ended before now whole" do
      period = described_class.find("custom")
      range = period.range(now: now, from: "2026-08-01", to: "2026-08-05")
      comparison = period.comparison_range(range, :previous_period, now: now)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2026, 7, 27).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2026, 7, 31).end_of_day)
    end

    it "walks back a year for year over year" do
      period = described_class.find("yesterday")
      comparison = period.comparison_range(period.range(now: now), :year_over_year)

      expect(comparison.begin).to be_within(1.second).of(zone.local(2025, 8, 10).beginning_of_day)
      expect(comparison.end).to be_within(1.second).of(zone.local(2025, 8, 10).end_of_day)
    end

    it "has nothing to compare realtime against" do
      period = described_class.find("realtime")

      expect(period.comparison_range(period.range(now: now), :previous_period)).to be_nil
      expect(period.comparison_range(period.range(now: now), :year_over_year)).to be_nil
    end
  end

  describe "#running?" do
    it "knows which ranges are still going" do
      expect(described_class.find("day").running?(range_for("day"), now: now)).to be(true)
      expect(described_class.find("30d").running?(range_for("30d"), now: now)).to be(true)
      expect(described_class.find("yesterday").running?(range_for("yesterday"), now: now)).to be(false)
      expect(described_class.find("last_month").running?(range_for("last_month"), now: now)).to be(false)
      expect(described_class.find("realtime").running?(range_for("realtime"), now: now)).to be(false)
    end
  end

  describe "#comparison_phrase" do
    def phrase(key, mode, **options)
      period = described_class.find(key)

      period.comparison_phrase(period.range(now: now, **options), mode, now: now)
    end

    it "says what a running range is being held against" do
      expect(phrase("day", :previous_period)).to eq("yesterday by this hour")
      expect(phrase("30d", :previous_period)).to eq("the 30 days before, same elapsed time")
      expect(phrase("month", :previous_period)).to eq("the 11 days before, same elapsed time")
      expect(phrase("day", :year_over_year)).to eq("this day last year by this hour")
      expect(phrase("7d", :year_over_year)).to eq("the same 7 days last year, same elapsed time")
    end

    it "says what a finished range is being held against" do
      expect(phrase("yesterday", :previous_period)).to eq("the day before")
      expect(phrase("last_month", :previous_period)).to eq("the 31 days before")
      expect(phrase("yesterday", :year_over_year)).to eq("the same day last year")
      expect(phrase("last_month", :year_over_year)).to eq("the same 31 days last year")
    end

    it "does not call hours a day" do
      expect(phrase("custom", :previous_period, from: "2026-08-11T09:00", to: "2026-08-11T17:00"))
        .to eq("the period before, same elapsed time")
      expect(phrase("custom", :previous_period, from: "2026-08-10T09:00", to: "2026-08-10T17:00"))
        .to eq("the previous period")
    end

    it "has nothing to say without a comparison" do
      expect(phrase("day", nil)).to be_nil
      expect(phrase("realtime", :previous_period)).to be_nil
    end
  end

  describe "#running_label" do
    it "says today is not over" do
      expect(described_class.find("day").running_label(range_for("day"), now: now)).to eq("Today so far")
      expect(described_class.find("yesterday").running_label(range_for("yesterday"), now: now)).to eq("Yesterday")
      expect(described_class.find("30d").running_label(range_for("30d"), now: now)).to eq("Last 30 days")
    end

    it "says a custom range that reaches past now is not over" do
      custom = described_class.find("custom")
      range = custom.range(now: now, from: "2026-08-10", to: "2026-08-12")

      expect(custom.running_label(range, now: now)).to eq("Aug 10 to Aug 12 so far")
    end
  end

  describe "#label_for" do
    let(:custom) { described_class.find("custom") }

    def label(from, to)
      custom.label_for(custom.range(now: now, from: from, to: to), timed: custom.timed?(from, to))
    end

    it "says what the range covers" do
      period = described_class.find("7d")

      expect(period.label_for(period.range(now: now))).to be_present
    end

    it "names the times of a range that stops short of whole days" do
      expect(label("2026-08-10T09:00", "2026-08-10T17:00")).to eq("Aug 10, 9 AM to 5 PM")
    end

    it "prints minutes only where there are some" do
      expect(label("2026-08-10T09:40", "2026-08-10T10:00")).to eq("Aug 10, 9:40 AM to 10 AM")
      expect(label("2026-08-10T09:05", "2026-08-10T09:10")).to eq("Aug 10, 9:05 AM to 9:10 AM")
    end

    it "says midnight rather than 12 AM" do
      expect(label("2026-08-10T00:00", "2026-08-10T06:00")).to eq("Aug 10, midnight to 6 AM")
      expect(label("2026-08-10T15:00", "2026-08-11T00:00")).to eq("Aug 10, 3 PM to midnight")
    end

    it "names both days when the times cross midnight" do
      expect(label("2026-08-09T21:00", "2026-08-10T03:00")).to eq("Aug 9, 9 PM to Aug 10, 3 AM")
    end

    it "keeps the date wording for a custom range of dates" do
      expect(label("2026-08-03", "2026-08-09")).to eq("Aug 3 to Aug 9")
      expect(custom.timed?("2026-08-03", "2026-08-09")).to be(false)
    end

    it "does not call a range it could not parse timed" do
      expect(custom.timed?("2026-08-10T17:00", "2026-08-10T09:00")).to be(false)
      expect(described_class.find("30d").timed?("2026-08-10T09:00", "2026-08-10T17:00")).to be(false)
    end
  end

  describe "grouping a custom range" do
    let(:custom) { described_class.find("custom") }

    def grouping(from, to)
      range = custom.range(now: now, from: from, to: to)

      [ custom.intervals_for(range), custom.interval_for(nil, range: range) ]
    end

    it "defaults to the finest grouping that fits on the chart" do
      expect(grouping("2026-08-10T09:00", "2026-08-10T11:00").last).to eq(:minute)
      expect(grouping("2026-08-10T09:00", "2026-08-10T16:00").last).to eq(:five_minutes)
      expect(grouping("2026-08-10", "2026-08-10").last).to eq(:five_minutes)
      expect(grouping("2026-08-08", "2026-08-10").last).to eq(:fifteen_minutes)
      expect(grouping("2026-08-04", "2026-08-10").last).to eq(:hour)
      expect(grouping("2026-07-12", "2026-08-10").last).to eq(:day)
      expect(grouping("2024-08-11", "2026-08-10").last).to eq(:week)
    end

    it "offers only the groupings that fit, from finest to coarsest" do
      expect(grouping("2026-08-10", "2026-08-10").first).to eq(%i[five_minutes fifteen_minutes hour day])
      expect(grouping("2026-07-12", "2026-08-10").first).to eq(%i[day week])
    end

    it "keeps a grouping somebody asked for when it fits, and drops it when it does not" do
      range = custom.range(now: now, from: "2026-07-12", to: "2026-08-10")

      expect(custom.interval_for("week", range: range)).to eq(:week)
      expect(custom.interval_for("minute", range: range)).to eq(:day)
    end

    it "leaves the named periods on their own lists" do
      period = described_class.find("7d")

      expect(period.intervals_for(period.range(now: now))).to eq(%i[hour day])
      expect(period.interval_for(nil, range: period.range(now: now))).to eq(:day)
    end
  end
end
