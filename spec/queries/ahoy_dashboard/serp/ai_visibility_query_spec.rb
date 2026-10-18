require "rails_helper"

RSpec.describe AhoyDashboard::Serp::AiVisibilityQuery do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }
  let(:site) { create(:dash_serp_site, domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword) }

  around { |example| travel_to(now) { example.run } }

  def reading(at:, overview:, cited:, citations: [])
    run = serp_reading(keyword, site: site, at: at, position: 4, ai_overview_present: overview,
                                ai_overview_cited: cited).run
    citations.each_with_index do |domain, index|
      create(:dash_serp_ai_citation, run: run, slot: index + 1, link: "https://#{domain}/x",
             domain: domain, checked_at: at)
    end
    run
  end

  it "counts what showed an overview and what got quoted in one" do
    reading(at: now - 3.days, overview: true, cited: true, citations: %w[bop.gov example.com])
    reading(at: now - 2.days, overview: true, cited: false, citations: %w[bop.gov])
    reading(at: now - 1.day, overview: false, cited: false)

    result = described_class.call(site: site, range: range)

    expect(result.checks).to eq(3)
    expect(result.shown).to eq(2)
    expect(result.cited).to eq(1)
    expect(result.share_shown).to be_within(0.01).of(0.667)
    expect(result.share_cited).to eq(0.5)
  end

  it "ranks who gets quoted, most first" do
    reading(at: now - 2.days, overview: true, cited: false, citations: %w[bop.gov justice.gov])
    reading(at: now - 1.day, overview: true, cited: false, citations: %w[bop.gov])

    domains = described_class.call(site: site, range: range).domains

    expect(domains.map(&:domain)).to eq(%w[bop.gov justice.gov])
    expect(domains.first.citations).to eq(2)
    expect(domains.first.share).to eq(1.0)
  end

  it "counts cited domains only from the site's own searches, so a share never passes 100%" do
    reading(at: now - 1.day, overview: true, cited: false, citations: %w[bop.gov bop.gov])
    elsewhere = create(:dash_serp_run, checked_at: now - 1.day)
    create(:dash_serp_ai_citation, run: elsewhere, slot: 1, link: "https://bop.gov/y", domain: "bop.gov",
           checked_at: elsewhere.checked_at)
    create(:dash_serp_ai_citation, run: elsewhere, slot: 2, link: "https://justice.gov/y", domain: "justice.gov",
           checked_at: elsewhere.checked_at)

    domains = described_class.call(site: site, range: range).domains

    expect(domains.map { |row| [ row.domain, row.citations, row.share ] }).to eq([ [ "bop.gov", 1, 1.0 ] ])
  end

  it "does not divide by nothing when no overview has ever shown" do
    reading(at: now - 1.day, overview: false, cited: false)

    result = described_class.call(site: site, range: range)

    expect(result.share_cited).to eq(0.0)
    expect(result.domains).to be_empty
  end

  it "leaves out a check that was never asked about an overview" do
    serp_reading(keyword, site: site, at: now - 1.day, position: 3, ai_overview_present: nil)

    expect(described_class.call(site: site, range: range).checks).to be_zero
  end
end
