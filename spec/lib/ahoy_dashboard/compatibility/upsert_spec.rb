# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Compatibility::Upsert do
  let(:model) { AhoyDashboard::SearchConsoleDay }
  let(:date) { Date.current }
  let(:earlier) { 2.days.ago.change(usec: 0) }
  let(:later) { 1.day.ago.change(usec: 0) }

  def upsert(rows:, **options)
    described_class.new(model: model, rows: rows, unique_by: :date, **options).call
  end

  it "preserves created_at when updating only selected columns" do
    model.create!(date: date, scanned_at: earlier, created_at: earlier, updated_at: earlier)

    upsert(rows: [{ date: date, scanned_at: later, created_at: later, updated_at: later }],
           update_only: [:scanned_at])

    expect(model.find_by!(date: date).created_at).to eq(earlier)
  end

  it "updates the requested column" do
    model.create!(date: date, scanned_at: earlier)

    upsert(rows: [{ date: date, scanned_at: later }], update_only: [:scanned_at])

    expect(model.find_by!(date: date).scanned_at).to eq(later)
  end

  it "preserves updated_at when selected values are unchanged" do
    model.create!(date: date, scanned_at: earlier, updated_at: earlier)

    upsert(rows: [{ date: date, scanned_at: earlier }], update_only: [:scanned_at])

    expect(model.find_by!(date: date).updated_at).to eq(earlier)
  end

  it "preserves updated_at when default writable values are unchanged" do
    model.create!(date: date, scanned_at: earlier, updated_at: earlier)

    upsert(rows: [{ date: date, scanned_at: earlier }])

    expect(model.find_by!(date: date).updated_at).to eq(earlier)
  end

  it "supplies required timestamps for inserted rows" do
    upsert(rows: [{ date: date, scanned_at: earlier }])

    expect(model.find_by!(date: date)).to have_attributes(created_at: be_present, updated_at: be_present)
  end

  it "uses ActiveRecord enum serialization" do
    described_class.new(model: AhoyDashboard::SerpSpendDay,
                        rows: [{ provider: "fake", on: date, kind: :keywords, units: 4 }],
                        unique_by: [:provider, :on, :kind]).call

    expect(AhoyDashboard::SerpSpendDay.find_by!(provider: "fake").kind).to eq("keywords")
  end

  it "applies custom duplicate SQL instead of replacing the existing value" do
    create(:dash_serp_spend_day, provider: "fake", on: date, kind: :checks, units: 3)
    spend = AhoyDashboard::SerpSpendDay

    described_class.new(model: spend, rows: [{ provider: "fake", on: date, kind: :checks, units: 4 }],
                        unique_by: [:provider, :on, :kind],
                        on_duplicate: Arel.sql("units = #{spend.quoted_table_name}.units + excluded.units")).call

    expect(spend.find_by!(provider: "fake").units).to eq(7)
  end

  it "rejects unknown attributes before issuing SQL" do
    expect { upsert(rows: [{ date: date, scanned_at: earlier, unknown_attribute: 1 }]) }
      .to raise_error(ActiveModel::UnknownAttributeError)
  end

  it "rejects rows with different sets of attributes" do
    expect { upsert(rows: [{ date: date }, { date: date + 1, scanned_at: earlier }]) }
      .to raise_error(ArgumentError, /same keys/)
  end
end
