require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::ShareOfPageOneQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:range) { (now - 30.days)..now }

  around { |example| travel_to(now) { example.run } }

  def ranked(keyword:, at:, domains:, location: "us")
    run = create(:dash_serp_run, keyword: keyword, location: location, checked_at: at)
    domains.each_with_index do |domain, index|
      create(:dash_serp_result, run: run, position: index + 1, link: "https://#{domain}/x",
             domain: domain, checked_at: at)
    end
    run
  end

  it "counts how many searches a domain holds a place on" do
    first = create(:dash_serp_keyword, query: "one")
    second = create(:dash_serp_keyword, query: "two")
    ranked(keyword: first, at: now - 1.day, domains: %w[bop.gov example.com])
    ranked(keyword: second, at: now - 1.day, domains: %w[bop.gov justice.gov])

    result = described_class.call(range: range)

    expect(result.searches).to eq(2)
    expect(result.rows.map { |row| [ row.domain, row.appearances, row.best ] })
      .to eq([ [ "bop.gov", 2, 1 ], [ "example.com", 1, 2 ], [ "justice.gov", 1, 2 ] ])
    expect(result.rows.first.share).to eq(1.0)
  end

  it "reads only the most recent search, so a domain is not ranked by how often it ran" do
    keyword = create(:dash_serp_keyword)
    ranked(keyword: keyword, at: now - 5.days, domains: %w[gone.com])
    ranked(keyword: keyword, at: now - 1.day, domains: %w[here.com])

    result = described_class.call(range: range)

    expect(result.searches).to eq(1)
    expect(result.rows.map(&:domain)).to eq([ "here.com" ])
  end

  it "counts each place separately, because they are different results pages" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    ranked(keyword: keyword, at: now - 1.day, domains: %w[bop.gov], location: "us")
    ranked(keyword: keyword, at: now - 1.day, domains: %w[bop.gov], location: "gb")

    expect(described_class.call(range: range).searches).to eq(2)
  end

  it "stops at the depth it was asked for" do
    keyword = create(:dash_serp_keyword)
    ranked(keyword: keyword, at: now - 1.day, domains: (1..12).map { |n| "site-#{n}.com" })

    result = described_class.call(range: range, depth: 3)

    expect(result.rows.map(&:domain)).to eq(%w[site-1.com site-2.com site-3.com])
  end

  it "leaves out a search that failed" do
    keyword = create(:dash_serp_keyword)
    run = ranked(keyword: keyword, at: now - 1.day, domains: %w[bop.gov])
    run.update!(status: :failed)

    expect(described_class.call(range: range).searches).to be_zero
  end

  it "counts a domain once per search however many results it holds, so a share never passes 100%" do
    keyword = create(:dash_serp_keyword)
    ranked(keyword: keyword, at: now - 1.day, domains: %w[bop.gov bop.gov justice.gov])

    row = described_class.call(range: range).rows.first

    expect([ row.domain, row.appearances, row.share ]).to eq([ "bop.gov", 1, 1.0 ])
  end

  it "reads only the searches recorded for the site it is given" do
    site = create(:dash_serp_site)
    ours = create(:dash_serp_keyword)
    other = create(:dash_serp_keyword)
    run = ranked(keyword: ours, at: now - 1.day, domains: %w[bop.gov])
    create(:dash_serp_check, run: run, keyword: ours, site: site)
    ranked(keyword: other, at: now - 1.day, domains: %w[justice.gov])

    result = described_class.call(range: range, site: site)

    expect(result.searches).to eq(1)
    expect(result.rows.map(&:domain)).to eq([ "bop.gov" ])
  end

  it "leaves out a place the keyword no longer searches from" do
    keyword = create(:dash_serp_keyword, locations: %w[us gb])
    ranked(keyword: keyword, at: now - 1.day, domains: %w[bop.gov], location: "us")
    ranked(keyword: keyword, at: now - 1.day, domains: %w[gone.co.uk], location: "gb")
    keyword.update!(locations: %w[us])

    result = described_class.call(range: range)

    expect(result.searches).to eq(1)
    expect(result.rows.map(&:domain)).to eq([ "bop.gov" ])
  end

  it "answers with nothing for a range with no searches in it" do
    expect(described_class.call(range: range)).not_to be_any
  end
end
