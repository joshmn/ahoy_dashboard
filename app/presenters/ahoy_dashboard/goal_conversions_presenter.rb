module AhoyDashboard
  # The goal conversions card, which is its own section under the journey rather
  # than a panel in the grid.
  #
  # Goals are the one breakdown the dashboard draws full width, because the row
  # carries three numbers instead of one and a 554px card cannot hold them beside
  # a name. That is also why it is not a Report: a Report is a card with tabs in
  # a half-width column, and this has neither.
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

      # Printed beside the name rather than in a column of its own, because only
      # some goals carry money and an empty fourth column on every other row
      # reads as a number that failed to load.
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

    # The bar is a share of the busiest goal, like every other list on the
    # dashboard, rather than a share of everybody. Conversion rates are small
    # and a bar drawn against the visitor total would be a hairline on all of
    # them; the number beside it is already the honest one.
    def share(visitors)
      return 0.0 unless busiest.positive?

      (visitors.to_f / busiest).clamp(0.0, 1.0)
    end

    def filtered?(name)
      !applied_index(name).nil?
    end

    # Clicking a goal filters the whole dashboard by it, and clicking the one
    # already applied takes it off, so the row is the control both ways.
    def filter_params(name)
      return query.with(filters: removed(name).to_param).to_query if filtered?(name)

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

    def removed(name)
      query.filters.without(applied_index(name))
    end

    def applied_index(name)
      applied = query.filters.groups.select(&:single?).map(&:first).find do |filter|
        filter.dimension.key == AhoyDashboard::Dimension::GOAL_KEY && filter.value == name
      end

      applied && query.filters.to_a.index { |filter| filter.equal?(applied) }
    end
  end
end
