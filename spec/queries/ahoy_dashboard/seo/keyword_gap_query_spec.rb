require "rails_helper"

RSpec.describe AhoyDashboard::Seo::KeywordGapQuery do
  let(:range) { 7.days.ago..Time.current }
  let(:ours) { create(:dash_serp_site, name: "Ours") }
  let(:ticked) { create(:dash_serp_site, name: "Ticked") }
  let!(:unticked) { create(:dash_serp_site, name: "Unticked") }
  let(:contested) { create(:dash_serp_keyword, query: "fci thomson visiting") }
  let(:empty) { create(:dash_serp_keyword, query: "fci thomson commissary") }

  before do
    [ [ contested, 5, 3 ], [ empty, nil, nil ] ].each do |keyword, mine, theirs|
      run = create(:dash_serp_run, keyword: keyword, checked_at: 1.day.ago)
      create(:dash_serp_check, run: run, site: ours, position: mine)
      create(:dash_serp_check, run: run, site: ticked, position: theirs)
    end
  end

  def presenter(result)
    AhoyDashboard::Seo::KeywordGapPresenter.new(
      query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("keyword_gap"), result: result, site: ours
    )
  end

  def standing(row, site)
    row.rivals.find { |stand| stand.site.id == site.id }
  end

  it "puts a search nobody ranks on in a group of its own, so every search counted sits somewhere" do
    result = described_class.call(site: ours, range: range)
    groups = presenter(result).groups

    expect(result.rows.size).to eq(2)
    expect(groups.sum { |group| group.rows.size }).to eq(result.rows.size)
    expect(groups.find { |group| group.key == :nobody }.title).to eq("Nobody ranks")
    expect(groups.find { |group| group.key == :nobody }.rows.map(&:query)).to eq([ "fci thomson commissary" ])
  end

  it "counts only the competitors attached to these searches in the Rivals tile" do
    result = described_class.call(site: ours, range: range)
    tile = presenter(result).tiles.find { |candidate| candidate.label == "Rivals" }

    expect(result.rivals.map(&:name)).to contain_exactly("Ticked", "Unticked")
    expect(tile.value).to eq("1")
    expect(tile.note).to eq("attached to these searches")
  end

  it "says a competitor is not tracked on a search rather than calling it nowhere" do
    result = described_class.call(site: ours, range: range)
    row = result.rows.find { |candidate| candidate.query == "fci thomson visiting" }
    blank = result.rows.find { |candidate| candidate.query == "fci thomson commissary" }

    expect(presenter(result).position_label(standing(row, unticked))).to eq("Not tracked")
    expect(presenter(result).position_label(standing(row, ticked))).to eq("3")
    expect(presenter(result).position_label(standing(blank, ticked))).to eq("Nowhere")
  end

  it "counts a competitor ticked on a search as tracked before its first check lands" do
    create(:dash_serp_keyword_target, keyword: contested, site: unticked)

    result = described_class.call(site: ours, range: range)
    row = result.rows.find { |candidate| candidate.query == "fci thomson visiting" }

    expect(presenter(result).position_label(standing(row, unticked))).to eq("Nowhere")
    expect(result.attached.map(&:name)).to contain_exactly("Ticked", "Unticked")
  end
end
