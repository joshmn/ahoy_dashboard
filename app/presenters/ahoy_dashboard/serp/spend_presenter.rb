module AhoyDashboard
  module Serp
    class SpendPresenter
      BAND_KEYS = SpendQuery::KINDS

      KIND_LABELS = {
        "checks" => "Rank checks",
        "keywords" => "Keyword ideas",
        "backlinks" => "Backlink syncs"
      }.freeze

      def self.helpers
        ActionController::Base.helpers
      end

      attr_reader :spend

      delegate :name, :capped?, :saved?, :used, :cap, :percent, :forecast, :days, to: :spend

      def initialize(spend: nil, now: Time.current)
        @spend = spend || SpendQuery.call(now: now)
      end

      def label
        Settings::Display.serp_label(name)
      end

      def sample?
        name.to_s == Adapters::FakeAdapter.adapter_name
      end

      def share
        [ spend.share, 1.0 ].min
      end

      def threshold
        @threshold ||= tuned_threshold || NEAR_CAP_PERCENT
      end

      def warning?
        spend.near?(threshold)
      end

      def meter_label
        "#{number(used)} of #{number(cap)} units used, #{percent}% of the monthly cap"
      end

      def used_line
        return "#{counted(used, "unit")} this month. There is no cap." unless capped?

        "#{counted(used, "unit")} of #{number(cap)} this month. #{number(spend.left)} left."
      end

      def forecast_line
        return "Sample results cost nothing. #{scheduled_line}" if sample?
        return "Nothing else is scheduled before #{through}." unless forecast.any?

        "#{scheduled_line} #{cost_line}"
      end

      def cost_line
        return "That is #{counted(forecast.total, "unit")}." unless capped?

        if spend.over?
          "That is #{counted(forecast.total, "unit")}, which would take the month to " \
            "#{number(spend.projected)}. The cap stops the checks at #{number(cap)}."
        else
          "That is #{counted(forecast.total, "unit")}, ending the month at " \
            "#{number(spend.projected)} of #{number(cap)}."
        end
      end

      def scheduled_line
        return "Nothing is scheduled for the rest of the month." unless forecast.searches.positive?

        "#{counted(forecast.searches, "search")} #{forecast.searches == 1 ? "is" : "are"} scheduled " \
          "between now and #{through}."
      end

      def warning_title
        "#{percent}% of this month's cap is spent"
      end

      def warning_detail
        return "#{number(spend.left)} left of #{number(cap)}. #{over_line}" if spend.over?
        return "#{number(spend.left)} left of #{number(cap)}, and nothing else is scheduled this month." unless forecast.any?

        "#{number(spend.left)} left of #{number(cap)}, and #{counted(forecast.total, "unit")} " \
          "#{forecast.total == 1 ? "is" : "are"} already scheduled before #{through}."
      end

      def over_line
        "What is scheduled would spend #{number(forecast.total)} more, so checks stop " \
          "once the month reaches #{number(cap)}."
      end

      def legend
        BAND_KEYS.map do |kind|
          units = spend.count(kind)
          next if units.zero?

          { key: kind, label: kind_label(kind), units: units }
        end.select { |value| value }
      end

      def day_title(day)
        parts = BAND_KEYS.map do |kind|
          units = day.count(kind)
          "#{kind_label(kind).downcase} #{number(units)}" if units.positive?
        end.select { |value| value }
        detail = parts.any? ? parts.join(", ") : "nothing"

        "#{date(day.date)}: #{detail}"
      end

      def chart_label
        "Units spent each day from #{date(spend.starts_on)} to #{date(spend.today)}"
      end

      def dates
        return [] if days.empty?

        [ date(days.first.date), date(days.last.date) ].uniq
      end

      def footer
        return "A unit is one request to the provider. Sample results cost nothing." if sample?
        return no_cap_footer unless saved? && capped?

        "A unit is one request to the provider. Keyword lookups and backlink syncs spend from this " \
          "cap too, and the bars say which."
      end

      def no_cap_footer
        return "Nothing is counted against a cap until a provider is saved on Settings, Search provider." unless saved?

        "This provider has no cap, so nothing stops it spending. Set one on Settings, Search provider."
      end

      def number(value)
        self.class.helpers.number_with_delimiter(value.to_i)
      end

      def counted(value, word)
        "#{number(value)} #{word.pluralize(value.to_i)}"
      end

      private

      def kind_label(kind)
        KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)
      end

      def tuned_threshold
        return unless Alerts.installed?

        AhoyDashboard::AlertRule.find_by(key: "spend_near_cap")&.threshold_value.presence
      end

      def through
        date(forecast.through.to_date)
      end

      def date(value)
        value.strftime("%b %-d")
      end
    end
  end
end
