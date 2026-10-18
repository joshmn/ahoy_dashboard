module AhoyDashboardSql
  IGNORED = %w[SCHEMA TRANSACTION].freeze
  ANALYTICS = /\b(?:FROM|JOIN)\s+"?ahoy_(?:visits|events)\b/i
  SETTINGS = 'FROM "ahoy_dashboard_settings"'.freeze

  def captured_sql(matching = nil, cached: false, uncached: false)
    statements = []
    subscriber = lambda do |*, payload|
      sql = payload[:sql]
      next if IGNORED.include?(payload[:name])
      next if payload[:cached] && !cached
      next if matching.is_a?(Regexp) && !sql.match?(matching)
      next if matching.is_a?(String) && !sql.include?(matching)

      statements << sql
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      uncached ? ActiveRecord::Base.uncached { yield } : yield
    end
    statements
  end

  def analytics_sql(&block)
    captured_sql(ANALYTICS, uncached: true, &block)
  end

  def setting_reads(&block)
    captured_sql(SETTINGS, cached: true, &block).size
  end

  def instantiated(class_name)
    count = 0
    subscriber = lambda do |*, payload|
      count += payload[:record_count] if payload[:class_name] == class_name.to_s
    end
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { yield }
    count
  end
end

RSpec.configure { |config| config.include AhoyDashboardSql }
