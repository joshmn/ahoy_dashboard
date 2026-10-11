require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Segment, type: :model do
  def entry(dimension: "country", operator: "is", value: "US")
    { "dimension" => dimension, "operator" => operator, "value" => value }
  end

  describe "validations" do
    it "saves a segment with a name and a filter" do
      segment = described_class.new(name: "Non-customer traffic", filters: [ entry ])

      expect(segment).to be_valid
    end

    it "wants a name" do
      segment = described_class.new(name: " ", filters: [ entry ])

      expect(segment).not_to be_valid
      expect(segment.errors[:name]).to be_present
    end

    it "refuses a name another segment already has" do
      create(:dash_segment, name: "Non-customer traffic")
      segment = described_class.new(name: "Non-customer traffic", filters: [ entry ])

      expect(segment).not_to be_valid
      expect(segment.errors[:name]).to be_present
    end

    it "refuses a segment with no filters, because that is every visit on the site" do
      segment = described_class.new(name: "Everybody", filters: [])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("every visit on the site")
    end

    it "refuses a filter naming a dimension nobody registered" do
      segment = described_class.new(name: "Broken", filters: [ entry(dimension: "nope") ])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("cannot read")
    end

    # Filter coerces an operator it does not know to "is", so an unchecked one
    # would save as a different match than the one somebody asked for.
    it "refuses a match nobody offered rather than quietly making it an is" do
      segment = described_class.new(name: "Broken", filters: [ entry(operator: "sideways") ])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("cannot read")
    end

    it "refuses a filter with no value" do
      segment = described_class.new(name: "Broken", filters: [ entry(value: "") ])

      expect(segment).not_to be_valid
    end

    # Dimension.find_by_key builds a prop: dimension on demand and never reads
    # the allowlist, so hiding a property does not break a segment using it.
    it "keeps a custom property filter readable whether or not it is on the allowlist" do
      segment = described_class.new(name: "One prison", filters: [ entry(dimension: "prop:facility_id", value: "12") ])

      expect(segment).to be_valid
      expect(AhoyDashboard::Property.count).to be_zero
    end

    it "reads a filter written with symbol keys before the row has been round-tripped" do
      segment = described_class.new(name: "Symbols", filters: [ { dimension: "country", operator: "is", value: "US" } ])

      expect(segment).to be_valid
    end
  end

  describe "#to_filters" do
    it "hands back real filters in the order they were saved" do
      segment = create(:dash_segment, filters: [ entry, entry(dimension: "browser", value: "Chrome") ])

      expect(segment.reload.to_filters.map(&:label)).to eq([ "Country is US", "Browser is Chrome" ])
    end

    it "round-trips through the same shape the query string carries" do
      segment = create(:dash_segment, filters: [ entry(operator: "contains", value: "faq") ])

      expect(segment.reload.to_filters.to_param).to eq([ entry(operator: "contains", value: "faq") ])
    end
  end

  describe "#readable?" do
    it "is true for a segment whose every filter still parses" do
      expect(create(:dash_segment)).to be_readable
    end

    # The state a row falls into when a dimension is taken out of the registry
    # after the row was saved. Nothing saves it, so the trait writes past the
    # validations.
    it "is false once a dimension it names is gone" do
      segment = create(:dash_segment, :unreadable)

      expect(segment).not_to be_readable
    end

    it "does not let a segment whose dimension is gone read as no filters at all" do
      segment = create(:dash_segment, :unreadable)

      expect(segment.to_filters).to be_empty
      expect(segment).not_to be_readable
    end
  end

  describe ".listed" do
    it "is every segment in position order" do
      later = create(:dash_segment, position: 2)
      sooner = create(:dash_segment, position: 1)

      expect(described_class.listed.map(&:id)).to eq([ sooner.id, later.id ])
    end

  end

  describe "applying one" do
    let(:now) { dash_time(2026, 8, 11, 14, 30) }

    around { |example| travel_to(now) { example.run } }

    # Asserted on the rows the dashboard would read, not on the page: a segment is
    # only worth anything if the visits come back narrowed.
    it "narrows what the dashboard reads to the visits its filters match" do
      american = dash_visit(started_at: now - 2.days, visitor: "a", country: "US")
      dash_page_view(american, at: now - 2.days)
      canadian = dash_visit(started_at: now - 1.day, visitor: "b", country: "CA")
      dash_page_view(canadian, at: now - 1.day)

      segment = create(:dash_segment, filters: [ entry(value: "CA") ])
      form = AhoyDashboard::QueryForm.from_params({ filters: segment.reload.to_filters.to_param })

      expect(form.scope.visits.pluck(:id)).to eq([ canadian.id ])
    end

    it "reads every visit when no segment is applied, so the narrowing is the segment's" do
      american = dash_visit(started_at: now - 2.days, visitor: "a", country: "US")
      dash_page_view(american, at: now - 2.days)
      canadian = dash_visit(started_at: now - 1.day, visitor: "b", country: "CA")
      dash_page_view(canadian, at: now - 1.day)

      expect(AhoyDashboard::QueryForm.from_params({}).scope.visits.count).to eq(2)
    end

    it "narrows on every filter at once when a segment holds more than one" do
      matching = dash_visit(started_at: now - 2.days, visitor: "a", country: "CA", browser: "Chrome")
      dash_page_view(matching, at: now - 2.days)
      half = dash_visit(started_at: now - 1.day, visitor: "b", country: "CA", browser: "Safari")
      dash_page_view(half, at: now - 1.day)

      segment = create(
        :dash_segment,
        filters: [ entry(value: "CA"), entry(dimension: "browser", value: "Chrome") ]
      )
      form = AhoyDashboard::QueryForm.from_params({ filters: segment.reload.to_filters.to_param })

      expect(form.scope.visits.pluck(:id)).to eq([ matching.id ])
    end
  end
end
