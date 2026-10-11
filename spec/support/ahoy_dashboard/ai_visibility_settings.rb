require_relative "switches"

module AiVisibilitySettingsFixtures
  def ai_visibility_settings(**values, &block)
    with_ahoy_dashboard_settings(:ai_visibility, **values, &block)
  end
end

RSpec.configure { |config| config.include AiVisibilitySettingsFixtures }
