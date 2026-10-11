require_relative "switches"

module ReportEmailFixtures
  def report_settings(**values, &block)
    with_ahoy_dashboard_settings(:reports, **values, &block)
  end
end

RSpec.configure { |config| config.include ReportEmailFixtures }
