module AhoyDashboard
  module Alerts
    class Readings
      attr_reader :now, :since

      def initialize(now: Time.current, since: 2.days.ago)
        @now = now
        @since = since
      end

      def our_site
        return @our_site if defined?(@our_site)

        @our_site = installed?(:serp) ? AhoyDashboard::SerpSite.ours : nil
      end

      def rank_pairs
        @rank_pairs ||= RankPairsQuery.call(site: our_site, since: since)
      end

      def rivals
        @rivals ||= begin
          run_ids = rank_pairs.flat_map { |pair| [ pair.now&.run_id, pair.before&.run_id ] }.compact.uniq

          run_ids.empty? ? {} : rival_checks(run_ids)
        end
      end

      def serp_spend
        return @serp_spend if defined?(@serp_spend)

        @serp_spend = Rules::SpendNearCap.definition.available? ? Serp::SpendQuery.call(now: now) : nil
      end

      def search_console_weeks
        return @search_console_weeks if defined?(@search_console_weeks)

        @search_console_weeks = installed?(:search_console) ? SearchConsoleWeeksQuery.call(now: now) : nil
      end

      def goal_days
        @goal_days ||= GoalDaysQuery.call(now: now)
      end

      def latest_backlink_sample
        return @latest_backlink_sample if defined?(@latest_backlink_sample)

        @latest_backlink_sample = installed?(:backlinks) ? latest_sample : nil
      end

      def traffic
        return @traffic if defined?(@traffic)

        @traffic = TrafficQuery.call(now: now)
      end

      def jobs
        @jobs ||= begin
          records = AhoyDashboard::JobRun.all.index_by(&:key)

          Schedule::ALL.map { |entry| JobReading.new(entry: entry, record: records[entry.key], on: entry.on?, now: now) }
        end
      end

      JobReading = Data.define(:entry, :record, :on, :now) do
        def name
          entry.name
        end

        def on?
          on
        end

        def status
          record&.status
        end

        def failed?
          status == "failed"
        end

        def ok?
          status == "ok"
        end

        def stuck?
          record.present? && record.stuck?(now)
        end

        def last_started_at
          [ record&.last_run_at, record&.last_finished_at ].compact.max
        end

        def cadence
          entry.interval
        end

        def cadence_label
          return "hourly" if cadence == 1.hour
          return "daily" if cadence == 1.day
          return "monthly" if entry.monthly?

          "every #{ActiveSupport::Duration.build(cadence.to_i).inspect}"
        end

        def overdue?
          cadence.present? && last_started_at.present? && last_started_at < now - (cadence * 2)
        end
      end

      private

      def installed?(feature)
        Installation.installed?(feature)
      end

      def latest_sample
        AhoyDashboard::BacklinkSample.where(AhoyDashboard::BacklinkSample.arel_table[:on].gteq(since.to_date)).order(on: :desc).first
      end

      def rival_checks(run_ids)
        AhoyDashboard::SerpCheck.success.includes(:site)
          .where(run_id: run_ids)
          .where.not(site_id: our_site&.id)
          .group_by { |check| [ check.run_id, check.location ] }
      end
    end
  end
end
