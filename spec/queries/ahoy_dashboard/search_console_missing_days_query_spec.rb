require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleMissingDaysQuery do
  let(:now) { Time.utc(2026, 8, 12, 18, 0) }
  let(:last_final) { Date.new(2026, 8, 9) }
  let(:floor) { AhoyDashboard::SearchConsole.earliest_available_date(now: now) }

  def store(*dates)
    dates.flatten.each do |date|
      create(:dash_search_console_day, date: date)
      create(:dash_search_console_total, date: date)
    end
  end

  def scan(*dates)
    dates.flatten.each { |date| create(:dash_search_console_day, date: date) }
  end

  def missing
    described_class.call(now: now)
  end

  it "has nothing to say before anything has been pulled" do
    expect(missing.any?).to be(false)
    expect(missing.dates).to be_empty
  end

  it "finds the hole an outage left in the middle" do
    store(Date.new(2026, 7, 1), Date.new(2026, 7, 2))
    store((Date.new(2026, 7, 20)..last_final).to_a)

    gaps = missing.gaps

    expect(gaps.size).to eq(1)
    expect(gaps.first).to have_attributes(first: Date.new(2026, 7, 3), last: Date.new(2026, 7, 19), days: 17)
    expect(gaps.first.gone?).to be(false)
  end

  it "does not count the three days Google has not finished yet" do
    store((Date.new(2026, 8, 1)..last_final).to_a)

    expect(missing.any?).to be(false)
    expect(missing.last_date).to eq(last_final)
  end

  it "does not count days below the oldest one asked about, because that is the backfill's end of the record" do
    store(Date.new(2026, 8, 1), Date.new(2026, 8, 2))

    expect(missing.first_date).to eq(Date.new(2026, 8, 1))
    expect(missing.gaps.map(&:first)).to eq([ Date.new(2026, 8, 3) ])
  end

  it "counts a day as one day, not as a range" do
    store(Date.new(2026, 8, 1), (Date.new(2026, 8, 3)..last_final).to_a)

    expect(missing.gaps.map { |gap| [ gap.first, gap.last ] }).to eq([ [ Date.new(2026, 8, 2), Date.new(2026, 8, 2) ] ])
  end

  it "calls a hole Google no longer serves gone rather than missing" do
    store(floor - 10.days, (floor..last_final).to_a)

    gone = missing.gaps

    expect(gone.size).to eq(1)
    expect(gone.first.gone?).to be(true)
    expect(gone.first).to have_attributes(first: floor - 9, last: floor - 1, days: 9)
    expect(missing.dates).to be_empty
  end

  it "splits a hole that straddles the sixteen month line, because half of it can still be filled" do
    store(floor - 5.days, (floor + 5.days..last_final).to_a)

    gone, fillable = missing.gaps

    expect(gone.gone?).to be(true)
    expect(gone).to have_attributes(first: floor - 4, last: floor - 1)
    expect(fillable.gone?).to be(false)
    expect(fillable).to have_attributes(first: floor, last: floor + 4)
    expect(missing.fillable_days).to eq(5)
    expect(gone.days).to eq(4)
  end

  it "hands the fill its days oldest first" do
    store(Date.new(2026, 7, 1), Date.new(2026, 7, 5), (Date.new(2026, 7, 9)..last_final).to_a)

    expect(missing.dates.first).to eq(Date.new(2026, 7, 2))
    expect(missing.dates).to eq(missing.dates.sort)
    expect(missing.dates.size).to eq(missing.fillable_days)
  end

  it "reads one day however many device and country rows it has" do
    store((Date.new(2026, 8, 1)..last_final).to_a)
    create(:dash_search_console_total, date: Date.new(2026, 8, 5), device: "mobile", country: "usa")

    expect(missing.any?).to be(false)
  end

  describe "a day Google had nothing for" do
    it "is not a hole, because it was asked about and the answer was nothing" do
      store(Date.new(2026, 8, 1), (Date.new(2026, 8, 3)..last_final).to_a)
      scan(Date.new(2026, 8, 2))

      expect(missing.any?).to be(false)
      expect(missing.dates).to be_empty
    end

    it "is counted and named, rather than quietly dropped" do
      store(Date.new(2026, 8, 1), (Date.new(2026, 8, 4)..last_final).to_a)
      scan(Date.new(2026, 8, 2), Date.new(2026, 8, 3))

      expect(missing.empty?).to be(true)
      expect(missing.empty_days).to eq(2)
      expect(missing.scanned_days).to eq(9)
    end

    it "starts the record when it is the oldest day reached" do
      scan(Date.new(2026, 7, 30), Date.new(2026, 7, 31))
      store((Date.new(2026, 8, 1)..last_final).to_a)

      expect(missing.first_date).to eq(Date.new(2026, 7, 30))
      expect(missing.any?).to be(false)
    end

    it "still counts as a hole when nothing was ever asked, which is the case they used to share" do
      store(Date.new(2026, 8, 1), (Date.new(2026, 8, 4)..last_final).to_a)

      expect(missing.gaps.map(&:days)).to eq([ 2 ])
      expect(missing.empty_days).to be_zero
    end
  end
end
