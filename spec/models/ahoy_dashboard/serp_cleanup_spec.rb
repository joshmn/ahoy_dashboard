require "rails_helper"

RSpec.describe "Removing rank tracking records" do
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:rival) { create(:dash_serp_site, name: "Them", domain: "rival.com") }
  let(:keyword) { create(:dash_serp_keyword) }
  let(:run) { create(:dash_serp_run, keyword: keyword) }
  let!(:check) { create(:dash_serp_check, run: run, site: site) }
  let!(:rival_check) { create(:dash_serp_check, run: run, site: rival) }
  let!(:event) { create(:dash_alert_event, rule: create(:dash_alert_rule), check: check, previous_check: rival_check) }

  before do
    create(:dash_serp_result, run: run)
    create(:dash_serp_ai_citation, run: run)
    create(:dash_serp_run_page, run: run)
  end

  def counts
    [ AhoyDashboard::SerpKeywordTarget, AhoyDashboard::SerpRun, AhoyDashboard::SerpCheck, AhoyDashboard::SerpResult,
      AhoyDashboard::SerpAiCitation, AhoyDashboard::SerpRunPage ].map(&:count)
  end

  it "takes a keyword's targets, runs, checks and everything a run read with it, and unlinks its alerts" do
    expect(counts).to eq([ 2, 1, 2, 1, 1, 1 ])

    keyword.destroy!

    expect(counts).to eq([ 0, 0, 0, 0, 0, 0 ])
    expect(event.reload).to have_attributes(check_id: nil, previous_check_id: nil)
  end

  it "takes a site's targets and checks and leaves the runs other sites share" do
    site.destroy!

    expect(counts).to eq([ 1, 1, 1, 1, 1, 1 ])
    expect(AhoyDashboard::SerpCheck.pluck(:id)).to eq([ rival_check.id ])
    expect(event.reload).to have_attributes(check_id: nil, previous_check_id: rival_check.id)
  end

  it "takes a run's checks, results, citations and pages" do
    run.destroy!

    expect(counts).to eq([ 2, 0, 0, 0, 0, 0 ])
  end

  it "takes a target's checks and leaves the other site's" do
    AhoyDashboard::SerpKeywordTarget.find_by!(site: site).destroy!

    expect(AhoyDashboard::SerpCheck.pluck(:id)).to eq([ rival_check.id ])
  end
end
