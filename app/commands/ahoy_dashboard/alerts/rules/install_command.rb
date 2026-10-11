module AhoyDashboard
  module Alerts
    module Rules
      class InstallCommand < AhoyDashboard::Command
        Outcome = Data.define(:added, :removed)

        def call
          return broadcast(:not_installed) unless Alerts.installed?

          definitions = Catalogue.all
          existing = AhoyDashboard::AlertRule.where(key: definitions.map(&:key)).pluck(:key).to_set
          added = definitions.reject { |definition| existing.include?(definition.key) }
                             .map { |definition| install(definition) }
                             .count(&:saved_change_to_id?)
          broadcast(:ok, Outcome.new(added: added, removed: 0))
        end

        private

        def install(definition)
          AhoyDashboard::AlertRule.find_or_create_by!(key: definition.key) do |rule|
            rule.name = definition.name
            rule.severity = definition.severity
            rule.threshold = definition.default_threshold
            rule.floor = definition.default_floor
            rule.enabled = false
          end
        end
      end
    end
  end
end
