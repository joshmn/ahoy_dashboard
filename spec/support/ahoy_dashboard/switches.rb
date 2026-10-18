module AhoyDashboardSwitches
  def switch_on_ahoy_dashboard(*names, **values)
    names.each do |name|
      AhoyDashboard::Preferences.write(name, enabled: true, **values)
    end
  end

  def switch_off_ahoy_dashboard(*names)
    names.each { |name| AhoyDashboard::Preferences.write(name, enabled: false) }
  end

  def with_ahoy_dashboard_settings(scope, **values)
    preferences, configured = values.partition { |key, _| AhoyDashboard::Preferences.definitions.key?([ scope.to_sym, key.to_sym ]) }.map(&:to_h)
    keys = preferences.keys.map { |key| AhoyDashboard::Preferences.definition(scope, key).key }
    saved = AhoyDashboard::Preferences.stored.slice(*keys)
    AhoyDashboard::Preferences.write(scope, **preferences)

    if configured.any?
      settings = AhoyDashboard.config.public_send(scope)
      original = configured.keys.index_with { |key| settings[key] }
      configured.each { |key, value| settings[key] = value }
    end
    yield
  ensure
    original&.each { |key, value| settings[key] = value }
    if keys
      AhoyDashboard::Setting.where(key: keys - saved.keys).delete_all
      saved.each { |key, value| AhoyDashboard::Setting.write(key, value) }
      AhoyDashboard::Preferences.forget
    end
  end

  def alert_settings(**values, &block)
    with_ahoy_dashboard_settings(:alerts, **values, &block)
  end

  def report_settings(**values, &block)
    with_ahoy_dashboard_settings(:reports, **values, &block)
  end

  def ai_visibility_settings(**values, &block)
    with_ahoy_dashboard_settings(:ai_visibility, **values, &block)
  end

  def search_console_settings(**values, &block)
    with_ahoy_dashboard_settings(:search_console, **values, &block)
  end

  def serp_settings(**values, &block)
    with_ahoy_dashboard_settings(:serp, **values, &block)
  end
end

RSpec.configure { |config| config.include AhoyDashboardSwitches }
