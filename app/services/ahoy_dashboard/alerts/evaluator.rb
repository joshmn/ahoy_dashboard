module AhoyDashboard
  module Alerts
    # What each rule actually looks at.
    #
    # Every rank rule reads the same two readings: the most recent check and the
    # one before it, per search and place. That pair is worked out once and
    # handed to all of them, so switching on six rules is one query rather than
    # six.
    #
    # A finding is a subject and a sentence, and the two checks it compared. The
    # newer check is what stops a position that stays down being reported every
    # hour: the unique index on rule and check means one comparison is reported
    # once, however many runs read it.
    class Evaluator
      Verdict = Data.define(:rule, :findings, :cleared) do
        def latches?
          rule.definition.rule.latches
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(rules: nil, now: Time.current, since: 2.days.ago)
        @rules = rules || AhoyDashboard::AlertRule.live.available.to_a
        @readings = Readings.new(now: now, since: since)
      end

      def call
        rules.select { |rule| rule.defined? && rule.available? }.map do |rule|
          evaluator = rule.definition.rule.new(rule, readings)

          Verdict.new(rule: rule, findings: evaluator.findings,
                      cleared: rule.definition.rule.latches ? evaluator.cleared : [])
        end
      end

      private

      attr_reader :rules, :readings
    end
  end
end
