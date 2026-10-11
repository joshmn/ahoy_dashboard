module AhoyDashboard
  module Reports
    class DigestPresenter
      UP = "#0a7250".freeze
      DOWN = "#b42318".freeze
      LEVEL = "#6b7280".freeze

      PREVIOUS = { daily: "the day before", weekly: "the week before", monthly: "the month before" }.freeze

      Tile = Data.define(:key, :label, :value, :change, :direction, :color)
      Row = Data.define(:label, :value, :share)
      List = Data.define(:key, :title, :dimension_key, :rows)

      attr_reader :result, :host

      def initialize(result, host:)
        @result = result
        @host = host
      end

      def empty?
        result.empty?
      end

      def period
        result.window.period
      end

      def cadence
        period.to_s.capitalize
      end

      def subject
        "Traffic for #{short_period}: #{visitors}"
      end

      def headline
        visitors
      end

      def summary
        return "Nothing came in, and nothing came in #{PREVIOUS.fetch(period)} either." if empty? && was_empty?
        return "Nothing came in. #{previous_visitors} #{PREVIOUS.fetch(period)}." if empty?

        [ change_sentence, second_sentence ].compact.join(" ")
      end

      def preheader
        "#{headline}. #{summary}"
      end

      def period_heading
        case period
        when :daily then day(window.starts_on, weekday: true)
        when :weekly then "#{day(window.starts_on, weekday: true)} to #{day(window.ends_on, weekday: true)}"
        when :monthly then window.starts_on.strftime("%B %Y")
        end
      end

      def tiles
        @tiles ||= result.stats.map do |stat|
          Tile.new(key: stat.metric.key, label: stat.metric.short, value: stat.metric.format(stat.value),
                   change: change_label(stat), direction: direction(stat), color: color(stat))
        end
      end

      def lists
        @lists ||= result.lists.select(&:any?).map do |list|
          List.new(key: list.key, title: list.title, dimension_key: list.dimension.key,
                   rows: list.rows.map { |row| row_for(row) })
        end
      end

      def nothing_listed?
        lists.empty?
      end

      def nothing_listed_note
        return "Nobody came, so there is nothing to list." if empty?

        "Nothing came through with a page, a source or a country on it."
      end

      def footer
        "You get this #{period} because traffic emails are on for #{host}."
      end

      def scope_note
        "The whole site, crawlers left out. No filter or segment applies."
      end

      private

      def window
        result.window
      end

      def row_for(row)
        Row.new(label: row.label, value: count(row.visitors, "visitor"), share: row.share.round)
      end

      def visitors
        count(result.visitors, "visitor")
      end

      def previous_visitors
        count(result.stat("visitors")&.comparison_value.to_i, "visitor")
      end

      def was_empty?
        result.stat("visitors")&.comparison_value.to_i.zero?
      end

      # The four tiles carry their own changes, so the line under the headline
      # says the one thing a number cannot: which way this is going, and by how
      # much against a period somebody can name.
      def change_sentence
        stat = result.stat("visitors")
        return "There is nothing to compare it with yet." if stat.nil? || stat.change.nil?
        return "Level with #{PREVIOUS.fetch(period)}." if stat.change.zero?

        "#{stat.change.positive? ? "Up" : "Down"} #{stat.change.abs}% on #{PREVIOUS.fetch(period)}."
      end

      def second_sentence
        views = result.stat("pageviews")
        return if views.nil? || views.value.to_i.zero?

        "#{ActiveSupport::NumberHelper.number_to_delimited(views.value)} #{"pageview".pluralize(views.value)} in all."
      end

      def change_label(stat)
        return if stat.change.nil?
        return "Level" if stat.change.zero?

        "#{stat.change.positive? ? "+" : "-"}#{stat.change.abs}%"
      end

      def direction(stat)
        return :none if stat.change.nil?
        return :level if stat.change.zero?

        stat.change.positive? ? :up : :down
      end

      # Bounce rate is the one that reads the other way round: a fall is the good
      # news, which is why the colour comes off the metric rather than the sign.
      def color(stat)
        return LEVEL if stat.change.nil? || stat.change.zero?

        good = stat.metric.inverted? ? stat.change.negative? : stat.change.positive?
        good ? UP : DOWN
      end

      def short_period
        case period
        when :daily then day(window.starts_on)
        when :weekly then "#{day(window.starts_on)} to #{day(window.ends_on)}"
        when :monthly then window.starts_on.strftime("%B")
        end
      end

      def day(date, weekday: false)
        date.strftime(weekday ? "%a, %b %-d" : "%b %-d")
      end

      def count(number, word)
        "#{ActiveSupport::NumberHelper.number_to_delimited(number)} #{word.pluralize(number)}"
      end
    end
  end
end
