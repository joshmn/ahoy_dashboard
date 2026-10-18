require "rails_helper"

RSpec.describe AhoyDashboard::Seo::Periods do
  def query(params)
    AhoyDashboard::QueryForm.from_params(params)
  end

  it "leaves out the periods too short for data that lands days late" do
    expect(described_class.all.map(&:key)).not_to include("realtime", "day", "yesterday")
  end

  it "marks the current period in the menu and links each one through the block" do
    items = described_class.menu(query(period: "28d")) { |period| "/x?period=#{period.key}" }

    expect(items.select { |item| item[:active] }.map { |item| item[:url] }).to eq([ "/x?period=28d" ])
  end

  it "offers a custom range unless told not to" do
    labels = ->(custom) { described_class.menu(query(period: "28d"), custom: custom) { "/x" }.map { |item| item[:label] } }

    expect(labels.call(true)).to include("Custom range")
    expect(labels.call(false)).not_to include("Custom range")
  end

  it "takes everything as wide enough and a week as too narrow" do
    expect(described_class.wide_enough?(query(period: "all"))).to be(true)
    expect(described_class.wide_enough?(query(period: "28d"))).to be(true)
    expect(described_class.wide_enough?(query(period: "7d"))).to be(false)
  end

  it "widens to the last 28 days and drops a custom range's dates" do
    widened = described_class.widened(query(period: "custom", from: "2026-08-01", to: "2026-08-03"))

    expect(widened.values_at(:period, :from, :to)).to eq([ "28d", nil, nil ])
    expect(described_class.widen_label).to eq("Show the last 28 days")
  end
end
