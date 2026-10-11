require "rails_helper"

RSpec.describe AhoyDashboard::SerpKeywordDecorator, type: :decorator do
  def decorate(keyword)
    described_class.new(keyword)
  end

  describe "#frequency_label" do
    it "names every cadence the way the form does" do
      labels = AhoyDashboard::SerpKeyword.frequencies.keys.map do |key|
        decorate(build(:dash_serp_keyword, frequency: key)).frequency_label
      end

      expect(labels).to eq([ "Daily", "Weekly", "Every 2 weeks", "Monthly" ])
    end
  end

  describe "#search_label" do
    it "says the device and the language" do
      keyword = build(:dash_serp_keyword, device: "mobile", language: "es")

      expect(decorate(keyword).search_label).to eq("Mobile, es")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    keyword = create(:dash_serp_keyword)

    expect(decorate(keyword).to_param).to eq(keyword.id.to_s)
  end
end
