require_relative "switches"

module AlertFixtures
  def alert_settings(**values, &block)
    with_ahoy_dashboard_settings(:alerts, **values, &block)
  end

  def our_serp_site
    AhoyDashboard::SerpSite.ours || create(:dash_serp_site, domain: AhoyDashboard::Serp.own_domain)
  end

  def serp_reading(keyword, position:, at:, provider: "fake", location: "us")
    run = create(:dash_serp_run, keyword: keyword, provider: provider, location: location, checked_at: at)
    create(:dash_serp_check, run: run, keyword: keyword, site: our_serp_site, location: location,
                             position: position, checked_at: at)
  end
end

RSpec.configure { |config| config.include AlertFixtures }
