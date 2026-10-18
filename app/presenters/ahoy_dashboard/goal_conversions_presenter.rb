module AhoyDashboard
  class GoalConversionsPresenter
    FRAME = "dash_goal_conversions".freeze
    ROWS = 9

    TITLE = "Goal conversions".freeze
    HINT = "Click a goal to filter".freeze

    COLUMNS = [
      { key: "visitors", label: "Visitors" },
      { key: "events", label: "Conversions" },
      { key: "conversion_rate", label: "Rate" }
    ].freeze

    class Row
      attr_reader :row

      def initialize(row:, presenter:)
        @row = row
        @presenter = presenter
      end

      delegate :label, :metrics, to: :row

      def goal
        presenter.goal_for(label)
      end

      def revenue?
        goal&.revenue?
      end

      def revenue
        return if !revenue? || metrics["revenue_total"].nil?

        AhoyDashboard::Metric.find("revenue_total").format(metrics["revenue_total"])
      end

      def visitors
        metrics["visitors"].to_i
      end

      def share
        presenter.share(visitors)
      end

      def uniques
        presenter.number(visitors)
      end

      def total
        presenter.number(metrics["events"])
      end

      def rate
        presenter.rate(metrics["conversion_rate"])
      end

      def filtered?
        presenter.filtered?(label)
      end

      def filter_params
        presenter.filter_params(label)
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :result

    def initialize(query:, result:, goals:)
      @query = query
      @result = result
      @goals = goals
    end

    def title
      TITLE
    end

    def hint
      HINT
    end

    def columns
      COLUMNS
    end

    def rows
      @rows ||= result.rows.map { |row| Row.new(row: row, presenter: self) }
    end

    def empty?
      rows.empty?
    end

    def any_goals?
      goals.any?
    end

    def goal_for(name)
      goals_by_name[name]
    end

    def share(visitors)
      AhoyDashboard::Share.fraction(visitors, of: busiest)
    end

    def filtered?(name)
      !applied_index(name).nil?
    end

    def filter_params(name)
      index = applied_index(name)
      return query.without_filter_params(index) unless index.nil?

      query.filter_link_params(AhoyDashboard::Dimension::GOAL_KEY, name)
    end

    def number(value)
      AhoyDashboard::CompactNumber.call(value)
    end

    def rate(value)
      return "" if value.nil?

      AhoyDashboard::Metric.find("conversion_rate").format(value.to_f)
    end

    private

    attr_reader :goals

    def goals_by_name
      @goals_by_name ||= goals.index_by(&:name)
    end

    def busiest
      @busiest ||= rows.map(&:visitors).max.to_i
    end

    def applied_index(name)
      applied = query.filters.groups.select(&:single?).map(&:first).find do |filter|
        filter.dimension.key == AhoyDashboard::Dimension::GOAL_KEY && filter.value == name
      end

      applied && query.filters.to_a.index { |filter| filter.equal?(applied) }
    end
  end
end
