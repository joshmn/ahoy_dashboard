module AhoyDashboard
  # The period menu. Same registry shape as the content pages (frozen ALL, find
  # raising RecordNotFound, to_param), plus the range arithmetic, which lives
  # here so the dashboard, the comparison and the export all cut time the same way.
  class Period
    include ActiveModel::Model

    DEFAULT_KEY = "30d".freeze
    CUSTOM_KEY = "custom".freeze
    DATE_FORMAT = "%Y-%m-%d".freeze
    TIME_FORMAT = "%Y-%m-%dT%H:%M".freeze
    DATE_PATTERN = /\A\d{4}-\d{1,2}-\d{1,2}\z/
    TIME_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/
    MAX_BUCKETS = 400

    RUNNING_LABELS = { "day" => "Today so far" }.freeze

    RUNNING_COMPARISONS = {
      previous_period: {
        day: "yesterday by this hour",
        span: "the %<days>s days before, same elapsed time",
        timed: "the period before, same elapsed time"
      },
      year_over_year: {
        day: "this day last year by this hour",
        span: "the same %<days>s days last year, same elapsed time",
        timed: "the same hours last year, same elapsed time"
      }
    }.freeze

    FINISHED_COMPARISONS = {
      previous_period: { day: "the day before", span: "the %<days>s days before", timed: "the previous period" },
      year_over_year: {
        day: "the same day last year",
        span: "the same %<days>s days last year",
        timed: "the same hours last year"
      }
    }.freeze

    attr_reader :key, :label, :chip_label, :interval, :intervals

    def initialize(key:, label:, chip_label:, interval:, intervals:)
      @key = key
      @label = label
      @chip_label = chip_label
      @interval = interval
      @intervals = intervals.freeze
    end

    ALL = [
      new(key: "realtime", label: "Realtime", chip_label: "Realtime",
          interval: :minute, intervals: %i[minute]),
      new(key: "day", label: "Today", chip_label: "Today",
          interval: :hour, intervals: %i[hour]),
      new(key: "yesterday", label: "Yesterday", chip_label: "Yesterday",
          interval: :hour, intervals: %i[hour]),
      new(key: "7d", label: "Last 7 days", chip_label: "7d",
          interval: :day, intervals: %i[hour day]),
      new(key: "28d", label: "Last 28 days", chip_label: "28d",
          interval: :day, intervals: %i[day week]),
      new(key: "30d", label: "Last 30 days", chip_label: "30d",
          interval: :day, intervals: %i[day week]),
      new(key: "month", label: "Month to date", chip_label: "MTD",
          interval: :day, intervals: %i[day week]),
      new(key: "last_month", label: "Last month", chip_label: "Last month",
          interval: :day, intervals: %i[day week]),
      new(key: "6mo", label: "Last 6 months", chip_label: "6mo",
          interval: :month, intervals: %i[week month]),
      new(key: "12mo", label: "Last 12 months", chip_label: "12mo",
          interval: :month, intervals: %i[week month]),
      new(key: "year", label: "Year to date", chip_label: "YTD",
          interval: :month, intervals: %i[week month]),
      new(key: "all", label: "All time", chip_label: "All time",
          interval: :month, intervals: %i[day week month]),
      new(key: CUSTOM_KEY, label: "Custom range", chip_label: "Custom",
          interval: :day, intervals: %i[minute five_minutes fifteen_minutes hour day week month])
    ].freeze

    INDEX = ALL.index_by(&:key).freeze

    class << self
      def all
        ALL
      end

      def find(key)
        INDEX.fetch(key.to_s) { raise ActiveRecord::RecordNotFound, "no dashboard period #{key}" }
      end

      def find_by_key(key)
        INDEX[key.to_s]
      end

      def default
        INDEX.fetch(DEFAULT_KEY)
      end
    end

    def to_param
      key
    end

    def custom?
      key == CUSTOM_KEY
    end

    def realtime?
      key == "realtime"
    end

    def intervals_for(range)
      return intervals unless custom? && range

      span = (range.end - range.begin).round
      fitting = intervals.select do |candidate|
        length = AhoyDashboard::Sql::Buckets::LENGTHS.fetch(candidate).to_i
        length <= span && (span.to_f / length).ceil <= MAX_BUCKETS
      end

      fitting.presence || [ intervals.first ]
    end

    def default_interval_for(range)
      custom? && range ? intervals_for(range).first : interval
    end

    def interval_for(candidate, range: nil)
      wanted = candidate.to_s.presence&.to_sym

      intervals_for(range).include?(wanted) ? wanted : default_interval_for(range)
    end

    def range(now: Time.current, from: nil, to: nil)
      now = now.in_time_zone(AhoyDashboard.time_zone)

      case key
      when "realtime" then (now - 30.minutes)..now
      when "day" then now.beginning_of_day..now.end_of_day
      when "yesterday" then whole_day(now - 1.day)
      when "7d" then (now - 6.days).beginning_of_day..now.end_of_day
      when "28d" then (now - 27.days).beginning_of_day..now.end_of_day
      when "month" then now.beginning_of_month..now.end_of_day
      when "last_month" then whole_month(now - 1.month)
      when "6mo" then (now - 5.months).beginning_of_month..now.end_of_day
      when "12mo" then (now - 11.months).beginning_of_month..now.end_of_day
      when "year" then now.beginning_of_year..now.end_of_day
      when "all" then everything(now)
      when CUSTOM_KEY then custom(now, from, to)
      else last_30_days(now)
      end
    end

    def running?(range, now: Time.current)
      return false if realtime? || range.nil?

      range.begin <= now && now < range.end
    end

    def elapsed_range(range, now: Time.current)
      running?(range, now: now) ? range.begin..now : range
    end

    def comparison_range(range, mode, now: Time.current)
      return nil if realtime? || range.nil? || mode.blank?

      finish = elapsed_range(range, now: now).end

      case mode.to_sym
      when :previous_period
        length = (range.end - range.begin).ceil
        (range.begin - length)..(finish - length)
      when :year_over_year
        (range.begin - 1.year)..(finish - 1.year)
      end
    end

    def comparison_phrase(range, mode, now: Time.current)
      return nil if realtime? || range.nil? || mode.blank?

      wording = running?(range, now: now) ? RUNNING_COMPARISONS : FINISHED_COMPARISONS
      phrase = wording.dig(mode.to_sym, shape_of(range))

      phrase && format(phrase, days: ActiveSupport::NumberHelper.number_to_delimited(days_in(range)))
    end

    def running_label(range, now: Time.current)
      return label unless running?(range, now: now)

      RUNNING_LABELS.fetch(key) { custom? ? "#{label_for(range)} so far" : label }
    end

    def timed?(from, to)
      custom? && custom_bounds(from, to).present? && [ from, to ].any? { |bound| bound.to_s.match?(TIME_PATTERN) }
    end

    def label_for(range, timed: false)
      return "Last 30 minutes" if realtime?
      return label if range.nil?
      return times_label(range) if timed

      first = range.begin.in_time_zone(AhoyDashboard.time_zone).to_date
      last = range.end.in_time_zone(AhoyDashboard.time_zone).to_date

      return first.strftime("%b %-d, %Y") if first == last
      return first.strftime("%B %Y") if whole_calendar_month?(first, last)
      return "#{first.strftime("%b %-d")} to #{last.strftime("%b %-d")}" if first.year == last.year

      "#{first.strftime("%b %-d, %Y")} to #{last.strftime("%b %-d, %Y")}"
    end

    private

    def days_in(range)
      zone = AhoyDashboard.time_zone

      (range.end.in_time_zone(zone).to_date - range.begin.in_time_zone(zone).to_date).to_i + 1
    end

    def shape_of(range)
      return :timed unless whole_days?(range)

      days_in(range) == 1 ? :day : :span
    end

    def whole_days?(range)
      zone = AhoyDashboard.time_zone
      first = range.begin.in_time_zone(zone)
      last = range.end.in_time_zone(zone)

      first == first.beginning_of_day && (last.end_of_day - last) < 1
    end

    def whole_day(time)
      time.beginning_of_day..time.end_of_day
    end

    def whole_month(time)
      time.beginning_of_month..time.end_of_month
    end

    def last_30_days(now)
      (now - 29.days).beginning_of_day..now.end_of_day
    end

    def everything(now)
      earliest = AhoyDashboard.visit.minimum(:started_at)

      (earliest || now).in_time_zone(AhoyDashboard.time_zone).beginning_of_day..now.end_of_day
    end

    # This is a URL people edit by hand, so a range that will not parse or reads
    # backwards falls back to the default rather than raising or querying nothing.
    def custom(now, from, to)
      custom_bounds(from, to) || last_30_days(now)
    end

    def custom_bounds(from, to)
      first = opening(from)
      last = closing(to)
      return if first.nil? || last.nil? || first > last

      first..last
    end

    def opening(value)
      text = value.to_s
      return moment(text) if text.match?(TIME_PATTERN)

      day(text)
    end

    def closing(value)
      text = value.to_s
      return moment(text)&.yield_self { |time| (time - 1.minute).end_of_minute } if text.match?(TIME_PATTERN)

      day(text)&.end_of_day
    end

    def moment(text)
      AhoyDashboard.time_zone.strptime(text, TIME_FORMAT).beginning_of_minute
    rescue ArgumentError, TypeError, RangeError
      nil
    end

    def day(text)
      return unless text.match?(DATE_PATTERN)

      Date.strptime(text, DATE_FORMAT).in_time_zone(AhoyDashboard.time_zone)
    rescue ArgumentError, TypeError, RangeError
      nil
    end

    def times_label(range)
      first = range.begin.in_time_zone(AhoyDashboard.time_zone)
      stop = (range.end.in_time_zone(AhoyDashboard.time_zone) + 1.second).beginning_of_minute
      opening = "#{first.strftime("%b %-d")}, #{clock(first)}"
      same_day = stop.to_date == first.to_date || (midnight?(stop) && stop.to_date == first.to_date + 1)

      return "#{opening} to #{clock(stop)}" if same_day

      "#{opening} to #{stop.strftime("%b %-d")}, #{clock(stop)}"
    end

    def midnight?(time)
      time.hour.zero? && time.min.zero?
    end

    def clock(time)
      return "midnight" if midnight?(time)

      time.strftime(time.min.zero? ? "%-l %p" : "%-l:%M %p")
    end

    def whole_calendar_month?(first, last)
      first == first.beginning_of_month && last == last.end_of_month &&
        first.year == last.year && first.month == last.month
    end
  end
end
