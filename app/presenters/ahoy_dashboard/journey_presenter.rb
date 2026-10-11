module AhoyDashboard
  # The page journey: a row of columns you walk left to right, each one a list
  # of what people did next. Every link carries the whole state, so a journey
  # somebody is looking at can be sent to somebody else.
  #
  # Only the columns somebody has actually opened are drawn. The page opens as a
  # single list rather than six, five of which would be prompts asking to be
  # filled in, and past the last one there is a ghost saying what to do.
  class JourneyPresenter
    COLUMNS = AhoyDashboard::JourneyQuery::COLUMNS
    EXIT = AhoyDashboard::JourneyQuery::EXIT
    SEARCH_NAME = "find[]".freeze

    TITLE = "Page journey".freeze
    EXIT_LABEL = "Exited site".freeze

    # Past this many the breadcrumb elides from the front. The last three are
    # the ones that say where you are; the ones before them are how you got
    # here, and the chips are still in the URL either way.
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

      def bar_width
        (share.to_f * 100).round(2)
      end

      # Against everybody who reached this column, not everybody in the range:
      # the question a column answers is what this group did, so the share is of
      # this group.
      def percent
        presenter.percent(visitors, column.reached)
      end

      # Picking the step that is already picked drops it again, so a column can
      # be walked back without going to the address bar.
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

      # The first column is where everybody came in. Every one after it is read
      # against the step that opened it, so it says which.
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

      def cap_note
        return nil unless column&.more?

        "Showing the busiest #{presenter.limit}. Search to reach one that is not."
      end

      private

      attr_reader :presenter
    end

    attr_reader :query, :result

    def initialize(query:, result:)
      @query = query
      @result = result
    end

    delegate :chain, :limit, :entered, :ended, :ended?, :capped?, to: :result

    def title
      TITLE
    end

    def range_label
      query.range_label
    end

    def columns
      @columns ||= result.columns.each_with_index.map do |column, index|
        ColumnView.new(index: index, column: column, presenter: self)
      end
    end

    def any_chain?
      chain.any?
    end

    # The count the whole journey is measured against: how many people took the
    # first step, not how many were in the range. Everything downstream is a
    # share of the people who actually entered here.
    def entry_label
      chain.first&.value
    end

    # Everything downstream is measured against the people who took the first
    # step, not against everybody in the range. "13% of visitors who entered at
    # /" has to mean thirteen percent of the ones who entered at /, and reading
    # it off the range total instead answers a question nobody asked.
    def entry_count
      return entered if chain.empty?

      columns.first&.rows&.find(&:chosen?)&.visitors.to_i
    end

    def ended_percent
      percent(ended, entry_count)
    end

    # Where the walk got to, and how much of the entry survived to there. The
    # numbers come off the rows rather than the chain, so a step filtered out of
    # view by a search still reports what it was.
    def last_count
      return entered if chain.empty?

      columns.last&.rows&.find(&:chosen?)&.visitors || columns.last&.reached || entered
    end

    def kept_percent
      percent(last_count, entry_count)
    end

    # Chips for the bar over the columns. Elided from the front past three,
    # because the recent steps are the ones that say where you are.
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

    # The hidden fields a column's search form needs to leave the rest of the
    # state alone. Only the slots up to the one being typed in are emitted, and
    # they are in index order, because the terms travel as one list and a missing
    # slot would shift every term after it into the wrong column.
    def search_slots(index)
      last = [ index, result.searches.rindex(&:present?) || 0 ].max

      (0..last).map { |slot| [ slot, result.searches[slot].to_s ] }
    end

    def chain_fields
      chain.map(&:to_param)
    end

    def range_hint
      query.filters.any? ? "Try a wider date range, or drop one of the filters." : "Try a wider date range."
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    def count_label(value)
      "#{number(value)} #{"visitor".pluralize(value.to_i)}"
    end

    # Prints 100% rather than rounding to it, so a step everybody took does not
    # read as 99.5 and look like an error next to a step that genuinely lost
    # somebody.
    def percent(part, whole)
      return nil unless whole.to_i.positive?

      value = part.to_f / whole * 100

      return "100%" if value >= 99.5
      return "0%" if value.zero?
      return "<0.1%" if value.round(1) < 0.1

      value >= 10 ? "#{value.round}%" : "#{value.round(1)}%"
    end

    private

    def path(chain:, searches:)
      params = query.to_query
      params = params.merge(steps: chain.map(&:to_param)) if chain.any?
      terms = trimmed(searches)
      params = params.merge(find: terms) if terms.any?

      AhoyDashboard::Engine.routes.url_helpers.journey_path(params)
    end

    # A trailing blank term is nothing to carry, and dropping it keeps a plain
    # journey URL plain.
    def trimmed(searches)
      terms = Array(searches).map(&:to_s)
      terms.pop while terms.any? && terms.last.blank?

      terms
    end
  end
end
