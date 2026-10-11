module AhoyDashboardInstallation
  attr_reader :ahoy_dashboard_schema_changed

  def self.tables_for(names)
    names = Array(names).map(&:to_sym)
    kept = AhoyDashboard::Installation::FEATURES.reject { |feature| names.include?(feature.name) }.flat_map(&:tables)

    names.flat_map { |name| AhoyDashboard::Installation.fetch(name).tables }.uniq - kept
  end

  def self.forget_schema!
    AhoyDashboard::Record.connection.schema_cache.clear!
    AhoyDashboard::Current.tables = nil
  end

  def uninstall_ahoy_dashboard(*names)
    @ahoy_dashboard_schema_changed = true
    connection = AhoyDashboard::Record.connection
    AhoyDashboardInstallation.tables_for(names).each { |table| connection.drop_table(table, force: :cascade) }
    AhoyDashboardInstallation.forget_schema!
  end

  def uninstall_every_ahoy_dashboard_feature
    uninstall_ahoy_dashboard(*AhoyDashboard::Installation.names)
  end
end

RSpec.configure do |config|
  config.include AhoyDashboardInstallation
  config.after { AhoyDashboardInstallation.forget_schema! if ahoy_dashboard_schema_changed }
end
