require "rails_helper"

RSpec.describe AhoyDashboard::EventNamesQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  before do
    here = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
    dash_goal(here, "consult_requested", at: dash_time(2026, 8, 10, 9, 1))
    dash_goal(here, "consult_requested", at: dash_time(2026, 8, 10, 9, 2))

    abroad = dash_landing("/a", at: dash_time(2026, 8, 10, 11), visitor: "b", country: "CA")
    dash_goal(abroad, "newsletter_subscribed", at: dash_time(2026, 8, 10, 11, 1))
  end

  it "lists what the range holds, most common first" do
    expect(described_class.call(scope: scope)).to eq(%w[consult_requested newsletter_subscribed])
  end

  it "leaves page views out" do
    expect(described_class.call(scope: scope)).not_to include(AhoyDashboard::PAGE_VIEW)
  end

  it "counts nothing outside the range" do
    earlier = dash_visit(started_at: dash_time(2026, 8, 9, 9), visitor: "c")
    dash_goal(earlier, "page_tip_submitted", at: dash_time(2026, 8, 9, 9))

    expect(described_class.call(scope: scope)).not_to include("page_tip_submitted")
  end

  describe "caching" do
    let(:filtered) { dash_scope(range: range, filters: dash_filters([ "country", "is", "CA" ])) }

    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "does not hand a filtered answer to the unfiltered screen" do
      expect(described_class.call(scope: filtered)).to eq([ "newsletter_subscribed" ])
      expect(described_class.call(scope: scope)).to eq(%w[consult_requested newsletter_subscribed])
    end

    it "does not hand the unfiltered answer to a filtered one either" do
      expect(described_class.call(scope: scope)).to eq(%w[consult_requested newsletter_subscribed])
      expect(described_class.call(scope: filtered)).to eq([ "newsletter_subscribed" ])
    end

    it "keeps a different limit apart" do
      expect(described_class.call(scope: scope, limit: 1)).to eq([ "consult_requested" ])
      expect(described_class.call(scope: scope)).to eq(%w[consult_requested newsletter_subscribed])
    end

    it "answers the same scope out of the cache rather than asking again" do
      described_class.call(scope: scope)
      Ahoy::Event.delete_all

      expect(described_class.call(scope: dash_scope(range: range)))
        .to eq(%w[consult_requested newsletter_subscribed])
    end
  end
end
