require "rails_helper"

RSpec.describe "Dashboard default segment" do
  def form(params = {})
    AhoyDashboard::QueryForm.from_params(params)
  end

  describe "the query" do
    it "applies nothing when no segment is the default" do
      create(:dash_segment)

      expect(form.filters).to be_empty
      expect(form).not_to be_defaulted
      expect(form.to_query).not_to have_key(:filters)
    end

    it "applies the default's filters when the request carries no filters of its own" do
      create(:dash_segment, applied_by_default: true, filters: [ dash_entry(value: "CA") ])

      expect(form.filters.map(&:label)).to eq([ "Country is CA" ])
      expect(form).to be_defaulted
      expect(form(period: "7d").filters.map(&:label)).to eq([ "Country is CA" ])
    end

    it "does not apply it when the request names its own filters" do
      create(:dash_segment, applied_by_default: true, filters: [ dash_entry(value: "CA") ])

      explicit = form(filters: [ dash_entry(dimension: "device", value: "mobile") ])

      expect(explicit.filters.map(&:label)).to eq([ "Device is mobile" ])
      expect(explicit).not_to be_defaulted
    end

    it "treats an explicit empty set as a choice rather than an absence" do
      create(:dash_segment, applied_by_default: true)

      cleared = form(filters: "none")

      expect(cleared.filters).to be_empty
      expect(cleared).not_to be_defaulted
      expect(cleared.to_query[:filters]).to eq("none")
    end

    it "leaves the filters out of a link while they are the default's own" do
      create(:dash_segment, applied_by_default: true)

      expect(form.to_query).not_to have_key(:filters)
      expect(form.with(period: "7d").to_query).to eq({ period: "7d" })
    end

    it "keeps the last chip's removal from bringing the default straight back" do
      create(:dash_segment, applied_by_default: true)

      expect(form.without_filter_params(0)).to include(filters: "none")
      expect(form.with(filters: nil).to_query[:filters]).to eq("none")
    end

    it "does not print the marker when there is no default to hold off" do
      expect(form.without_filter_params(0)).not_to have_key(:filters)
      expect(form.with(filters: nil).to_query).not_to have_key(:filters)
    end

    it "follows an edited default rather than the one a link was built against" do
      segment = create(:dash_segment, applied_by_default: true)
      link = form.to_query
      segment.update!(filters: [ dash_entry(value: "CA") ])

      expect(form(link).filters.map(&:label)).to eq([ "Country is CA" ])
    end
  end
end
