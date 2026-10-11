module AhoyDashboard
  # The whole dashboard is one URL, so the query string is read once here and
  # every controller, link and frame src is built back out of it. Malformed URL
  # values fall back to defaults because people edit these by hand. Database
  # failures still surface.
  class QueryForm < AhoyDashboard::Form
    DEFAULT_PERIOD = "30d".freeze
    COMPARISONS = %w[previous_period year_over_year].freeze
    CRAWLERS_ON = "1".freeze
    INTERNAL_ON = "1".freeze
    NO_FILTERS = "none".freeze
    IS = "is".freeze

    # What a remembered view is allowed to carry. Filters are deliberately not on
    # the list. A filter is a question somebody asked once, and putting it back on
    # the next visit means every number on the page is quietly scoped to
    # something nobody asked for again, with a chip in the corner as the only
    # warning.
    VIEW_KEYS = %i[period interval metric comparison crawlers internal from to].freeze
    CLOCK_PATTERN = /\A\d{2}:\d{2}\z/

    # Any one of these in the URL and the URL wins whole, rather than the
    # remembered view filling in the keys it left out. to_query leaves defaults
    # out, so "?period=day" is not half a view: it is today with everything else
    # default, and that is what somebody following the link has to land on.
    URL_KEYS = (VIEW_KEYS + %i[filters]).freeze

    attribute :period_key, :string
    attribute :interval_key, :string
    attribute :metric_key, :string
    attribute :comparison_key, :string
    attribute :crawlers, :string
    attribute :internal, :string
    attribute :from, :string
    attribute :to, :string
    attribute :filters
    attribute :restored, :boolean, default: false

    def self.from_params(params, remembered: nil)
      source = normalize(params)
      view = remembered_view(remembered) unless URL_KEYS.any? { |key| source[key].present? }
      source = view if view.present?

      new(
        period_key: source[:period],
        interval_key: source[:interval],
        metric_key: source[:metric],
        comparison_key: source[:comparison],
        crawlers: source[:crawlers],
        internal: source[:internal],
        from: joined_bound(source[:from], source[:from_time]),
        to: joined_bound(source[:to], source[:to_time]),
        filters: parse_filters(source),
        restored: view.present?
      )
    end

    # The remembered view arrives as a query string and is read back in through
    # the same reader as the URL, so a cookie somebody has edited is worth
    # exactly what a hand-edited address bar is worth: a fall back to defaults.
    def self.remembered_view(remembered)
      parsed = remembered.is_a?(String) ? Rack::Utils.parse_nested_query(remembered) : remembered

      normalize(parsed).slice(*VIEW_KEYS).reject { |_key, value| value.blank? }
    rescue StandardError
      {}
    end
    private_class_method :remembered_view

    def self.normalize(params)
      hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
      hash.to_h.symbolize_keys
    rescue StandardError
      {}
    end
    private_class_method :normalize

    def self.joined_bound(date, time)
      date = date.to_s.strip
      time = time.to_s.strip
      return date.presence unless date.match?(AhoyDashboard::Period::DATE_PATTERN) && time.match?(CLOCK_PATTERN)

      "#{date}T#{time}"
    end
    private_class_method :joined_bound

    def self.parse_filters(source)
      return default_filters || AhoyDashboard::Filters.new([]) unless source.key?(:filters)

      AhoyDashboard::Filters.from_params(source)
    rescue ArgumentError, TypeError
      AhoyDashboard::Filters.new([])
    end
    private_class_method :parse_filters

    def self.default_filters
      AhoyDashboard::Segment.default&.to_filters.presence
    end

    def filters
      @filters ||= super || AhoyDashboard::Filters.new([])
    end

    def period
      @period ||= AhoyDashboard::Period.find_by_key(period_key) || AhoyDashboard::Period.default
    end

    def range
      @range ||= period.range(now: Time.current, from: from, to: to)
    end

    def interval
      @interval ||= period.interval_for(interval_key, range: range)
    end

    def intervals
      period.intervals_for(range)
    end

    def timed?
      period.timed?(from, to)
    end

    def range_label
      period.label_for(range, timed: timed?)
    end

    # What the date control says it is showing. A custom range says its own
    # bounds: "Custom range" is the name of the menu item somebody picked, not
    # the window they are looking at, and on a range dragged off the chart that
    # window is the one thing on the page nothing else prints.
    def period_label
      return period.running_label(range) unless period.custom?
      return range_label unless period.running?(range)

      "#{range_label} so far"
    end

    # What the custom range's own fields are filled with. A range dragged out of
    # the chart is minutes wide, so the fields have to be able to say minutes: a
    # date input rounds both ends to the day, and applying one silently widened
    # the window it was sitting there showing.
    def range_from_date
      zoned(range.begin).to_date.to_s
    end

    def range_from_time
      clock_field(zoned(range.begin))
    end

    def range_to_date
      stop = range_stop

      (midnight?(stop) ? stop - 1.day : stop).to_date.to_s
    end

    def range_to_time
      clock_field(range_stop)
    end

    def range_date_max
      zoned(Time.current).to_date.to_s
    end

    def range_from_field
      range_field(range.begin)
    end

    # A timed closing bound is held as the last instant inside the range, so it
    # goes back the way Period read it: one second past the end, floored to the
    # minute, which is the time somebody typed. A dated one is its own day, and
    # adding the second there rolls it onto the next.
    def range_to_field
      return range_field(range.end) unless timed?

      range_field(zoned(range.end) + 1.second)
    end

    def metric
      @metric ||= AhoyDashboard::Metric.find_by_key(metric_key) || AhoyDashboard::Metric.default
    end

    def comparison
      return @comparison if defined?(@comparison)

      @comparison = COMPARISONS.include?(comparison_key.to_s) ? comparison_key.to_sym : nil
    end

    def comparison_range
      return @comparison_range if defined?(@comparison_range)

      @comparison_range = comparison && period.comparison_range(range, comparison, now: comparison_now)
    end

    def include_crawlers?
      crawlers.to_s == CRAWLERS_ON
    end

    def include_internal?
      internal.to_s == INTERNAL_ON
    end

    def hidden_visits
      return 0 if include_internal?

      @hidden_visits ||= AhoyDashboard::HiddenVisitsQuery.call(range: range)
    end

    def restored?
      restored
    end

    def default_filters
      return @default_filters if defined?(@default_filters)

      @default_filters = self.class.default_filters
    end

    def defaulted?
      default_filters.present? && filters.to_param == default_filters.to_param
    end

    def filters_param
      return nil if defaulted?
      return filters.to_param if filters.any?

      NO_FILTERS if default_filters.present?
    end

    def carried_filters
      return filters.to_param if filters.any?

      NO_FILTERS if default_filters.present?
    end

    def scope
      @scope ||= AhoyDashboard::ScopeQuery.call(
        range: range,
        filters: filters,
        include_crawlers: include_crawlers?,
        include_internal: include_internal?
      )
    end

    def comparison_scope
      return @comparison_scope if defined?(@comparison_scope)

      @comparison_scope = comparison_range && AhoyDashboard::ScopeQuery.call(
        range: comparison_range,
        filters: filters,
        include_crawlers: include_crawlers?,
        include_internal: include_internal?
      )
    end

    # Everything a link needs to arrive at the view somebody is looking at now.
    # Defaults are left out so a plain /telemetry stays a plain URL.
    def to_query
      {
        period: period.key,
        interval: (interval.to_s unless interval == period.default_interval_for(range)),
        metric: (metric.key unless metric.key == AhoyDashboard::Metric.default.key),
        comparison: comparison&.to_s,
        crawlers: (CRAWLERS_ON if include_crawlers?),
        internal: (INTERNAL_ON if include_internal?),
        from: (from.presence if period.custom?),
        to: (to.presence if period.custom?),
        filters: filters_param
      }.compact
    end

    # The part of the view worth keeping until next time, in the same shape as
    # the query string so there is only one syntax to read. Blank when the
    # dashboard is sitting at its defaults: to_query always names the period, and
    # storing "this operator likes the default" would leave a Reset view control
    # on the bar forever with nothing to reset.
    def to_view
      params = to_query.slice(*VIEW_KEYS)
      params.delete(:period) if period.key == AhoyDashboard::Period.default.key

      params.to_query
    end

    def with(overrides)
      self.class.from_params(explicit_query.merge(overrides.to_h.symbolize_keys))
    end

    def filter_link_params(dimension_key, value)
      dimension = AhoyDashboard::Dimension.find_by_key(dimension_key)
      return to_query if dimension.nil?

      wanted = value.presence || dimension.unknown_label
      return to_query if applied?(dimension, wanted)

      filter = AhoyDashboard::Filter.new(dimension: dimension, operator: IS, value: wanted)
      to_query.merge(filters: filters.replacing(dimension.key, filter).to_param)
    end

    def without_filter(index)
      with(filters: filters.without(index).to_param.presence || NO_FILTERS)
    end

    def without_filter_params(index)
      remaining = filters.without(index.to_i)
      params = to_query
      return params.merge(filters: remaining.to_param) if remaining.any?

      default_filters.present? ? params.merge(filters: NO_FILTERS) : params.except(:filters)
    end

    def crawler_toggle_params
      include_crawlers? ? to_query.except(:crawlers) : to_query.merge(crawlers: CRAWLERS_ON)
    end

    def internal_toggle_params
      include_internal? ? to_query.except(:internal) : to_query.merge(internal: INTERNAL_ON)
    end

    def default_clear_params
      to_query.merge(filters: NO_FILTERS)
    end

    private

    def comparison_now
      now = Time.current
      return now if period.custom? || !period.running?(range, now: now)

      seconds = AhoyDashboard::ScopeQuery::TOTAL_TTL.to_i
      Time.at(now.to_i / seconds * seconds).in_time_zone
    end

    def zoned(time)
      time.in_time_zone(AhoyDashboard.time_zone)
    end

    def range_stop
      (zoned(range.end) + 1.second).beginning_of_minute
    end

    def clock_field(time)
      (time.strftime("%H:%M") unless midnight?(time))
    end

    def midnight?(time)
      time.hour.zero? && time.min.zero?
    end

    def range_field(time)
      moment = zoned(time)

      timed? ? moment.beginning_of_minute.strftime(AhoyDashboard::Period::TIME_FORMAT) : moment.to_date.to_s
    end

    def explicit_query
      to_query.merge(filters: filters.to_param)
    end

    def applied?(dimension, value)
      filters.pinned_index(dimension.key, value).present?
    end
  end
end
