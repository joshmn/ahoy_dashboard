require "rails_helper"

RSpec.describe AhoyDashboard::Serp::DispatchJob do
  let(:site) { create(:dash_serp_site) }

  def tracked(**attributes)
    create(:dash_serp_keyword, :tracked, site: site, **attributes)
  end

  before { serp_enabled! }

  it "enqueues one check per place a keyword is watched from" do
    keyword = tracked(locations: %w[us gb])

    expect { described_class.perform_now }
      .to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob).with(keyword.id, "us")
      .and have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob).with(keyword.id, "gb")
  end

  it "leaves alone a keyword that is not due" do
    tracked(frequency: :weekly, last_checked_at: 1.hour.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)
  end

  it "does nothing while the tracking is switched off" do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    tracked

    expect { described_class.perform_now }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)
  end

  it "does nothing once the month's ceiling is reached" do
    create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 5, units_spent: 5,
           units_reset_on: Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.beginning_of_month)
    tracked

    expect { described_class.perform_now }.not_to have_enqueued_job(AhoyDashboard::Serp::Keywords::CheckJob)
  end
end
