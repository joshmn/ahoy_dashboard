module AhoyDashboard
  module DateFormat
    SHORT = "%b %-d".freeze
    LONG = "%b %-d, %Y".freeze

    class << self
      def short(value, zone: AhoyDashboard.time_zone, today: zone.today)
        date = local(value, zone: zone)
        return nil if date.nil?

        date.strftime(date.year == today.year ? SHORT : LONG)
      end

      def local(value, zone: AhoyDashboard.time_zone)
        return nil if value.nil?
        return value if value.instance_of?(Date)
        return value.in_time_zone(zone).to_date if value.respond_to?(:in_time_zone) && !value.is_a?(String)

        value.to_date
      end

      def span(first, last, zone: AhoyDashboard.time_zone, today: zone.today)
        return short(first, zone: zone, today: today) if first == last

        "#{short(first, zone: zone, today: today)} to #{short(last, zone: zone, today: today)}"
      end

      def ago(time, never: "Never")
        return never if time.nil?

        "#{ActionController::Base.helpers.time_ago_in_words(time).delete_prefix("about ")} ago"
      end
    end
  end
end
