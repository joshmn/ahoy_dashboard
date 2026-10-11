module AhoyDashboard
  module Seo
    class AlertsQuery
      Result = Data.define(:range, :rules, :events, :page, :total, :firing, :failed_alerts, :sample, :sample_ids,
                           :deliverable, :enabled, :emails, :failed_emails) do
        def any?
          rules.any?
        end

        def live
          rules.select(&:enabled)
        end

        def quiet
          rules.count(&:quiet?)
        end

        def undelivered
          failed_alerts + failed_emails
        end

        def pages
          [ (total.to_f / LIMIT).ceil, 1 ].max
        end

        def more?
          page < pages
        end

        def sample?
          sample.positive?
        end

        def sample_data?(event)
          sample_ids.include?(event.id)
        end

        def deliverable?
          deliverable
        end

        def emailing?
          emails.any?
        end

        def enabled?
          enabled
        end
      end

      LIMIT = 40

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, page: 1)
        @range = range
        @page = [ page.to_i, 1 ].max
      end

      def call
        total, firing, failed_alerts, sample = counts
        page = [ @page, [ (total.to_f / LIMIT).ceil, 1 ].max ].min
        events = in_range.includes(:rule).latest_first.offset((page - 1) * LIMIT).limit(LIMIT).to_a

        Result.new(range: range, rules: rules, events: events, page: page, total: total,
                   firing: firing, failed_alerts: failed_alerts,
                   sample: sample,
                   sample_ids: in_range.from_sample_data.where(id: events.map(&:id)).pluck(:id).to_set,
                   deliverable: ::AhoyDashboard::Alerts.deliverable?, enabled: ::AhoyDashboard::Alerts.enabled?,
                   emails: emails, failed_emails: failed_emails)
      end

      private

      attr_reader :range

      def counts
        in_range.pick(
          Arel.sql("count(*)"),
          Arel.sql("count(*) filter (where severity = #{AhoyDashboard::AlertEvent.severities.fetch('high')})"),
          Arel.sql("count(delivery_error)"),
          sample_count
        )
      end

      def rules
        AhoyDashboard::AlertRule.ordered.to_a
      end

      def sample_count
        predicate = AhoyDashboard::AlertEvent.from_sample_data.where_clause.ast
        Arel::Nodes::Count.new([ Arel::Nodes::Case.new.when(predicate).then(1) ])
      end

      def in_range
        AhoyDashboard::AlertEvent.in_range(range)
      end

      def emails
        ::AhoyDashboard::Alerts::Digests.enabled? ? ::AhoyDashboard::Alerts::Digests.periods : []
      end

      def failed_emails
        AhoyDashboard::AlertDigest.failed.where(starts_on: range.begin.to_date..range.end.to_date).count
      end
    end
  end
end
