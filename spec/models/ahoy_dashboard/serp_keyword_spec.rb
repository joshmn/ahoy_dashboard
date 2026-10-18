require "rails_helper"

RSpec.describe AhoyDashboard::SerpKeyword do
  let(:site) { create(:dash_serp_site) }

  def tracked(**attributes)
    create(:dash_serp_keyword, :tracked, site: site, **attributes)
  end

  describe "tags" do
    it "trims, squeezes, splits on commas and drops repeats whatever their case" do
      keyword = create(:dash_serp_keyword, tags: [ "  Brand  name , pricing", "brand name", "", "Pricing" ])

      expect(keyword.tags).to eq([ "Brand name", "pricing" ])
    end

    it "starts with none" do
      expect(create(:dash_serp_keyword).tags).to eq([])
    end

    it "refuses a tag longer than it can show" do
      keyword = build(:dash_serp_keyword, tags: [ "x" * (described_class::MAX_TAG_LENGTH + 1) ])

      expect(keyword).not_to be_valid
      expect(keyword.errors[:tags].to_sentence).to include("#{described_class::MAX_TAG_LENGTH} characters at most")
    end

    it "refuses more tags than the cap" do
      keyword = build(:dash_serp_keyword, tags: (1..described_class::MAX_TAGS + 1).map { |n| "tag #{n}" })

      expect(keyword).not_to be_valid
    end

    it "finds the keywords carrying one tag, and everything for no tag" do
      branded = create(:dash_serp_keyword, tags: [ "brand", "pricing" ])
      create(:dash_serp_keyword, tags: [ "pricing" ])
      untagged = create(:dash_serp_keyword)

      expect(described_class.tagged("brand")).to eq([ branded ])
      expect(described_class.tagged(nil)).to include(branded, untagged)
    end

    it "lists every tag in use once, and forgets one when its last keyword goes" do
      create(:dash_serp_keyword, tags: [ "pricing", "Brand" ])
      last = create(:dash_serp_keyword, tags: [ "blog", "pricing" ])

      expect(described_class.tags_in_use).to eq([ "blog", "Brand", "pricing" ])

      last.destroy

      expect(described_class.tags_in_use).to eq([ "Brand", "pricing" ])
    end

    it "spells a new tag the way the one already in use is spelled" do
      create(:dash_serp_keyword, tags: [ "Brand" ])

      expect(described_class.canonical_tags("brand, new one")).to eq([ "Brand", "new one" ])
    end
  end

  describe "places" do
    it "keeps a country and a city apart" do
      keyword = build(:dash_serp_keyword,
                      locations: [ "us", "city:us:Chicago,Illinois,United States" ])

      expect(keyword.places.map(&:city?)).to eq([ false, true ])
    end

    it "falls back to one country rather than saving nothing to search" do
      keyword = create(:dash_serp_keyword, locations: [])

      expect(keyword.locations).to eq([ "us" ])
    end

    it "drops blanks and repeats" do
      keyword = create(:dash_serp_keyword, locations: [ "us", " us ", "", "gb" ])

      expect(keyword.locations).to eq([ "us", "gb" ])
    end

    it "refuses more places than it is worth paying for" do
      keyword = build(:dash_serp_keyword, locations: %w[us gb ca au de fr])

      expect(keyword).not_to be_valid
      expect(keyword.errors[:locations].to_sentence).to include("every place is another search")
    end
  end

  it "refuses a second copy of the same search" do
    create(:dash_serp_keyword, query: "visiting hours")

    expect { create(:dash_serp_keyword, query: "visiting hours") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "refuses a second copy of the same search that differs only by capitals" do
    create(:dash_serp_keyword, query: "Visiting Hours")

    expect { create(:dash_serp_keyword, query: "visiting hours") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "still tracks the same words on another device" do
    create(:dash_serp_keyword, query: "Visiting Hours", device: "desktop")

    expect { create(:dash_serp_keyword, query: "visiting hours", device: "mobile") }
      .to change(described_class, :count).by(1)
  end

  describe ".due" do
    it "takes one that has never been checked" do
      keyword = tracked(last_checked_at: nil)

      expect(described_class.due).to include(keyword)
    end

    it "leaves a daily one alone until a day has passed" do
      keyword = tracked(frequency: :daily, last_checked_at: 2.hours.ago)

      expect(described_class.due).not_to include(keyword)
    end

    it "reads each cadence against its own span" do
      weekly = tracked(frequency: :weekly, last_checked_at: 2.days.ago)
      daily = tracked(frequency: :daily, last_checked_at: 2.days.ago)

      expect(described_class.due).to include(daily)
      expect(described_class.due).not_to include(weekly)
    end

    it "leaves out one nobody is looking for a site in" do
      keyword = create(:dash_serp_keyword, last_checked_at: nil)

      expect(described_class.due).not_to include(keyword)
    end

    it "leaves out one whose only site is not being tracked" do
      keyword = tracked(last_checked_at: nil)
      keyword.keyword_targets.update_all(tracking_enabled: false)

      expect(described_class.due).not_to include(keyword)
    end

    it "leaves out a paused one" do
      keyword = tracked(enabled: false, last_checked_at: nil)

      expect(described_class.due).not_to include(keyword)
    end
  end

  describe "#monthly_units" do
    it "multiplies the depth, the places and the cadence" do
      keyword = build(:dash_serp_keyword, pages: 2, locations: %w[us gb], frequency: :daily)

      expect(keyword.monthly_units(AhoyDashboard::Serp::Adapters::SerpApiAdapter)).to eq(120)
    end

    it "costs a seventh of that weekly" do
      keyword = build(:dash_serp_keyword, pages: 1, locations: %w[us], frequency: :weekly)

      expect(keyword.monthly_units(AhoyDashboard::Serp::Adapters::SerpApiAdapter)).to eq(5)
    end

    it "costs nothing while it is paused" do
      keyword = build(:dash_serp_keyword, enabled: false)

      expect(keyword.monthly_units(AhoyDashboard::Serp::Adapters::SerpApiAdapter)).to eq(0)
    end
  end

  describe "the search itself" do
    let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

    it "counts a new phrase, device or language as a different search" do
      expect(keyword.tap { |record| record.query = "visitation hours" }.search_changed?).to be(true)
      expect(keyword.reload.tap { |record| record.device = "mobile" }.search_changed?).to be(true)
      expect(keyword.reload.tap { |record| record.language = "es" }.search_changed?).to be(true)
    end

    it "does not count a change of case, place, depth or cadence" do
      keyword.assign_attributes(query: "Visiting Hours", locations: %w[us gb], pages: 2, frequency: :weekly)

      expect(keyword.search_changed?).to be(false)
    end
  end
end
