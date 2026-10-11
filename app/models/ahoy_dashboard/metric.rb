module AhoyDashboard
  # The six top-stat metrics, plus the two the goals card needs. ALL is the six,
  # because the stat strip and the top stats query iterate it; find resolves the
  # extras as well so a card can name "conversion_rate" as a column.
  class Metric
    include ActiveModel::Model

    DEFAULT_KEY = "visitors".freeze

    # Metrics where a fall is the good news, so the tile's change reads green
    # going down. Everything else is the other way round, which is why this is a
    # list of one rather than a flag on every metric.
    INVERTED = %w[bounce_rate].freeze

    attr_reader :key, :label, :short, :format_type

    def initialize(key:, label:, short:, format_type:)
      @key = key
      @label = label
      @short = short
      @format_type = format_type
    end

    ALL = [
      new(key: "visitors", label: "Unique visitors", short: "Visitors", format_type: :integer),
      new(key: "visits", label: "Total visits", short: "Visits", format_type: :integer),
      new(key: "pageviews", label: "Total pageviews", short: "Pageviews", format_type: :integer),
      new(key: "views_per_visit", label: "Views per visit", short: "Views/visit", format_type: :decimal),
      new(key: "bounce_rate", label: "Bounce rate", short: "Bounce rate", format_type: :percent),
      new(key: "visit_duration", label: "Visit duration", short: "Duration", format_type: :duration),
      new(key: "scroll_depth", label: "Scroll depth", short: "Scroll", format_type: :percent)
    ].freeze

    # Numbers that belong to a row rather than to a session, so they are
    # findable as a column without being charted or taking a tile in the strip.
    EXTRA = [
      new(key: "events", label: "Total conversions", short: "Events", format_type: :integer),
      new(key: "conversion_rate", label: "Conversion rate", short: "CR", format_type: :rate),
      new(key: "engagement_time", label: "Time on page", short: "Time", format_type: :duration),
      new(key: "revenue_total", label: "Revenue", short: "Revenue", format_type: :currency),
      new(key: "revenue_average", label: "Average revenue", short: "Avg", format_type: :currency)
    ].freeze

    INDEX = (ALL + EXTRA).index_by(&:key).freeze

    class << self
      def all
        ALL
      end

      def find(key)
        INDEX.fetch(key.to_s) { raise ActiveRecord::RecordNotFound, "no dashboard metric #{key}" }
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

    def chartable?
      ALL.include?(self)
    end

    def inverted?
      INVERTED.include?(key)
    end

    def format(value)
      number = value.to_f

      case format_type
      when :decimal then "%.2f" % number
      when :percent then "#{number.round}%"
      when :rate then "#{trim(number.round(1))}%"
      when :duration then duration(number)
      when :currency then ActiveSupport::NumberHelper.number_to_currency(number)
      else ActiveSupport::NumberHelper.number_to_delimited(number.round)
      end
    end

    def compact(value)
      return format(value) unless format_type == :integer

      AhoyDashboard::CompactNumber.call(value.to_f)
    end

    private

    def duration(number)
      total = number.round
      hours = total / 3600
      minutes = total % 3600 / 60
      seconds = total % 60

      return "#{hours}h #{minutes}m" if hours.positive?
      return "#{minutes}m #{seconds}s" if minutes.positive?

      "#{seconds}s"
    end

    def trim(number)
      (number % 1).zero? ? number.to_i : number
    end
  end
end
