module AhoyDashboard
  module Assistant
    class Window
      class UnknownPeriod < StandardError; end

      MAX_DAYS = 365
      DAY = "day".freeze

      def self.call(**options)
        new(**options)
      end

      def self.keys
        AhoyDashboard::Period::ALL.map(&:key) - [ AhoyDashboard::Period::CUSTOM_KEY ]
      end

      def self.described
        AhoyDashboard::Period::ALL.reject { |period| period.key == AhoyDashboard::Period::CUSTOM_KEY }
          .map { |period| { key: period.key, means: period.label } }
      end

      def initialize(period: nil, from: nil, to: nil, days: nil, interval: nil, compare: nil, slice: Slice.new)
        @asked = period.to_s.strip.presence
        @from = parse(from)
        @to = parse(to)
        @days = days
        @interval = interval.to_s.strip.presence
        @compare = compare
        @slice = slice
      end

      def form
        @form ||= AhoyDashboard::QueryForm.from_params(params)
      end

      delegate :range, :scope, :period, :filters, to: :form

      def interval
        form.interval
      end

      def label
        form.range_label
      end

      def days_covered
        ((range.end.to_date - range.begin.to_date).to_i + 1)
      end

      def link_params(**extra)
        form.to_query.merge(extra.reject { |_key, value| value.blank? })
      end

      def filter_labels
        FilterWording.labels(form.filters)
      end

      def filter_sentence
        FilterWording.sentence(form.filters)
      end

      def to_h
        {
          window: label, days: days_covered, interval: interval.to_s,
          crawlers: (form.include_crawlers? ? "included" : "excluded"),
          **FilterWording.hidden_traffic(form),
          filters: filter_labels.presence || "none, the whole site",
          filters_from: slice.from_label,
          filters_dropped: slice.dropped.presence
        }.compact
      end

      private

      attr_reader :asked, :from, :to, :slice

      def params
        window = dates || named || counted
        interval = @interval || (DAY if window[:period] == AhoyDashboard::Period::CUSTOM_KEY)

        { interval: interval, comparison: @compare }.merge(slice.form_params).merge(window)
      end

      def dates
        return nil if from.nil? && to.nil?

        first = from || to
        last = to || from
        first, last = last, first if first > last

        custom(first: first, last: last)
      end

      def named
        return nil if asked.blank?
        raise UnknownPeriod, asked if AhoyDashboard::Period.find_by_key(asked).nil?

        { period: asked }
      end

      def counted
        return { period: AhoyDashboard::Period::DEFAULT_KEY } if @days.blank?

        span = @days.to_i.clamp(1, MAX_DAYS)
        last = Time.current.in_time_zone(AhoyDashboard.time_zone).to_date

        custom(first: last - (span - 1), last: last)
      end

      def custom(first:, last:)
        { period: AhoyDashboard::Period::CUSTOM_KEY, from: first.strftime(AhoyDashboard::Period::DATE_FORMAT),
          to: last.strftime(AhoyDashboard::Period::DATE_FORMAT) }
      end

      def parse(value)
        return nil if value.blank?

        Date.strptime(value.to_s.strip, AhoyDashboard::Period::DATE_FORMAT)
      rescue ArgumentError, TypeError, RangeError
        nil
      end
    end
  end
end
