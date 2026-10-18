require "rails_helper"

RSpec.describe AhoyDashboard::Filters do
  def from(list)
    described_class.from_params("filters" => list)
  end

  describe ".from_params" do
    it "reads a filter off the query string" do
      filters = from([ { "dimension" => "page", "operator" => "contains", "value" => "/faq" } ])

      expect(filters.size).to eq(1)
      expect(filters.to_a.first.dimension.key).to eq("page")
      expect(filters.to_a.first.operator).to eq("contains")
      expect(filters.to_a.first.value).to eq("/faq")
    end

    it "reads action controller parameters too" do
      params = ActionController::Parameters.new(
        filters: [ { dimension: "country", operator: "is", value: "US" } ]
      ).permit!

      filters = described_class.from_params(params)

      expect(filters.size).to eq(1)
      expect(filters.to_a.first.dimension.key).to eq("country")
    end

    it "drops a dimension nobody registered" do
      filters = from([
        { "dimension" => "hairstyle", "operator" => "is", "value" => "mullet" },
        { "dimension" => "page", "operator" => "is", "value" => "/faq" }
      ])

      expect(filters.map { |filter| filter.dimension.key }).to eq([ "page" ])
    end

    it "drops a blank value" do
      filters = from([
        { "dimension" => "page", "operator" => "is", "value" => "" },
        { "dimension" => "country", "operator" => "is", "value" => nil }
      ])

      expect(filters).to be_empty
    end

    it "keeps a property filter" do
      filters = from([ { "dimension" => "prop:facility_id", "operator" => "is", "value" => "42" } ])

      expect(filters.map { |filter| filter.dimension.key }).to eq([ "prop:facility_id" ])
    end

    it "drops a property name that could not be a property" do
      filters = from([ { "dimension" => "prop:line\nbreak", "operator" => "is", "value" => "1" } ])

      expect(filters).to be_empty
    end

    it "keeps a property name that only looks like sql as a plain key" do
      name = "x'); drop table ahoy_events; --"
      filters = from([ { "dimension" => "prop:#{name}", "operator" => "is", "value" => "1" } ])

      expect(filters.map { |filter| filter.dimension.key }).to eq([ "prop:#{name}" ])
      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end

    it "keeps a property filter on a key with capitals, dashes and dots" do
      filters = from([ { "dimension" => "prop:page.section-Id", "operator" => "is", "value" => "1" } ])

      expect(filters.map { |filter| filter.dimension.key }).to eq([ "prop:page.section-Id" ])
    end

    it "never raises on rubbish" do
      [
        {},
        { "filters" => nil },
        { "filters" => "" },
        { "filters" => "banana" },
        { "filters" => [] },
        { "filters" => [ nil ] },
        { "filters" => [ "banana" ] },
        { "filters" => [ {} ] },
        { "filters" => [ { "dimension" => "page" } ] },
        { "filters" => { "0" => { "dimension" => "page", "operator" => "is", "value" => "/faq" } } }
      ].each do |params|
        expect { described_class.from_params(params) }.not_to raise_error,
          "raised on #{params.inspect}"
      end
    end
  end

  describe "the collection" do
    let(:page) { dash_filter("page", "is", "/faq") }
    let(:country) { dash_filter("country", "is", "US") }
    let(:filters) { described_class.new([ page, country ]) }

    it "enumerates in the order it was given" do
      expect(filters.to_a).to eq([ page, country ])
      expect(filters.size).to eq(2)
      expect(filters).to be_any
      expect(filters).not_to be_empty
      expect(filters.map { |filter| filter.dimension.key }).to eq(%w[page country])
    end

    it "is empty when it holds nothing" do
      expect(described_class.new([])).to be_empty
      expect(described_class.new([])).not_to be_any
    end

    it "holds each plain filter as a group of its own" do
      expect(filters.groups.map(&:size)).to eq([ 1, 1 ])
      expect(filters.groups.map(&:kind)).to eq([ :view, :visit ])
      expect(filters).not_to be_grouped
    end

    it "adds without mutating what it was built from" do
      added = filters.add(dash_filter("browser", "is", "Chrome"))

      expect(added.size).to eq(3)
      expect(filters.size).to eq(2)
    end

    it "removes by index without mutating" do
      without = filters.without(0)

      expect(without.map { |filter| filter.dimension.key }).to eq([ "country" ])
      expect(filters.size).to eq(2)
    end

    it "round trips through to_param" do
      expect(described_class.from_params("filters" => filters.to_param).to_param).to eq(filters.to_param)
      expect(described_class.from_params("filters" => filters.to_param).map { |filter| filter.value })
        .to eq([ "/faq", "US" ])
    end
  end

  describe "or groups" do
    def params(*entries)
      { "filters" => entries.map { |dimension, operator, value, group| { "dimension" => dimension, "operator" => operator, "value" => value, "group" => group }.compact } }
    end

    it "reads filters that share a group as one group" do
      filters = described_class.from_params(params([ "country", "is", "US", "0" ], [ "country", "is", "CA", "0" ], [ "browser", "is", "Chrome" ]))

      expect(filters.groups.map(&:size)).to eq([ 2, 1 ])
      expect(filters.map(&:value)).to eq(%w[US CA Chrome])
      expect(filters).to be_grouped
    end

    it "keeps both values in a group rather than letting the last is win" do
      filters = described_class.from_params(params([ "country", "is", "US", "3" ], [ "country", "is", "CA", "3" ]))

      expect(filters.map(&:value)).to eq(%w[US CA])
    end

    it "still lets the last plain is win on one dimension" do
      filters = described_class.from_params(params([ "country", "is", "US" ], [ "country", "is", "CA" ]))

      expect(filters.map(&:value)).to eq(%w[CA])
    end

    it "places a group where its first filter appeared, however the members are spread" do
      filters = described_class.from_params(
        params([ "country", "is", "US", "7" ], [ "browser", "is", "Chrome" ], [ "country", "is", "CA", "7" ])
      )

      expect(filters.groups.map(&:label)).to eq([ "Country is US or CA", "Browser is Chrome" ])
    end

    it "treats a group key that is not a whole number as no group" do
      filters = described_class.from_params(params([ "country", "is_not", "US", "x" ], [ "country", "is_not", "CA", "-1" ]))

      expect(filters.groups.map(&:size)).to eq([ 1, 1 ])
    end

    it "serializes a group of one with no group key, so old links read the same" do
      filters = described_class.from_params(params([ "country", "is", "US", "4" ]))

      expect(filters.to_param).to eq([ { "dimension" => "country", "operator" => "is", "value" => "US" } ])
    end

    it "numbers groups by position when serializing" do
      filters = described_class.from_params(
        params([ "browser", "is", "Chrome" ], [ "country", "is", "US", "9" ], [ "country", "is", "CA", "9" ])
      )

      expect(filters.to_param).to eq([
        { "dimension" => "browser", "operator" => "is", "value" => "Chrome" },
        { "dimension" => "country", "operator" => "is", "value" => "US", "group" => 1 },
        { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => 1 }
      ])
      expect(described_class.from_params("filters" => filters.to_param).to_param).to eq(filters.to_param)
    end

    it "removes one member and leaves the rest of its group" do
      grouped = described_class.grouped([ dash_group(%w[country is US], %w[country is CA]).to_a ])

      expect(grouped.without(1).to_param).to eq([ { "dimension" => "country", "operator" => "is", "value" => "US" } ])
    end

    it "only counts a lone is filter as pinned" do
      grouped = described_class.grouped([
        dash_group(%w[country is US], %w[country is CA]), dash_group(%w[browser is Chrome]), dash_group(%w[os is_not Linux])
      ])

      expect(grouped.pinned.map(&:value)).to eq(%w[Chrome])
      expect(grouped.pinned_index("browser", "Chrome")).to eq(2)
      expect(grouped.pinned_index("country", "US")).to be_nil
    end

    it "does not replace a group when a row is clicked" do
      grouped = described_class.grouped([ dash_group(%w[country is US], %w[country is CA]) ])
      clicked = grouped.replacing("country", dash_filter("country", "is", "DE"))

      expect(clicked.sentence).to eq("(Country is US or CA) and Country is DE")
    end

    it "says a mixed group in full" do
      group = dash_group(%w[country is US], %w[page is /pricing])

      expect(group.label).to eq("Country is US or Page is /pricing")
      expect(group.kind).to eq(:view)
    end

    it "notices two negatives joined by or" do
      expect(dash_group(%w[country is_not US], %w[country is_not CA])).to be_negative_or
      expect(dash_group(%w[country is_not US], %w[country is CA])).not_to be_negative_or
    end

    it "validates a stored group key" do
      entry = { "dimension" => "country", "operator" => "is", "value" => "US" }

      expect(described_class.readable_entry?(entry.merge("group" => 2))).to be(true)
      expect(described_class.readable_entry?(entry.merge("group" => "two"))).to be(false)
    end
  end
end
