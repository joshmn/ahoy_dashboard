module AhoyDashboard
  module Alerts
    module Rules
      class UpdateCommand < AhoyDashboard::Command
        def initialize(rule:, attributes:)
          @rule = rule
          @attributes = attributes
        end

        def call
          waiting_on = rule.waiting_on
          return broadcast(:refused, waiting_on) if waiting_on && ActiveModel::Type::Boolean.new.cast(attributes[:enabled])
          return broadcast(:invalid, rule) unless rule.update(attributes)

          broadcast(:ok, rule)
        end

        private

        attr_reader :rule, :attributes
      end
    end
  end
end
