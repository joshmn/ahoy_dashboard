module AhoyDashboard
  class JourneyPresenter
    FRAME = "dash_journey".freeze
    SEARCH_NAME = "find[]".freeze

    TITLE = "Page journey".freeze
    EXIT_LABEL = "Exited site".freeze

    CRUMB_TAIL = 3

    class RowView
      delegate :value, :visitors, :share, :exit?, :chosen?, to: :row

      def initialize(row:, column:, presenter:)
        @row = row
        @column = column
        @presenter = presenter
      end

      def label
        exit? ? EXIT_LABEL : value
      end

      def count
        AhoyDashboard::CompactNumber.call(visitors)
      end

      def exact
        presenter.count_label(visitors)
      end

      def percent
        presenter.percent(visitors, column.reached)
      end

      def path
        chosen? ? presenter.drop_path(column) : presenter.pick_path(column, row)
      end

      def title
        return "Step back" if chosen?
        return "Visitors who left the site here" if exit?

        "Follow #{label}"
      end

      private

      attr_reader :row, :column, :presenter
    end

    class ColumnView
      def initialize(index:, column:, presenter:)
        @index = index
        @column = column
        @presenter = presenter
      end

      attr_reader :index, :column

      def id
        "tm-journey-col-#{index}"
      end

      def search_id
        "tm-journey-find-#{index}"
      end

      def step_label
        "Step #{index + 1}"
      end

      def heading
        index.zero? ? "Every page viewed" : nil
      end

      def after
        index.zero? ? nil : presenter.chain[index - 1]&.value
      end

      def search
        column&.search.to_s
      end

      def rows
        @rows ||= Array(column&.rows).map { |row| RowView.new(row: row, column: column, presenter: presenter) }
      end

      def empty?
        rows.empty?
      end

      def reached
        column&.reached.to_i
      end

      def empty_title
        return "Nothing matches that" if search.present?
        return "Nothing in this range" if index.zero?

        "Nobody went anywhere else"
      end

      def empty_hint
        return "Clear the search to see the busiest steps again." if search.present?
        return presenter.range_hint if index.zero?

        "Everybody who got here stopped here."
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :result

    def initialize(query:, result:)
      @query = query
      @result = result
    end

    delegate :chain, :entered, :ended, :ended?, :capped?, to: :result

    def title
      TITLE
    end

    def columns
      @columns ||= result.columns.each_with_index.map do |column, index|
        ColumnView.new(index: index, column: column, presenter: self)
      end
    end

    def any_chain?
      chain.any?
    end

    def entry_label
      chain.first&.value
    end

    def entry_count
      return entered if chain.empty?

      columns.first&.rows&.find(&:chosen?)&.visitors.to_i
    end

    def ended_percent
      percent(ended, entry_count)
    end

    def last_count
      return entered if chain.empty?

      columns.last&.rows&.find(&:chosen?)&.visitors || columns.last&.reached || entered
    end

    def kept_percent
      percent(last_count, entry_count)
    end

    def crumbs
      steps = chain.each_with_index.map do |step, index|
        {
          label: step.exit? ? EXIT_LABEL : step.value,
          exit: step.exit?,
          path: drop_path_at(index + 1)
        }
      end

      steps.size > CRUMB_TAIL ? steps.last(CRUMB_TAIL) : steps
    end

    def elided?
      chain.size > CRUMB_TAIL
    end

    def reset_path
      path(chain: [], searches: [])
    end

    def form_path
      AhoyDashboard::Engine.routes.url_helpers.journey_path
    end

    def pick_path(column, row)
      path(chain: column.chain + [ row.step ], searches: result.searches.first(column.index + 1))
    end

    def drop_path(column)
      path(chain: column.chain, searches: result.searches.first(column.index))
    end

    def drop_path_at(length)
      path(chain: chain.first(length), searches: result.searches.first(length))
    end

    def search_slots(index)
      last = [ index, result.searches.rindex(&:present?) || 0 ].max

      (0..last).map { |slot| [ slot, result.searches[slot].to_s ] }
    end

    def chain_fields
      chain.map(&:to_param)
    end

    def range_hint
      AhoyDashboard::RangeHint.call(query.filters)
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    def count_label(value)
      AhoyDashboard::Counted.call(value.to_i, noun: "visitor")
    end

    def percent(part, whole)
      AhoyDashboard::Share.label(part, of: whole.to_i)
    end

    private

    def path(chain:, searches:)
      params = query.to_query
      params = params.merge(steps: chain.map(&:to_param)) if chain.any?
      terms = trimmed(searches)
      params = params.merge(find: terms) if terms.any?

      AhoyDashboard::Engine.routes.url_helpers.journey_path(params)
    end

    def trimmed(searches)
      terms = Array(searches).map(&:to_s)
      terms.pop while terms.any? && terms.last.blank?

      terms
    end
  end
end
