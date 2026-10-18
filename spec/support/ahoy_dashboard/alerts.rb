module AlertFixtures
  def run_alert_rules(*rules)
    AhoyDashboard::Alerts::RunCommand.call(rules: rules)
  end

  def alert_events(rule)
    AhoyDashboard::AlertEvent.where(rule: rule).order(:id)
  end
end

RSpec.configure { |config| config.include AlertFixtures }
