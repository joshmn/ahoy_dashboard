require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleRowsQuery do
  let(:day) { Date.new(2026, 8, 10) }

  it "reuses daily counts and row dates for exact unfiltered pagination in three reads" do
    first = create(:dash_search_console_row, date: day, clicks: 7, impressions: 70)
    create(:dash_search_console_row, date: day, clicks: 2, impressions: 20)
    last = create(:dash_search_console_row, date: day + 2, clicks: 5, impressions: 50)
    create(:dash_search_console_total, date: day - 1, clicks: 10, impressions: 100)
    create(:dash_search_console_total, date: day, clicks: 20, impressions: 200)
    result = nil
    sql = captured_sql(/\ASELECT/, cached: true) do
      result = described_class.call(per_page: 2).tap { |found| found.rows.load }
    end

    expect(result).to have_attributes(total_rows: 3, pages: 2, range: day..(day + 2), rows: [ first, last ])
    expect(result.days.map { |point| [ point.date, point.rows, point.row_clicks, point.total_clicks ] })
      .to eq([ [ day + 2, 1, 5, nil ], [ day, 2, 9, 20 ], [ day - 1, 0, 0, 10 ] ])
    expect(sql.size).to eq(3)
  end

  it "counts only matching rows while retaining the unfiltered day summary and stored extent" do
    create(:dash_search_console_row, date: day, query: "100% match", clicks: 2)
    create(:dash_search_console_row, date: day + 1, query: "another", clicks: 9)
    create(:dash_search_console_row, date: day + 2, query: "100% match again", clicks: 3)
    result = nil
    sql = captured_sql(/\ASELECT/, cached: true) do
      result = described_class.call(term: "%", page: 2, per_page: 1).tap { |found| found.rows.load }
    end

    expect(result).to have_attributes(total_rows: 2, pages: 2, range: day..(day + 2))
    expect(result.rows.pluck(:query)).to eq([ "100% match" ])
    expect(result.days.sum(&:rows)).to eq(3)
    expect(sql.size).to eq(3)
  end

  it "uses identical literal matching for filtered counts and rows, including SQL metacharacters" do
    %w[% _ ? ' \\].each_with_index do |term, index|
      wanted = create(:dash_search_console_row, date: day, query: "literal #{term}", page: "https://example.com/#{index}")
      result = described_class.call(term: term)

      expect(result.total_rows).to eq(1), term
      expect(result.rows.to_a).to eq([ wanted ]), term
    end
  end

  it "keeps an empty row table's extent absent even when property totals exist" do
    create(:dash_search_console_total, date: day)

    expect(described_class.call).to have_attributes(total_rows: 0, pages: 1, range: nil)
  end
end
