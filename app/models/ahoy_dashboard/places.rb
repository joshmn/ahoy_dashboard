module AhoyDashboard
  module Places
    class Error < StandardError; end

    POSTAL = "postal code".freeze

    class << self
      def enabled?
        Features.on?(:places) && installed?
      end

      def installed?
        Installation.installed?(:places)
      end

      def postal_codes?
        Preferences.read(:places, :postal_codes)
      end

      def source_template
        Preferences.read(:places, :source)
      end

      def source_url(on)
        on.strftime(source_template)
      end

      def ready?
        enabled? && Place.ready?
      end

      def count
        return 0 unless installed?

        Place.count
      rescue ActiveRecord::ActiveRecordError
        0
      end

      def built_at
        installed? ? Place.built_at : nil
      end

      def note
        return Schedule.not_installed_reason(:places) unless installed?
        return "Off. The keyword forms keep the country list they already have." unless enabled?

        total = count
        return "Nothing built yet. Run it once and the keyword forms get a place picker." if total.zero?

        on = built_at
        stamp = on ? on.in_time_zone(AhoyDashboard.time_zone).strftime("%B %-d, %Y") : "an unknown date"

        "#{ActiveSupport::NumberHelper.number_to_delimited(total)} places, last rebuilt #{stamp}."
      end
    end
  end
end
