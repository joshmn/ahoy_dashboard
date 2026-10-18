require "rails_helper"

RSpec.describe "Rank queries read one tag at a time" do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:range) { (now - 7.days)..now }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:rival) { create(:dash_serp_site, name: "Them", domain: "rival.com") }
  let!(:branded) { create(:dash_serp_keyword, query: "federal prison consultant", tags: [ "Brand" ]) }
  let!(:plain) { create(:dash_serp_keyword, query: "visiting hours", tags: [ "Guides" ]) }

  around { |example| travel_to(now) { example.run } }

  before do
    [ branded, plain ].each do |keyword|
      [ 3, 1 ].each do |days_ago|
        run = create(:dash_serp_run, keyword: keyword, checked_at: now - days_ago.days)
        create(:dash_serp_check, run: run, site: site, position: days_ago + 1,
               ai_overview_present: true, ai_overview_cited: true)
        create(:dash_serp_check, run: run, site: rival, position: days_ago + 2)
        create(:dash_serp_result, run: run, position: 1, link: "https://#{keyword.query.parameterize}.com/#{days_ago}")
        create(:dash_serp_ai_citation, run: run, link: "https://cited-#{keyword.query.parameterize}.com/a")
        create(:dash_serp_run_page, run: run)
      end
    end
  end

  def queries_of(rows)
    rows.map { |row| row.respond_to?(:query) ? row.query : row.keyword.query }.uniq
  end

  it "narrows Rankings" do
    result = AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: range, tag: "Brand")

    expect(result.rows.map { |row| row.keyword.query }).to eq([ "federal prison consultant" ])
    expect(AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: range).rows.size).to eq(2)
  end

  it "narrows the AI overview counts and the cited domains" do
    result = AhoyDashboard::Serp::AiVisibilityQuery.call(site: site, range: range, tag: "Brand")

    expect(result.checks).to eq(2)
    expect(result.domains.map(&:domain)).to eq([ "cited-federal-prison-consultant.com" ])
  end

  it "narrows who else is on page one" do
    result = AhoyDashboard::Serp::ShareOfPageOneQuery.call(range: range, tag: "Brand")

    expect(result.searches).to eq(1)
    expect(result.rows.map(&:domain)).to eq([ "federal-prison-consultant.com" ])
  end

  it "narrows Visibility, denominator included" do
    result = AhoyDashboard::Seo::VisibilityQuery.call(site: site, range: range, tag: "Brand")

    expect(result.tracked).to eq(1)
    expect(queries_of(result.rows)).to eq([ "federal prison consultant" ])
  end

  it "narrows Position changes" do
    result = AhoyDashboard::Seo::PositionChangesQuery.call(site: site, range: range, tag: "Brand")

    expect(queries_of(result.rows)).to eq([ "federal prison consultant" ])
  end

  it "narrows Keyword gap" do
    rival
    result = AhoyDashboard::Seo::KeywordGapQuery.call(site: site, range: range, tag: "Brand")

    expect(queries_of(result.rows)).to eq([ "federal prison consultant" ])
  end

  it "narrows Volatility" do
    result = AhoyDashboard::Seo::VolatilityQuery.call(range: range, tag: "Brand")

    expect(queries_of(result.comparisons)).to eq([ "federal prison consultant" ])
  end

  it "narrows SERP features" do
    result = AhoyDashboard::Seo::SerpFeaturesQuery.call(site: site, range: range, tag: "Brand")

    expect(queries_of(result.rows)).to eq([ "federal prison consultant" ])
  end

  it "reads nothing for a tag nobody carries" do
    result = AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: range, tag: "Nobody")

    expect(result.rows).to be_empty
  end
end
