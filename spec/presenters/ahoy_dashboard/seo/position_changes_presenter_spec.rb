require "rails_helper"

RSpec.describe AhoyDashboard::Seo::PositionChangesPresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 8, 10, 12) }
  let(:range) { (now - 7.days).beginning_of_day..now.end_of_day }
  let(:site) { create(:dash_serp_site) }

  around { |example| travel_to(now) { example.run } }

  it "reads two checks from one evening in the dashboard's time zone as one day" do
    keyword = create(:dash_serp_keyword)
    [ [ zone.local(2026, 8, 9, 17), 8 ], [ zone.local(2026, 8, 9, 22), 4 ] ].each do |at, position|
      create(:dash_serp_check, run: create(:dash_serp_run, keyword: keyword, checked_at: at), site: site, position: position)
    end

    result = AhoyDashboard::Seo::PositionChangesQuery.call(site: site, range: range)
    presenter = described_class.new(query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("position_changes"),
                                    result: result, site: site)

    expect(presenter.window(sole_item(result.rows))).to eq("Aug 9")
    expect(presenter.window_note).to eq("Every search here was read on Aug 9.")
  end
end
