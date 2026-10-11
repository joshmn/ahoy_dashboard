require "rails_helper"

RSpec.describe AhoyDashboard::PickerFacet do
  describe ".all" do
    it "picks up a custom property that was shown after it was first asked" do
      expect(described_class.find_by_key("prop:shown_later")).to be_nil

      create(:dash_property, key: "shown_later")

      expect(described_class.find_by_key("prop:shown_later")).to be_present
      expect(described_class.for_scope(described_class::FILTER).map(&:key)).to include("prop:shown_later")
    end

    it "drops a custom property as soon as it is hidden" do
      property = create(:dash_property, key: "hidden_later")

      expect(described_class.find_by_key("prop:hidden_later")).to be_present

      property.update!(enabled: false)

      expect(described_class.find_by_key("prop:hidden_later")).to be_nil
      expect(described_class.grouped(described_class::FILTER).flat_map { |_, facets| facets.map(&:key) })
        .not_to include("prop:hidden_later")
    end

    it "keeps the two facets that are not dimensions" do
      expect(described_class.for_scope(described_class::GOAL).map(&:key))
        .to include(described_class::EVENTS, described_class::PROPERTY_KEYS)
    end
  end
end
