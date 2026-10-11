module AhoyDashboard
  # The period arithmetic behind every scheduled email. Alerts and traffic
  # reports are two different emails with the same shape: a daily, weekly or
  # monthly window that has ended, cut in the dashboard's own zone, sent once.
  #
  # One place rather than two because the window is the part that has to agree.
  # A week starting Monday in one email and Sunday in the other is the kind of
  # difference nobody notices until two emails land on the same morning and
  # disagree about the same days.
  module Digests
    PERIODS = %i[daily weekly monthly].freeze

    class UnknownPeriodError < ArgumentError; end

    Window = Data.define(:period, :starts_on, :ends_on) do
      def range(zone = AhoyDashboard.time_zone)
        starts_on.in_time_zone(zone)...(ends_on + 1).in_time_zone(zone)
      end

      # What this window is measured against. A month compares to the calendar
      # month before it rather than to the same number of days, because a report
      # holding August up against the 31 days ending July 31 is comparing it to
      # something nobody has a name for.
      def previous
        case period
        when :daily then with(starts_on: starts_on - 1, ends_on: ends_on - 1)
        when :weekly then with(starts_on: starts_on - 7, ends_on: ends_on - 7)
        when :monthly then starts_on.prev_month.yield_self { |first| with(starts_on: first, ends_on: first.end_of_month) }
        end
      end
    end

    def self.period!(value)
      key = value.to_s.strip.downcase.to_sym
      return key if PERIODS.include?(key)

      raise UnknownPeriodError, "#{value.inspect} is not a period. Use daily, weekly or monthly."
    end

    def self.last_window(period, now: Time.current)
      today = now.in_time_zone(AhoyDashboard.time_zone).to_date

      case period
      when :daily
        Window.new(period: :daily, starts_on: today - 1, ends_on: today - 1)
      when :weekly
        starts_on = today.beginning_of_week(:monday) - 7
        Window.new(period: :weekly, starts_on: starts_on, ends_on: starts_on + 6)
      when :monthly
        starts_on = today.prev_month.beginning_of_month
        Window.new(period: :monthly, starts_on: starts_on, ends_on: starts_on.end_of_month)
      end
    end
  end
end
