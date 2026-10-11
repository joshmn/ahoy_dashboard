require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Result do
  def organic(position, link, page: 1)
    AhoyDashboard::Serp::Organic.new(position: position, link: link, page: page)
  end

  def result(page:, start:, organic:, ai_overview: nil, cost_units: 1)
    described_class.new(provider: :fake, query: "visiting hours", page: page, start: start,
                        organic: organic, ai_overview: ai_overview, cost_units: cost_units)
  end

  it "derives the domain of a result from its link" do
    expect(organic(1, "https://www.bop.gov/a").domain).to eq("bop.gov")
  end

  it "finds where a domain ranks" do
    found = result(page: 1, start: 0, organic: [ organic(1, "https://bop.gov/a"),
                                                 organic(2, "https://example.com/b") ])

    expect(found.rank_for("example.com").position).to eq(2)
    expect(found.rank_for("nowhere.com")).to be_nil
  end

  it "only counts a subdomain as the site when asked" do
    found = result(page: 1, start: 0, organic: [ organic(1, "https://portal.example.com/a") ])

    expect(found.rank_for("example.com")).to be_nil
    expect(found.rank_for("example.com", match_subdomains: true).position).to eq(1)
  end

  it "reports an absent overview rather than nil" do
    expect(result(page: 1, start: 0, organic: []).ai_overview).not_to be_shown
  end

  it "says whether the overview cites a domain" do
    overview = AhoyDashboard::Serp::AiOverview.new(
      shown: true,
      sources: [ AhoyDashboard::Serp::Source.new(index: 1, link: "https://example.com/a") ]
    )
    found = result(page: 1, start: 0, organic: [], ai_overview: overview)

    expect(found.cited?("example.com")).to be(true)
    expect(found.cited?("bop.gov")).to be(false)
  end

  describe ".combine" do
    let(:page_one) do
      result(page: 1, start: 0, organic: [ organic(1, "https://bop.gov/a"), organic(2, "https://a.com/b") ],
             ai_overview: AhoyDashboard::Serp::AiOverview.new(shown: true))
    end
    let(:page_two) do
      result(page: 2, start: 10, organic: [ organic(11, "https://c.com/d", page: 2) ])
    end

    it "runs the pages into one ranking in order" do
      combined = described_class.combine([ page_two, page_one ])

      expect(combined.organic.map(&:position)).to eq([ 1, 2, 11 ])
      expect(combined.page).to eq(1)
    end

    it "adds up what the pages cost" do
      expect(described_class.combine([ page_one, page_two ]).cost_units).to eq(2)
    end

    it "keeps the overview off whichever page had one" do
      combined = described_class.combine([ page_two, page_one ])

      expect(combined.ai_overview).to be_shown
    end

    it "leaves an absent overview absent" do
      combined = described_class.combine([ page_two ])

      expect(combined.ai_overview).not_to be_shown
    end

    it "refuses to combine nothing" do
      expect { described_class.combine([]) }.to raise_error(AhoyDashboard::Serp::Error)
    end
  end
end
