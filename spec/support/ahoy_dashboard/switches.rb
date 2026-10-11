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

  def ahoy_dashboard_preferences(scope, **values)
    AhoyDashboard::Preferences.write(scope, **values)
  end

  def ahoy_dashboard_switches
    (@ahoy_dashboard_switches ||= [])
  end
end

RSpec.configure do |config|
  config.include AhoyDashboardSwitches
  config.after { ahoy_dashboard_switches.reverse_each { |settings, key, was| settings[key] = was } }
end
