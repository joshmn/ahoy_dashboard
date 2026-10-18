module AhoyDashboard
  module Alerts
    class RunCommand < AhoyDashboard::Command
      Outcome = Data.define(:fired, :delivered, :repeats)

      def initialize(rules: nil)
        @rules = rules
      end

      def call
        return broadcast(:disabled) unless Alerts.enabled?

        live = (rules || AhoyDashboard::AlertRule.live.available.to_a).select { |rule| rule.defined? && rule.available? }
        return broadcast(:nothing_on) if live.empty?

        verdicts = Evaluator.call(rules: live)
        fired, repeats = record(verdicts)
        clear(verdicts)
        delivered = fired.count { |event| deliver(event) }

        touch(live, fired)

        broadcast(:ok, Outcome.new(fired: fired, delivered: delivered, repeats: repeats))
      end

      private

      attr_reader :rules

      def deliver(event)
        return false unless Alerts.deliverable?

        Alerts.notifier.call(event)
        event.update_columns(delivered_at: Time.current, delivery_error: nil, updated_at: Time.current)
        true
      rescue StandardError => e
        event.update_columns(delivery_error: "#{e.class}: #{e.message}".first(255), updated_at: Time.current)
        false
      end

      def record(verdicts)
        fired = []
        repeats = 0
        now = Time.current

        verdicts.each do |verdict|
          said = already_said(verdict)

          verdict.findings.each do |finding|
            if said.call(finding)
              repeats += 1
              next
            end

            fired << AhoyDashboard::AlertEvent.create!(
              rule: verdict.rule, fired_at: now, severity: verdict.rule.severity, headline: finding.headline,
              detail: finding.detail, subject: finding.subject, reading: finding.reading,
              sample_data: finding.sample_data,
              check_id: finding.check_id, previous_check_id: finding.previous_check_id
            )
          rescue ActiveRecord::RecordNotUnique
            repeats += 1
          end
        end

        [ fired, repeats ]
      end

      def already_said(verdict)
        events = AhoyDashboard::AlertEvent.where(rule_id: verdict.rule.id)
        findings = verdict.findings

        checks = pluck_set(events, :check_id, findings.map(&:check_id).select { |value| value })
        readings = events.where(reading: findings.map(&:reading).select { |value| value }.uniq, subject: findings.map(&:subject).uniq)
          .pluck(:subject, :reading).to_set
        open = verdict.latches? ? pluck_set(events.unresolved, :subject, findings.map(&:subject)) : Set.new

        lambda do |finding|
          checks.include?(finding.check_id) || readings.include?([ finding.subject, finding.reading ]) ||
            open.include?(finding.subject)
        end
      end

      def pluck_set(events, column, values)
        return Set.new if values.empty?

        events.where(column => values.uniq).pluck(column).to_set
      end

      def clear(verdicts)
        now = Time.current

        verdicts.each do |verdict|
          next if verdict.cleared.empty?

          AhoyDashboard::AlertEvent.unresolved.where(rule_id: verdict.rule.id, subject: verdict.cleared.uniq)
            .update_all(cleared_at: now, updated_at: now)
        end
      end

      def touch(live, fired)
        now = Time.current
        fired_by = fired.group_by(&:rule_id)

        live.each do |rule|
          events = fired_by.fetch(rule.id, [])
          rows = AhoyDashboard::AlertRule.where(id: rule.id)

          if events.empty?
            rows.update_all(last_checked_at: now, updated_at: now)
          else
            rows.update_all([ "last_checked_at = ?, last_fired_at = ?, fired_count = fired_count + ?, updated_at = ?",
                              now, events.map(&:fired_at).max, events.size, now ])
          end
        end
      end
    end
  end
end
