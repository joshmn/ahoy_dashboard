require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::FilterCategory do
  def reachable_from
    described_class::ALL.flat_map { |category| category.dimension_keys.map { |key| [ key, category.key ] } }
  end

  # The invariant that rots first. A dimension in no category cannot be filtered
  # from the UI at all, which makes it a dimension that does not really exist, and
  # one in two categories is two menu items that write the same filter.
  describe "covering the dimensions" do
    it "reaches every filterable dimension from exactly one category" do
      claims = reachable_from.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      AhoyDashboard::Dimension.filterable.each do |dimension|
        expect(claims[dimension.key]).to be_present, "no filter category covers #{dimension.key}"
        expect(claims[dimension.key].size).to eq(1),
          "#{dimension.key} is in #{claims[dimension.key].join(" and ")}"
      end
    end

    it "reaches an allowlisted custom property too" do
      AhoyDashboard::Property.create!(key: "facility_id")

      expect(AhoyDashboard::Dimension.filterable.map(&:key)).to include("prop:facility_id")
      expect(described_class.find("property").dimension_keys).to eq([ "prop:facility_id" ])
      expect(reachable_from.map(&:first)).to include("prop:facility_id")
    end

    it "reaches a host-registered dimension through the custom category" do
      AhoyDashboard::Dimension.register(key: "widget", label: "Widget", group: "Behaviour", scope: :event,
                                     sql: "null")

      expect(described_class.find("custom").dimension_keys).to include("widget")
      expect(reachable_from.map(&:first)).to include("widget")
    end

    it "names nothing that is not a dimension" do
      described_class::ALL.each do |category|
        expect(category.dimensions.map(&:key)).to eq(category.dimension_keys),
          "#{category.key} names a dimension nobody registered"
      end
    end

    it "covers Source with its three readings, which is why a category is not a dimension" do
      expect(described_class.find("source").dimension_keys).to eq(%w[source channel referrer])
    end
  end

  describe "the registry" do
    it "reads out of a frozen list" do
      expect(described_class::ALL).to be_frozen
      expect(described_class.all).to eq(described_class::ALL)
    end

    it "finds by key" do
      expect(described_class.find("location").label).to eq("Location")
      expect(described_class.find("location").to_param).to eq("location")
    end

    it "raises on a key nobody registered" do
      expect { described_class.find("hairstyle") }.to raise_error(ActiveRecord::RecordNotFound)
      expect(described_class.find_by_key("hairstyle")).to be_nil
      expect(described_class.find_by_key(nil)).to be_nil
    end

    it "has a default to fall back to" do
      expect(described_class.default).to eq(described_class.find(described_class::DEFAULT_KEY))
    end

    it "titles itself for the dialog" do
      expect(described_class.find("utm").title).to eq("Filter by UTM tags")
    end

    it "declares a heading every category answers to" do
      expect(described_class::ALL.map(&:heading).uniq).to all(be_in(described_class::HEADINGS))
    end
  end

  describe ".surfaced" do
    it "leaves out a category with nothing in it" do
      AhoyDashboard::Dimension.instance_variable_set(:@registry, {})

      expect(described_class.surfaced.map(&:key)).not_to include("property")
      expect(described_class.surfaced.map(&:key)).not_to include("custom")
    end

    it "puts it back once the allowlist holds something" do
      AhoyDashboard::Property.create!(key: "term")

      expect(described_class.surfaced.map(&:key)).to include("property")
    end

    it "puts the custom category back once a host app registers a dimension" do
      AhoyDashboard::Dimension.register(key: "widget", label: "Widget", group: "Behaviour", scope: :event,
                                     sql: "null")

      expect(described_class.surfaced.map(&:key)).to include("custom")
    end
  end

  describe ".grouped" do
    it "groups in the declared heading order and drops a heading with nothing under it" do
      headings = described_class.grouped.map(&:first)

      expect(headings).to eq(described_class::HEADINGS)
      expect(described_class.grouped.to_h["URL"].map(&:key)).to eq(%w[page hostname])
    end

    it "carries every surfaced category and nothing else" do
      grouped = described_class.grouped.flat_map(&:last)

      expect(grouped.map(&:key)).to match_array(described_class.surfaced.map(&:key))
    end
  end
end
