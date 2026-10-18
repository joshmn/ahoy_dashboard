require "rails_helper"

RSpec.describe AhoyDashboard::Segment, type: :model do
  describe "validations" do
    it "saves a segment with a name and a filter" do
      segment = described_class.new(name: "Non-customer traffic", filters: [ dash_entry ])

      expect(segment).to be_valid
    end

    it "wants a name" do
      segment = described_class.new(name: " ", filters: [ dash_entry ])

      expect(segment).not_to be_valid
      expect(segment.errors[:name]).to be_present
    end

    it "refuses a name another segment already has" do
      create(:dash_segment, name: "Non-customer traffic")
      segment = described_class.new(name: "Non-customer traffic", filters: [ dash_entry ])

      expect(segment).not_to be_valid
      expect(segment.errors[:name]).to be_present
    end

    it "refuses a segment with no filters, because that is every visit on the site" do
      segment = described_class.new(name: "Everybody", filters: [])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("every visit on the site")
    end

    it "refuses a filter naming a dimension nobody registered" do
      segment = described_class.new(name: "Broken", filters: [ dash_entry(dimension: "nope") ])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("cannot read")
    end

    it "refuses a match nobody offered rather than quietly making it an is" do
      segment = described_class.new(name: "Broken", filters: [ dash_entry(operator: "sideways") ])

      expect(segment).not_to be_valid
      expect(segment.errors[:filters].to_sentence).to include("cannot read")
    end

    it "refuses a filter with no value" do
      segment = described_class.new(name: "Broken", filters: [ dash_entry(value: "") ])

      expect(segment).not_to be_valid
    end

    it "keeps a custom property filter readable whether or not it is on the allowlist" do
      segment = described_class.new(name: "One prison", filters: [ dash_entry(dimension: "prop:facility_id", value: "12") ])

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
      segment = create(:dash_segment, filters: [ dash_entry, dash_entry(dimension: "browser", value: "Chrome") ])

      expect(segment.reload.to_filters.map(&:label)).to eq([ "Country is US", "Browser is Chrome" ])
    end

    it "round-trips through the same shape the query string carries" do
      segment = create(:dash_segment, filters: [ dash_entry(operator: "contains", value: "faq") ])

      expect(segment.reload.to_filters.to_param).to eq([ dash_entry(operator: "contains", value: "faq") ])
    end
  end

  describe "#readable?" do
    it "is true for a segment whose every filter still parses" do
      expect(create(:dash_segment)).to be_readable
    end

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

    it "narrows what the dashboard reads to the visits its filters match" do
      dash_landing(at: now - 2.days, visitor: "a", country: "US")
      canadian = dash_landing(at: now - 1.day, visitor: "b", country: "CA")

      segment = create(:dash_segment, filters: [ dash_entry(value: "CA") ])
      form = AhoyDashboard::QueryForm.from_params({ filters: segment.reload.to_filters.to_param })

      expect(form.scope.visits.pluck(:id)).to eq([ canadian.id ])
    end

    it "reads every visit when no segment is applied, so the narrowing is the segment's" do
      dash_landing(at: now - 2.days, visitor: "a", country: "US")
      dash_landing(at: now - 1.day, visitor: "b", country: "CA")

      expect(AhoyDashboard::QueryForm.from_params({}).scope.visits.count).to eq(2)
    end

    it "narrows on every filter at once when a segment holds more than one" do
      matching = dash_landing(at: now - 2.days, visitor: "a", country: "CA", browser: "Chrome")
      dash_landing(at: now - 1.day, visitor: "b", country: "CA", browser: "Safari")

      segment = create(
        :dash_segment,
        filters: [ dash_entry(value: "CA"), dash_entry(dimension: "browser", value: "Chrome") ]
      )
      form = AhoyDashboard::QueryForm.from_params({ filters: segment.reload.to_filters.to_param })

      expect(form.scope.visits.pluck(:id)).to eq([ matching.id ])
    end
  end
end
