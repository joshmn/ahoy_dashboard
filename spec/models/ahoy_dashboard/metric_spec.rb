require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Metric do
  it "lists the top stats in plausible's order, with scroll depth after them" do
    expect(described_class::ALL.map(&:key)).to eq(
      %w[visitors visits pageviews views_per_visit bounce_rate visit_duration scroll_depth]
    )
  end

  it "labels them the way plausible does" do
    expect(described_class::ALL.map(&:label)).to eq(
      [ "Unique visitors", "Total visits", "Total pageviews", "Views per visit", "Bounce rate",
        "Visit duration", "Scroll depth" ]
    )
  end

  it "keeps the row-only metrics findable without charting them" do
    %w[events conversion_rate engagement_time revenue_total revenue_average].each do |key|
      expect(described_class.find(key)).to be_present
      expect(described_class.find(key)).not_to be_chartable
    end
  end

  it "prints revenue as money" do
    expect(described_class.find("revenue_total").format(1234.5)).to eq("$1,234.50")
  end

  it "defaults to unique visitors" do
    expect(described_class.default.key).to eq("visitors")
  end

  it "raises for a metric nobody registered" do
    expect { described_class.find("vibes") }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "charts all six" do
    expect(described_class::ALL.select(&:chartable?).map(&:key)).to eq(described_class::ALL.map(&:key))
  end

  it "gives every metric a short label for the tile" do
    described_class::ALL.each do |metric|
      expect(metric.short).to be_present, "#{metric.key} has no short label"
    end
  end

  describe "#format" do
    it "prints a count in full" do
      expect(described_class.find("visitors").format(7)).to eq("7")
      expect(described_class.find("visitors").format(1234).delete(",")).to eq("1234")
    end

    it "prints views per visit to two places" do
      expect(described_class.find("views_per_visit").format(1.75)).to eq("1.75")
    end

    it "prints a bounce rate as a whole percent" do
      expect(described_class.find("bounce_rate").format(50.0)).to eq("50%")
      expect(described_class.find("bounce_rate").format(33.4)).to eq("33%")
    end

    it "prints a duration in minutes and seconds" do
      expect(described_class.find("visit_duration").format(204)).to eq("3m 24s")
      expect(described_class.find("visit_duration").format(48)).to eq("48s")
    end

    it "prints nothing as zero in the metric's own units" do
      expect(described_class.find("visitors").format(nil)).to eq("0")
      expect(described_class.find("bounce_rate").format(nil)).to eq("0%")
      expect(described_class.find("visit_duration").format(nil)).to eq("0s")
    end
  end

  describe "#compact" do
    it "abbreviates a big count for the stat strip" do
      expect(described_class.find("visitors").compact(12_400)).to eq("12.4k")
      expect(described_class.find("visitors").compact(1234)).to eq("1.2k")
      expect(described_class.find("pageviews").compact(1_240_000)).to eq("1.2M")
    end

    it "leaves a small count alone" do
      expect(described_class.find("visitors").compact(942)).to eq("942")
    end

    it "leaves the non counting metrics reading the way format does" do
      expect(described_class.find("bounce_rate").compact(50.0)).to eq("50%")
      expect(described_class.find("visit_duration").compact(204)).to eq("3m 24s")
    end
  end
end
