module AhoyDashboard
  module Alerts
    class Evaluator
      Verdict = Data.define(:rule, :findings, :cleared) do
        def latches?
          rule.definition.rule.latches
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(rules:)
        @rules = rules
        @readings = Readings.new
      end

      def call
        rules.map do |rule|
          evaluator = rule.definition.rule.new(rule, readings)

          Verdict.new(rule: rule, findings: evaluator.findings, cleared: evaluator.cleared)
        end
      end

      private

      attr_reader :rules, :readings
    end
  end
end
