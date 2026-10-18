module AhoyDashboard
  module Alerts
    class DigestQuery
      Result = Data.define(:window, :events, :total, :severities, :checked, :rules_on, :rank_rules_on, :invented,
                           :waiting) do
        def initialize(waiting: [], **rest)
          super
        end

        def empty?
          total.zero?
        end

        def rules_ran
          rules_on - waiting.size
        end

        def more
          total - events.size
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(window:, limit: Digests::ROW_LIMIT)
        @window = window
        @limit = limit
      end

      def call
        events = distinct_events

        live = AhoyDashboard::AlertRule.live.ordered.to_a
        waiting, runnable = live.partition { |rule| !rule.available? }

        Result.new(window: window, events: events.first(limit), total: events.size,
                   severities: events.map(&:severity).each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }, checked: checked, rules_on: live.size,
                   rank_rules_on: runnable.count { |rule| rule.group == :rank }, invented: invented(events),
                   waiting: waiting)
      end

      private

      attr_reader :window, :limit

      def distinct_events
        latest = AhoyDashboard::AlertEvent.in_range(window.range)
          .select("distinct on (rule_id, subject) ahoy_dashboard_alert_events.*")
          .order(:rule_id, :subject, fired_at: :desc, id: :desc)

        AhoyDashboard::AlertEvent.from(latest, :ahoy_dashboard_alert_events).includes(:rule).latest_first.to_a
          .sort_by { |event| [ AhoyDashboard::AlertEvent.severities.fetch(event.severity), event.subject, event.rule.name ] }
      end

      def checked
        return 0 unless AhoyDashboard::Serp.installed?

        site = AhoyDashboard::SerpSite.ours
        return 0 if site.nil?

        AhoyDashboard::SerpCheck.success.where(site_id: site.id, checked_at: window.range)
          .distinct.count(Arel.sql("(keyword_id, location)"))
      end

      def invented(events)
        return 0 if events.empty?

        AhoyDashboard::AlertEvent.from_sample_data.where(id: events.map(&:id)).count
      end
    end
  end
end
